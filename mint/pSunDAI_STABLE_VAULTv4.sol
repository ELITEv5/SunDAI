// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║           pSunDAIVault ASA V4 Autonomous Stable Asset            ║
 * ║                                                                  ║
 * ║   Immutable Stable Vault — PulseChain Autonomous ELite Edition   ║
 * ║   - Powered by pSunDAIoraclePLSX4                                ║
 * ║   - Self-refreshing oracle, always-on, fully autonomous          ║
 * ║   - One-click UX: Deposit+Mint, Repay+Withdraw, Auto-Repair      ║
 * ║   - Built for perfect UX and safety — no keys, no admin          ║
 * ║                                                                  ║
 * ║   Dev:     ELITE TEAM6                                           ║
 * ║   Website: https://www.sundaitoken.com                           ║
 * ║   Docs:    https://github.com/ELITEv5/SunDAI                     ║
 * ║   License: MIT | Autonomous | Immutable                          ║
 * ╚══════════════════════════════════════════════════════════════════╝
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./pSunDAI_ASA_Token.sol";
import "./pSunDAIoraclePLSX4.sol";

interface IWPLS {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

contract pSunDAIVault_ASA_v4 is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IERC20 public immutable wpls;
    pSunDAI public immutable psundai;
    pSunDAIoraclePLSX4 public immutable oracle;

    string public constant VERSION = "pSunDAIVault_ASA_v4";
    uint256 public constant COLLATERAL_RATIO = 150;
    uint256 public constant LIQUIDATION_RATIO = 110;
    uint256 public constant MIN_ACTION_AMOUNT = 1e14;
    uint256 public constant WITHDRAW_COOLDOWN = 300;
    uint256 public constant MIN_PRICE = 1e12;
    uint256 public constant MAX_PRICE = 1000e18;
    uint256 public constant MIN_LIQUIDATION_BPS = 2000;
    uint256 public constant MIN_BONUS_BPS = 200;
    uint256 public constant MAX_BONUS_BPS = 500;
    uint256 public constant AUCTION_TIME = 3 hours;
    uint256 public constant LIQUIDATION_COOLDOWN = 600;
    uint256 public constant MIN_SYSTEM_HEALTH = 130; // 130% minimum system-wide collateral ratio


    struct Vault {
        uint256 collateral;
        uint256 debt;
        uint256 lastDepositTime;
        uint256 lastWithdrawTime;
        uint256 lastLiquidationTime;
        uint256 lastDebtAccrual;

    }

    mapping(address => Vault) public vaults;
    uint256 public lastSafePrice = 1e18;
    // ---- Global system tracking ----
uint256 public totalCollateral;
uint256 public totalDebt;

// ---- Stability fee configuration ----
uint256 public constant STABILITY_FEE_BPS = 50; // 0.5% annual fee
uint256 public constant SECONDS_PER_YEAR = 31_536_000; // 365 days

    /// @notice Returns true if oracle has been stale for > 24h
function _oracleStale() internal view returns (bool) {
    (, uint256 ts) = oracle.peekPriceView();
    return (block.timestamp - ts) > 24 hours;
}

/// @notice Accrues time-based stability fee on vault debt (final autonomous-safe version)
function _accrueInterest(Vault storage v) internal {
    // 1. Skip if no debt (nothing to accrue)
    if (v.debt == 0) {
        v.lastDebtAccrual = block.timestamp;
        return;
    }

    // 2. Compute elapsed time since last accrual
    uint256 elapsed = block.timestamp - v.lastDebtAccrual;
    if (elapsed == 0) return;

    // 3. Calculate proportional stability fee
    uint256 fee = (v.debt * STABILITY_FEE_BPS * elapsed)
        / (SECONDS_PER_YEAR * 10_000);

    // 4. Guarantee forward time progression (no rounding freeze)
    if (fee == 0 && elapsed > 0) fee = 1;

    // 5. Apply fee to vault + system totals
    v.debt += fee;
    totalDebt += fee;
    v.lastDebtAccrual = block.timestamp;

    // 6. Dust forgiveness — clear trivial residuals (< 1e12 wei)
    if (v.debt <= 1e12) {
        totalDebt -= v.debt;
        v.debt = 0;
    }
}






