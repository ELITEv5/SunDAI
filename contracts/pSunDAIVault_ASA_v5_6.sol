// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║           pSunDAIVault ASA V5.6 — Production Final Edition       ║
 * ║                                                                  ║
 * ║   Final, immutable, self-healing, auto-reviving SunDAI vault     ║
 * ║   - Auto-poke, no stale pause, interest on every touch           ║
 * ║   - 10% volatility guard, uses peekPriceView() everywhere        ║
 * ║   - No keepers, no admin, forever immortal                       ║
 * ║                                                                  ║
 * ║   FIXES IN V5.6:                                                 ║
 * ║   ✓ Removed oracle.poke() calls (prevents revert issues)         ║
 * ║   ✓ Oracle price validation in constructor (no magic numbers)    ║
 * ║   ✓ All v5.5 fixes maintained (lastDebtAccrual, price init)      ║
 * ║                                                                  ║
 * ║   Dev: ELITE TEAM6                                               ║
 * ║   Website: https://www.sundaitoken.com                           ║
 * ╚══════════════════════════════════════════════════════════════════╝
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./SunDAI_ASA_Token.sol";
import "./pSunDAI_Oracle_Hybrid_5_1.sol";

interface IWPLS {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

contract pSunDAIVault_ASA_v5_6 is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IERC20 public immutable wpls;
    pSunDAI_ASA public immutable psundai;
    pSunDAIoraclePLSXHybrid_5_1 public immutable oracle;

    string public constant VERSION = "pSunDAIVault_ASA_v5.6_Final";

    uint256 public constant COLLATERAL_RATIO = 150;
    uint256 public constant LIQUIDATION_RATIO = 110;
    uint256 public constant MIN_ACTION_AMOUNT = 1e14;
    uint256 public constant WITHDRAW_COOLDOWN = 300;
    uint256 public constant MIN_LIQUIDATION_BPS = 2000;
    uint256 public constant MIN_BONUS_BPS = 200;
    uint256 public constant MAX_BONUS_BPS = 500;
    uint256 public constant AUCTION_TIME = 3 hours;
    uint256 public constant LIQUIDATION_COOLDOWN = 600;
    uint256 public constant MIN_SYSTEM_HEALTH = 130;
    uint256 public constant STABILITY_FEE_BPS = 50;
    uint256 public constant SECONDS_PER_YEAR = 31_536_000;
    uint256 public constant MAX_VOLATILITY_BPS = 1000; // 10%

    struct Vault {
        uint256 collateral;
        uint256 debt;
        uint256 lastDepositTime;
        uint256 lastWithdrawTime;
        uint256 lastLiquidationTime;
        uint256 lastDebtAccrual;
    }

    mapping(address => Vault) public vaults;
    uint256 public totalCollateral;
    uint256 public totalDebt;
    uint256 public lastOraclePrice;
    uint256 public lastOracleUpdateTime;

    event Deposit(address indexed user, uint256 amount, uint256 ratio);
    event Withdraw(address indexed user, uint256 amount, uint256 ratio);
    event Mint(address indexed user, uint256 amount, uint256 ratio);
    event Repay(address indexed user, uint256 amount, uint256 ratio);
    event Liquidation(address indexed user, uint256 repayAmount, address indexed liquidator, uint256 reward, uint256 ratio);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(address _wpls, address _psundai, address _oracle) {
        require(_wpls != address(0) && _psundai != address(0) && _oracle != address(0), "Zero address");
        wpls = IERC20(_wpls);
        psundai = pSunDAI_ASA(_psundai);
        oracle = pSunDAIoraclePLSXHybrid_5_1(_oracle);
        
        // V5.6 FIX: Require valid oracle price at deployment (no magic numbers)
        (uint256 initialPrice,) = pSunDAIoraclePLSXHybrid_5_1(_oracle).peekPriceView();
        require(initialPrice > 0, "Oracle not ready - initialize pairs first");
        lastOraclePrice = initialPrice;
        lastOracleUpdateTime = block.timestamp;
    }