    event Deposit(address indexed user, uint256 amount, uint256 ratio);
    event Withdraw(address indexed user, uint256 amount, uint256 ratio);
    event Mint(address indexed user, uint256 amount, uint256 ratio);
    event Repay(address indexed user, uint256 amount, uint256 ratio);
    event Liquidation(address indexed user, uint256 repayAmount, address indexed liquidator, uint256 reward, uint256 ratio);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(address _wpls, address _psundai, address _oracle) {
        require(_wpls != address(0) && _psundai != address(0) && _oracle != address(0), "Invalid address");
        wpls = IERC20(_wpls);
        psundai = pSunDAI(_psundai);
        oracle = pSunDAIoraclePLSX4(_oracle);
    }

    function _checkedPrice() internal returns (uint256) {
    (uint256 p,) = oracle.getPriceWithTimestamp();

    // --- Oracle now returns 1e18-scaled USD/PLS directly ---
    // No normalization needed here

    // --- Bootstrap: accept oracle if still defaulting near zero on first use ---
    if (lastSafePrice == 1e18 && p < 1e17) {
        lastSafePrice = p;
        return p;
    }

    // --- Clamp against lastSafePrice to prevent flash deviations ---
    // Allows only ±10% change per update
    if (p == 0 || p < (lastSafePrice * 90) / 100 || p > (lastSafePrice * 110) / 100) {
        p = lastSafePrice;
    }

    // --- Enforce hard min/max bounds for sanity ---
    if (p < MIN_PRICE || p > MAX_PRICE) {
        p = lastSafePrice;
    }

    // --- Update and return safe value ---
    lastSafePrice = p;
    return p;
}





    function depositPLS() external payable nonReentrant {
        require(msg.value >= MIN_ACTION_AMOUNT, "Invalid amount");
        IWPLS(address(wpls)).deposit{value: msg.value}();
        _addCollateral(msg.sender, msg.value);
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount >= MIN_ACTION_AMOUNT, "Invalid amount");
        wpls.safeTransferFrom(msg.sender, address(this), amount);
        _addCollateral(msg.sender, amount);
    }

    function _addCollateral(address user, uint256 amount) internal {
        Vault storage v = vaults[user];
        v.collateral += amount;
        v.lastDepositTime = block.timestamp;
        totalCollateral += amount;
        emit Deposit(user, amount, _collateralRatio(user));
    }

    function depositAndAutoMintPLS() external payable nonReentrant {
        require(msg.value >= MIN_ACTION_AMOUNT, "Invalid amount");
        require(!_oracleStale(), "Mint paused: oracle stale >24h");
        IWPLS(address(wpls)).deposit{value: msg.value}();
        _addCollateral(msg.sender, msg.value);
        uint256 price = _checkedPrice();
        uint256 collateralValueUSD = (msg.value * price) / 1e18;
        uint256 mintAmount = (collateralValueUSD * 100) / 155;
        if (mintAmount == 0) return;
        Vault storage v = vaults[msg.sender];
        v.debt += mintAmount;
        totalDebt += mintAmount;
        psundai.mint(msg.sender, mintAmount);
        emit Mint(msg.sender, mintAmount, _collateralRatio(msg.sender));
    }

    function mint(uint256 amount) external nonReentrant {
        Vault storage v = vaults[msg.sender];
        require(amount > 0, "Invalid mint");
        require(!_oracleStale(), "Mint paused: oracle stale >24h");
        _accrueInterest(v);
if (v.debt == 0) v.lastDebtAccrual = block.timestamp;
require(systemHealth() >= MIN_SYSTEM_HEALTH, "Mint paused: system undercollateralized");
        uint256 price = _checkedPrice();
        require(_isSafePrice(v.collateral, v.debt + amount, price), "Not enough collateral");
        v.debt += amount;
        psundai.mint(msg.sender, amount);
        totalDebt += amount;
        emit Mint(msg.sender, amount, _collateralRatio(msg.sender));
    }

    function repay(uint256 amount) external nonReentrant {
    Vault storage v = vaults[msg.sender];
    require(amount > 0 && v.debt >= amount, "Invalid repay");
    _accrueInterest(v);

    psundai.burn(msg.sender, amount);
    v.debt -= amount;
    totalDebt -= amount;

    emit Repay(msg.sender, amount, _collateralRatio(msg.sender));
}


    function withdrawPLS(uint256 amount) external nonReentrant {
    Vault storage v = vaults[msg.sender];
    require(amount > 0 && v.collateral >= amount, "Invalid withdraw");
    require(block.timestamp > v.lastDepositTime + WITHDRAW_COOLDOWN, "Cooldown");

    // 🚨 NEW SAFETY GUARD
    require(!_oracleStale() || v.debt == 0, "Withdraw paused: oracle stale");

    v.collateral -= amount;
    totalCollateral -= amount;
    require(_isSafe(v.collateral, v.debt), "Unsafe");
    v.lastWithdrawTime = block.timestamp;

    IWPLS(address(wpls)).withdraw(amount);
    payable(msg.sender).transfer(amount);

    emit Withdraw(msg.sender, amount, _collateralRatio(msg.sender));
}


    function withdrawWPLS(uint256 amount) external nonReentrant {
    Vault storage v = vaults[msg.sender];
    require(amount > 0 && v.collateral >= amount, "Invalid withdraw");
    require(block.timestamp > v.lastDepositTime + WITHDRAW_COOLDOWN, "Cooldown");

    // 🚨 NEW SAFETY GUARD
    require(!_oracleStale() || v.debt == 0, "Withdraw paused: oracle stale");

    v.collateral -= amount;
    require(_isSafe(v.collateral, v.debt), "Unsafe");
    v.lastWithdrawTime = block.timestamp;

    wpls.safeTransfer(msg.sender, amount);

    emit Withdraw(msg.sender, amount, _collateralRatio(msg.sender));
}


    function repayAndAutoWithdraw(uint256 repayAmount) external nonReentrant {
    Vault storage v = vaults[msg.sender];
    _accrueInterest(v);
    require(repayAmount > 0 && v.debt >= repayAmount, "Invalid repay");

    // Burn user’s pSunDAI
    psundai.burn(msg.sender, repayAmount);

    // Update vault and system debt accounting
    v.debt -= repayAmount;
    totalDebt -= repayAmount;

    // --- Dust forgiveness ---
    // If residual debt is less than 1e12 (≈ 0.000000000001 pSunDAI), treat as fully repaid
    if (v.debt <= 1e12) {
        totalDebt -= v.debt; // remove the tiny residual debt from system total
        v.debt = 0;
    }

    uint256 price = _checkedPrice();

    // --- Full repayment case ---
    if (v.debt == 0) {
        uint256 amt = v.collateral;
        totalCollateral -= amt;

        // Reset vault cleanly for gas refund
        delete vaults[msg.sender];

        IWPLS(address(wpls)).withdraw(amt);
        payable(msg.sender).transfer(amt);

        emit EmergencyWithdraw(msg.sender, amt);
        return;
    }

    // --- Partial repayment case ---
    uint256 requiredCollateral = (v.debt * COLLATERAL_RATIO * 1e18) / (price * 100);
    if (v.collateral > requiredCollateral) {
        uint256 withdrawable = v.collateral - requiredCollateral;
        v.collateral = requiredCollateral;
        totalCollateral -= withdrawable;

        IWPLS(address(wpls)).withdraw(withdrawable);
        payable(msg.sender).transfer(withdrawable);

        emit Withdraw(msg.sender, withdrawable, _collateralRatio(msg.sender));
    }

    emit Repay(msg.sender, repayAmount, _collateralRatio(msg.sender));
}




    


    function repayToHealth(address user) external view returns (uint256 repayNeeded) {
        Vault storage v = vaults[user];
        if (v.debt == 0) return 0;
        (uint256 p, uint256 ts) = oracle.peekPriceView();
        uint256 price = (block.timestamp - ts > 300 || p == 0) ? lastSafePrice : p;
        uint256 requiredDebt = (v.collateral * price * 100) / (COLLATERAL_RATIO * 1e18);
        if (v.debt > requiredDebt) repayNeeded = v.debt - requiredDebt;
    }

    function autoRepayToHealth() external nonReentrant {
        Vault storage v = vaults[msg.sender];
        if (v.debt == 0) return;
        uint256 price = _checkedPrice();
        uint256 requiredDebt = (v.collateral * price * 100) / (COLLATERAL_RATIO * 1e18);
        if (v.debt > requiredDebt) {
            uint256 repayAmt = v.debt - requiredDebt;
            psundai.burn(msg.sender, repayAmt);
            v.debt -= repayAmt;
            emit Repay(msg.sender, repayAmt, _collateralRatio(msg.sender));
        }
    }

    function liquidate(address user, uint256 repayAmount) external nonReentrant {
    Vault storage v = vaults[user];
    _accrueInterest(v);

    // --- Preconditions ---
    require(!_isSafe(v.collateral, v.debt), "Vault safe");
    require(v.debt > 0, "No debt");
    require(repayAmount > 0 && repayAmount <= v.debt, "Invalid repay");
    require(repayAmount * 10000 >= v.debt * MIN_LIQUIDATION_BPS, "Below min repay");
    require(block.timestamp > v.lastLiquidationTime + LIQUIDATION_COOLDOWN, "Cooldown");
    require(!_oracleStale(), "Liquidations paused: oracle stale >24h");

    // --- Price + Collateral math ---
    uint256 price = _checkedPrice();
    uint256 baseCollateral = Math.mulDiv(repayAmount, 1e18, price);

    // Bonus dynamically increases over time since last withdrawal
    uint256 timeElapsed = block.timestamp - v.lastWithdrawTime;
    if (timeElapsed > AUCTION_TIME) timeElapsed = AUCTION_TIME;

    uint256 bonusBps = MIN_BONUS_BPS + ((MAX_BONUS_BPS - MIN_BONUS_BPS) * timeElapsed / AUCTION_TIME);
    uint256 bonus = (baseCollateral * bonusBps) / 10000;
    uint256 totalReward = baseCollateral + bonus;

    // Cap reward to vault’s available collateral
    if (totalReward > v.collateral) totalReward = v.collateral;

    // --- Apply state changes ---
    psundai.burn(msg.sender, repayAmount);
    v.debt -= repayAmount;
    totalDebt -= repayAmount;

    v.collateral -= totalReward;
    totalCollateral -= totalReward;

    v.lastLiquidationTime = block.timestamp;

    // --- Transfer liquidator reward ---
    IWPLS(address(wpls)).withdraw(totalReward);
    payable(msg.sender).transfer(totalReward);

    emit Liquidation(user, repayAmount, msg.sender, totalReward, _collateralRatio(user));
}


    function canLiquidate(address user) public view returns (bool) {
        Vault storage v = vaults[user];
        if (v.debt == 0) return false;
        (uint256 p,) = oracle.peekPriceView();
        uint256 price = p > 0 ? p : lastSafePrice;
        uint256 ratio = (v.collateral * price * 100) / (v.debt * 1e18);
        return ratio < LIQUIDATION_RATIO;
    }

    function liquidationInfo(address user) external view returns (uint256 debt, uint256 minRepay, uint256 reward, uint256 bonusBps) {
        Vault storage v = vaults[user];
        if (v.debt == 0) return (0, 0, 0, 0);
        (uint256 p, uint256 ts) = oracle.peekPriceView();
        uint256 price = (block.timestamp - ts > 300 || p == 0) ? lastSafePrice : p;
        uint256 minRepayAmt = (v.debt * MIN_LIQUIDATION_BPS) / 10000;
        uint256 baseCollateral = Math.mulDiv(minRepayAmt, 1e18, price);
        uint256 timeElapsed = block.timestamp - v.lastWithdrawTime;
        if (timeElapsed > AUCTION_TIME) timeElapsed = AUCTION_TIME;
        bonusBps = MIN_BONUS_BPS + ((MAX_BONUS_BPS - MIN_BONUS_BPS) * timeElapsed / AUCTION_TIME);
        uint256 bonus = (baseCollateral * bonusBps) / 10000;
        reward = baseCollateral + bonus;
        return (v.debt, minRepayAmt, reward, bonusBps);
    }

    function systemStatus(address user) external view returns (bool oracleHealthy, uint256 price, uint256 ratio, uint256 mintable, uint256 collateralUSD) {
        Vault storage v = vaults[user];
        (uint256 p, uint256 ts) = oracle.peekPriceView();
        price = (block.timestamp - ts > 300 || p == 0) ? lastSafePrice : p;
        oracleHealthy = (block.timestamp - ts <= 600);
        ratio = v.debt == 0 ? type(uint256).max : (v.collateral * price * 100) / (v.debt * 1e18);
        uint256 collateralValueUSD = (v.collateral * price) / 1e18;
        uint256 safeDebtLimit = (collateralValueUSD * 100) / COLLATERAL_RATIO;
        mintable = safeDebtLimit > v.debt ? safeDebtLimit - v.debt : 0;
        collateralUSD = collateralValueUSD;
    }
    /// @notice Returns overall system collateralization ratio