    // ───────────────────────────── PRICE HELPERS ─────────────────────────────
    function _safePrice() internal returns (uint256 p) {
        uint256 ts;
        (p, ts) = oracle.peekPriceView();
        if (p == 0) p = lastOraclePrice > 0 ? lastOraclePrice : 1e18;

        if (lastOraclePrice > 0) {
            uint256 diff = p > lastOraclePrice ? p - lastOraclePrice : lastOraclePrice - p;
            uint256 volatilityBps = (diff * 10_000) / lastOraclePrice;

            if (volatilityBps > MAX_VOLATILITY_BPS) {
                // Asymmetric cooldown
                uint256 cooldown = p < lastOraclePrice ? 4 hours : 1 hours;

                // Early recovery: if price moves back into ±10% band, accept immediately
                uint256 lowerBound = (lastOraclePrice * 9000) / 10000;  // -10%
                uint256 upperBound = (lastOraclePrice * 11000) / 10000; // +10%

                if (p >= lowerBound && p <= upperBound) {
                    lastOraclePrice = p;
                    lastOracleUpdateTime = ts;
                }
                // Otherwise enforce cooldown
                else if (block.timestamp - lastOracleUpdateTime >= cooldown) {
                    lastOraclePrice = p;
                    lastOracleUpdateTime = ts;
                }
                else {
                    p = lastOraclePrice; // clamp
                }
            } else {
                // Normal case: within 10% → accept
                lastOraclePrice = p;
                lastOracleUpdateTime = ts;
            }
        } else {
            lastOraclePrice = p;
            lastOracleUpdateTime = ts;
        }
        return p;
    }

    // ───────────────────────────── INTEREST ACCRUAL ─────────────────────────────
    function _touch(address user) internal {
        Vault storage v = vaults[user];
        if (v.debt > 0) _accrueInterest(v);
    }

    function _accrueInterest(Vault storage v) internal {
        if (v.debt == 0) {
            v.lastDebtAccrual = block.timestamp;
            return;
        }
        uint256 elapsed = block.timestamp - v.lastDebtAccrual;
        if (elapsed == 0) return;

        uint256 fee = (v.debt * STABILITY_FEE_BPS * elapsed) / (SECONDS_PER_YEAR * 10_000);
        if (fee == 0 && elapsed > 0) fee = 1;

        v.debt += fee;
        totalDebt += fee;
        v.lastDebtAccrual = block.timestamp;

        if (v.debt <= 1e12) {
            totalDebt -= v.debt;
            v.debt = 0;
        }
    }

    // ───────────────────────────── USER ACTIONS ─────────────────────────────
    function depositPLS() external payable nonReentrant {
        require(msg.value >= MIN_ACTION_AMOUNT, "Too small");
        _touch(msg.sender);
        IWPLS(address(wpls)).deposit{value: msg.value}();
        _addCollateral(msg.sender, msg.value);
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount >= MIN_ACTION_AMOUNT, "Too small");
        _touch(msg.sender);
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
        require(msg.value >= MIN_ACTION_AMOUNT, "Too small");
        // V5.6 FIX: Removed oracle.poke() call (prevents revert due to rate limiting)
        _touch(msg.sender);

        IWPLS(address(wpls)).deposit{value: msg.value}();
        _addCollateral(msg.sender, msg.value);

        uint256 price = _safePrice();
        uint256 valueUSD = (msg.value * price) / 1e18;
        uint256 mintAmount = (valueUSD * 100) / 155;  // Intentional 155% buffer — prevents rounding reverts & adds safety margin