function systemHealth() public view returns (uint256 systemRatio) {
    if (totalDebt == 0) return type(uint256).max;

    (uint256 p,) = oracle.peekPriceView();
    // Oracle already returns 1e18-scaled USD/PLS, no normalization needed
    uint256 price = p > 0 ? p : lastSafePrice;

    // Ratio = (Collateral Value / Total Debt) * 100
    // Collateral Value = totalCollateral * price / 1e18
    systemRatio = (totalCollateral * price * 100) / (totalDebt * 1e18);
}


    /**
     * @notice Returns the maximum additional pSunDAI a user can safely mint right now.
     * @dev Read-only, purely for frontend display — does not modify state.
     * @param user The address of the vault owner.
     * @return maxMintable The maximum additional pSunDAI mintable (1e18 precision).
     */
    function maxMint(address user) external view returns (uint256 maxMintable) {
    Vault storage v = vaults[user];
    if (v.collateral == 0) return 0;

    (uint256 p, uint256 ts) = oracle.peekPriceView();
    // Oracle already returns 1e18-scaled USD/PLS price — no normalization needed

    uint256 price = (block.timestamp - ts > 300 || p == 0) ? lastSafePrice : p;

    uint256 collateralValueUSD = (v.collateral * price) / 1e18;
    uint256 safeDebtLimit = (collateralValueUSD * 100) / COLLATERAL_RATIO;

    if (v.debt >= safeDebtLimit) return 0;

    maxMintable = safeDebtLimit - v.debt;
}




    function _collateralRatio(address user) internal view returns (uint256) {
        Vault storage v = vaults[user];
        if (v.debt == 0) return type(uint256).max;
        uint256 price = lastSafePrice > 0 ? lastSafePrice : _peekSafePrice();
        return (v.collateral * price * 100) / (v.debt * 1e18);
    }

    function _isSafe(uint256 col, uint256 debt) internal returns (bool) {
        if (debt == 0) return true;
        uint256 price = _checkedPrice();
        return col * price * 100 >= debt * COLLATERAL_RATIO * 1e18;
    }

    function _isSafePrice(uint256 col, uint256 debt, uint256 price) internal pure returns (bool) {
        if (debt == 0) return true;
        return col * price * 100 >= debt * COLLATERAL_RATIO * 1e18;
    }

    function _peekSafePrice() internal view returns (uint256) {
        (uint256 p,) = oracle.peekPriceView();
        return p > 0 ? p : lastSafePrice;
    }
        /**
     * @notice Emergency unlock if oracle fails or vault is idle too long
     * @dev Only works for fully repaid vaults after 30 days of inactivity
     */
    function emergencyUnlock() external nonReentrant {
        Vault storage v = vaults[msg.sender];
        require(v.debt == 0, "Repay debt first");
        require(v.collateral > 0, "No collateral");
        require(block.timestamp > v.lastDepositTime + 30 days, "Vault recently active");

        uint256 amt = v.collateral;
        v.collateral = 0;

        IWPLS(address(wpls)).withdraw(amt);
        payable(msg.sender).transfer(amt);

        emit EmergencyWithdraw(msg.sender, amt);
    }

    /**
     * @notice Frontend helper: returns full vault + system info for a user
     * @param user The address of the vault owner
     * @return collateral Collateral amount (WPLS)
     * @return debt Current debt (pSunDAI)
     * @return collateralUSD USD value of collateral based on oracle
     * @return ratio Collateralization ratio (x100 = %)
     * @return mintable Safe amount of pSunDAI mintable right now
     * @return oracleHealthy True if oracle updated recently
     * @return price Latest oracle price (1e18 precision)
     * @return systemRatio Global system collateralization ratio (x100 = %)
     */
    function vaultInfo(address user)
    external
    view
    returns (
        uint256 collateral,
        uint256 debt,
        uint256 collateralUSD,
        uint256 ratio,
        uint256 mintable,
        bool oracleHealthy,
        uint256 price,
        uint256 systemRatio
    )
{
    Vault storage v = vaults[user];
    collateral = v.collateral;
    debt = v.debt;

    (uint256 p, uint256 ts) = oracle.peekPriceView();
    // Oracle already returns 1e18-scaled USD/PLS, no normalization needed

    price = (block.timestamp - ts > 300 || p == 0) ? lastSafePrice : p;
    oracleHealthy = (block.timestamp - ts <= 600);

    collateralUSD = (collateral * price) / 1e18;
    ratio = debt == 0 ? type(uint256).max : (collateral * price * 100) / (debt * 1e18);

    uint256 safeDebtLimit = (collateralUSD * 100) / COLLATERAL_RATIO;
    mintable = safeDebtLimit > debt ? safeDebtLimit - debt : 0;

    systemRatio = systemHealth();
}

// Accept native PLS deposits safely
receive() external payable {}
fallback() external payable {}

}