        if (mintAmount > 0) {
            Vault storage v = vaults[msg.sender];
            
            // V5.5 FIX: Initialize lastDebtAccrual if this is first debt
            bool isFirstDebt = (v.debt == 0);
            
            v.debt += mintAmount;
            totalDebt += mintAmount;
            
            if (isFirstDebt) {
                v.lastDebtAccrual = block.timestamp;
            }
            
            psundai.mint(msg.sender, mintAmount);
            emit Mint(msg.sender, mintAmount, _collateralRatio(msg.sender));
        }
    }

    function mint(uint256 amount) external nonReentrant {
        // V5.6 FIX: Removed oracle.poke() call (prevents revert due to rate limiting)
        _touch(msg.sender);

        Vault storage v = vaults[msg.sender];
        require(amount > 0, "Zero mint");
        require(systemHealth() >= MIN_SYSTEM_HEALTH, "System undercollateralized");

        uint256 price = _safePrice();
        require(_isSafePrice(v.collateral, v.debt + amount, price), "Not enough collateral");

        // V5.5 FIX: Initialize lastDebtAccrual if this is first debt
        bool isFirstDebt = (v.debt == 0);

        v.debt += amount;
        totalDebt += amount;
        
        if (isFirstDebt) {
            v.lastDebtAccrual = block.timestamp;
        }

        psundai.mint(msg.sender, amount);
        emit Mint(msg.sender, amount, _collateralRatio(msg.sender));
    }

    function repay(uint256 amount) external nonReentrant {
        Vault storage v = vaults[msg.sender];
        require(amount > 0 && v.debt >= amount, "Invalid repay");
        _touch(msg.sender);

        psundai.burn(msg.sender, amount);
        v.debt -= amount;
        totalDebt -= amount;
        emit Repay(msg.sender, amount, _collateralRatio(msg.sender));
    }

    function withdrawPLS(uint256 amount) external nonReentrant {
        Vault storage v = vaults[msg.sender];
        require(amount > 0 && v.collateral >= amount, "Invalid withdraw");
        require(block.timestamp > v.lastDepositTime + WITHDRAW_COOLDOWN, "Cooldown");
        _touch(msg.sender);

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
        _touch(msg.sender);

        v.collateral -= amount;
        totalCollateral -= amount;
        require(_isSafe(v.collateral, v.debt), "Unsafe");
        v.lastWithdrawTime = block.timestamp;

        wpls.safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount, _collateralRatio(msg.sender));
    }

    function repayAndAutoWithdraw(uint256 repayAmount) external nonReentrant {
        Vault storage v = vaults[msg.sender];
        _touch(msg.sender);
        require(repayAmount > 0 && v.debt >= repayAmount, "Invalid repay");

        psundai.burn(msg.sender, repayAmount);
        v.debt -= repayAmount;
        totalDebt -= repayAmount;

        if (v.debt <= 1e12) {
            totalDebt -= v.debt;
            v.debt = 0;
        }

        uint256 price = _safePrice();

        if (v.debt == 0) {
            uint256 amt = v.collateral;
            totalCollateral -= amt;
            delete vaults[msg.sender];
            IWPLS(address(wpls)).withdraw(amt);
            payable(msg.sender).transfer(amt);
            emit EmergencyWithdraw(msg.sender, amt);
            return;
        }

        uint256 required = (v.debt * COLLATERAL_RATIO * 1e18) / (price * 100);
        if (v.collateral > required) {
            uint256 withdrawable = v.collateral - required;
            v.collateral = required;
            totalCollateral -= withdrawable;
            IWPLS(address(wpls)).withdraw(withdrawable);
            payable(msg.sender).transfer(withdrawable);
            emit Withdraw(msg.sender, withdrawable, _collateralRatio(msg.sender));
        }

        emit Repay(msg.sender, repayAmount, _collateralRatio(msg.sender));
    }

    function emergencyUnlock() external nonReentrant {
        Vault storage v = vaults[msg.sender];
        require(v.debt == 0, "Repay first");
        require(v.collateral > 0, "No collateral");
        require(block.timestamp > v.lastDepositTime + 30 days, "Active");

        uint256 amt = v.collateral;
        v.collateral = 0;
        totalCollateral -= amt;
        IWPLS(address(wpls)).withdraw(amt);
        payable(msg.sender).transfer(amt);
        emit EmergencyWithdraw(msg.sender, amt);
    }

    function liquidate(address user, uint256 repayAmount) external nonReentrant {
        Vault storage v = vaults[user];
        _touch(user);

        require(!_isSafe(v.collateral, v.debt), "Safe");
        require(v.debt > 0, "No debt");
        require(repayAmount > 0 && repayAmount <= v.debt, "Invalid");
        require(repayAmount * 10000 >= v.debt * MIN_LIQUIDATION_BPS, "Too small");
        require(block.timestamp > v.lastLiquidationTime + LIQUIDATION_COOLDOWN, "Cooldown");

        uint256 price = _safePrice();
        uint256 base = Math.mulDiv(repayAmount, 1e18, price);

        uint256 elapsed = block.timestamp - v.lastWithdrawTime;
        if (elapsed > AUCTION_TIME) elapsed = AUCTION_TIME;
        uint256 bonusBps = MIN_BONUS_BPS + ((MAX_BONUS_BPS - MIN_BONUS_BPS) * elapsed / AUCTION_TIME);
        uint256 bonus = (base * bonusBps) / 10000;
        uint256 reward = base + bonus;
        if (reward > v.collateral) reward = v.collateral;

        psundai.burn(msg.sender, repayAmount);
        v.debt -= repayAmount;
        totalDebt -= repayAmount;
        v.collateral -= reward;
        totalCollateral -= reward;
        v.lastLiquidationTime = block.timestamp;

        IWPLS(address(wpls)).withdraw(reward);
        payable(msg.sender).transfer(reward);

        emit Liquidation(user, repayAmount, msg.sender, reward, _collateralRatio(user));
    }

    // ───────────────────────────── VIEW FUNCTIONS ─────────────────────────────
    function systemHealth() public view returns (uint256) {
        if (totalDebt == 0) return type(uint256).max;
        (uint256 p,) = oracle.peekPriceView();
        uint256 price = p > 0 ? p : lastOraclePrice;
        return (totalCollateral * price * 100) / (totalDebt * 1e18);
    }

    function _collateralRatio(address user) internal view returns (uint256) {
        Vault storage v = vaults[user];
        if (v.debt == 0) return type(uint256).max;
        (uint256 p,) = oracle.peekPriceView();
        uint256 price = p > 0 ? p : lastOraclePrice;
        return (v.collateral * price * 100) / (v.debt * 1e18);
    }

    function _isSafe(uint256 col, uint256 debt) internal view returns (bool) {
        if (debt == 0) return true;
        (uint256 p,) = oracle.peekPriceView();
        uint256 price = p > 0 ? p : lastOraclePrice;
        return col * price * 100 >= debt * COLLATERAL_RATIO * 1e18;
    }

    function _isSafePrice(uint256 col, uint256 debt, uint256 price) internal pure returns (bool) {
        if (debt == 0) return true;
        return col * price * 100 >= debt * COLLATERAL_RATIO * 1e18;
    }

    function canLiquidate(address user) public view returns (bool) {
        Vault storage v = vaults[user];
        if (v.debt == 0) return false;
        (uint256 p,) = oracle.peekPriceView();
        uint256 price = p > 0 ? p : lastOraclePrice;
        uint256 ratio = (v.collateral * price * 100) / (v.debt * 1e18);
        return ratio < LIQUIDATION_RATIO;
    }

    function liquidationInfo(address user) external view returns (uint256 debt, uint256 minRepay, uint256 reward, uint256 bonusBps) {
        Vault storage v = vaults[user];
        if (v.debt == 0) return (0, 0, 0, 0);
        (uint256 p, uint256 ts) = oracle.peekPriceView();
        uint256 price = (block.timestamp - ts > 300 || p == 0) ? lastOraclePrice : p;
        uint256 minRepayAmt = (v.debt * MIN_LIQUIDATION_BPS) / 10000;
        uint256 base = Math.mulDiv(minRepayAmt, 1e18, price);
        uint256 elapsed = block.timestamp - v.lastWithdrawTime;
        if (elapsed > AUCTION_TIME) elapsed = AUCTION_TIME;
        bonusBps = MIN_BONUS_BPS + ((MAX_BONUS_BPS - MIN_BONUS_BPS) * elapsed / AUCTION_TIME);
        uint256 bonus = (base * bonusBps) / 10000;
        reward = base + bonus;
        return (v.debt, minRepayAmt, reward, bonusBps);
    }

    function maxMint(address user) external view returns (uint256) {
        Vault storage v = vaults[user];
        if (v.collateral == 0) return 0;
        (uint256 p, uint256 ts) = oracle.peekPriceView();
        uint256 price = (block.timestamp - ts > 300 || p == 0) ? lastOraclePrice : p;
        uint256 valueUSD = (v.collateral * price) / 1e18;
        uint256 limit = (valueUSD * 100) / COLLATERAL_RATIO;
        return limit > v.debt ? limit - v.debt : 0;
    }

    function repayToHealth(address user) external view returns (uint256 repayNeeded) {
        Vault storage v = vaults[user];
        if (v.debt == 0) return 0;
        (uint256 p, uint256 ts) = oracle.peekPriceView();
        uint256 price = (block.timestamp - ts > 300 || p == 0) ? lastOraclePrice : p;
        uint256 requiredDebt = (v.collateral * price * 100) / (COLLATERAL_RATIO * 1e18);
        return v.debt > requiredDebt ? v.debt - requiredDebt : 0;
    }

    function autoRepayToHealth() external nonReentrant {
        Vault storage v = vaults[msg.sender];
        _touch(msg.sender);
        if (v.debt == 0) return;
        uint256 price = _safePrice();
        uint256 requiredDebt = (v.collateral * price * 100) / (COLLATERAL_RATIO * 1e18);
        if (v.debt > requiredDebt) {
            uint256 repayAmt = v.debt - requiredDebt;
            psundai.burn(msg.sender, repayAmt);
            v.debt -= repayAmt;
            totalDebt -= repayAmt;
            emit Repay(msg.sender, repayAmt, _collateralRatio(msg.sender));
        }
    }

    function vaultInfo(address user) external view returns (
        uint256 collateral, uint256 debt, uint256 collateralUSD, uint256 ratio,
        uint256 mintable, bool oracleHealthy, uint256 price, uint256 systemRatio
    ) {
        Vault storage v = vaults[user];
        collateral = v.collateral;
        debt = v.debt;
        (uint256 p, uint256 ts) = oracle.peekPriceView();
        price = (block.timestamp - ts > 300 || p == 0) ? lastOraclePrice : p;
        oracleHealthy = (block.timestamp - ts <= 600);
        collateralUSD = (collateral * price) / 1e18;
        ratio = debt == 0 ? type(uint256).max : (collateral * price * 100) / (debt * 1e18);
        uint256 safeDebtLimit = (collateralUSD * 100) / COLLATERAL_RATIO;
        mintable = safeDebtLimit > debt ? safeDebtLimit - debt : 0;
        systemRatio = systemHealth();
    }

    receive() external payable {}
    fallback() external payable {}
}
