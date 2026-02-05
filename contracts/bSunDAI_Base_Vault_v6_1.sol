// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./bSunDAI_ASA_Token_2.sol";
import "./bSunDAIoracleBASE_v6_02_FINAL.sol";

/**
 * ╔════════════════════════════════════════════════════════════╗
 * ║            bSunDAI Vault v6.1 (Base Mainnet)               ║
 * ║          Vault Enumeration + All v6.0.2 Features           ║
 * ║                                                            ║
 * ║   License:  MIT | One-Time Setup | Then Immutable Forever  ║
 * ║                                                            ║
 * ║   v6.1.0 ENHANCEMENTS (LIQUIDATION DASHBOARD FIX):         ║
 * ║   ✓ On-chain vault enumeration (scales forever)            ║
 * ║   ✓ No RPC log query limits                                ║
 * ║   ✓ Trustless vault discovery for liquidators              ║
 * ║   ✓ ~20k gas one-time per user registration                ║
 * ║   ✓ All v6.0.2 security features preserved                 ║
 * ║                                                            ║
 * ║   v6.0.2 FEATURES (CATASTROPHIC ORACLE FAILURE FIX):       ║
 * ║   ✓ 7-day oracle failure override for emergency exits      ║
 * ║   ✓ Users can repay debt if oracle dead 7+ days            ║
 * ║   ✓ Users can withdraw if oracle dead 7+ days              ║
 * ║   ✓ Guarantees full fund recovery in worst-case scenario   ║
 * ║                                                            ║
 * ║   v6.0.1 PATCHES (IMMUTABLE-SAFE HARDENING):               ║
 * ║   ✓ Vault now ADVANCES oracle state via getPriceWithTimestamp║
 * ║   ✓ Dutch auction timing fixed (tracks undercollateralizedSince)║
 * ║   ✓ ETH payouts use .call instead of .transfer (keeper-safe)║
 * ║   ✓ Two-step burn pattern (institutional regulatory clarity)║
 * ║   ✓ Vault collects tokens then burns own balance (trust-minimized)║
 * ╚════════════════════════════════════════════════════════════╝
 */

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

contract bSunDAIVault_ASA_v6_1 is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                              IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    IERC20 public immutable weth;
    bSunDAI public immutable bsundai;
    bSunDAIoracleBASE_v6_0_2_FINAL public immutable oracle;

    string public constant VERSION = "bSunDAIVault_ASA_v6.1.0";

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Collateral ratio required for minting (150%)
    uint256 public constant COLLATERAL_RATIO = 150;

    /// @notice Auto-mint ratio with safety buffer (155%)
    uint256 public constant AUTO_MINT_RATIO = 155;

    /// @notice Liquidation threshold (110%)
    uint256 public constant LIQUIDATION_RATIO = 110;

    /// @notice Minimum action amount to prevent dust
    uint256 public constant MIN_ACTION_AMOUNT = 1e14;

    /// @notice Cooldown after deposit before withdrawal (5 minutes)
    uint256 public constant WITHDRAW_COOLDOWN = 300;

    /// @notice Stability fee in basis points (0.5% APY)
    uint256 public constant STABILITY_FEE_BPS = 50;

    /// @notice Seconds in a year for interest calculations
    uint256 public constant SECONDS_PER_YEAR = 31_536_000;

    /// @notice Minimum liquidation penalty (20%) (kept for docs/compat)
    uint256 public constant MIN_LIQUIDATION_BPS = 2000;

    /// @notice Minimum liquidation bonus for liquidators (2%)
    uint256 public constant MIN_BONUS_BPS = 200;

    /// @notice Maximum liquidation bonus (5%)
    uint256 public constant MAX_BONUS_BPS = 500;

    /// @notice Dutch auction duration (3 hours)
    uint256 public constant AUCTION_TIME = 3 hours;

    /// @notice Cooldown between liquidations of same vault (10 minutes)
    uint256 public constant LIQUIDATION_COOLDOWN = 600;

    /// @notice Minimum system health ratio for new minting (130%)
    uint256 public constant MIN_SYSTEM_HEALTH = 130;

    /// @notice Maximum oracle price volatility before fallback (10%)
    uint256 public constant MAX_VOLATILITY_BPS = 1000;

    /// @notice Maximum oracle price staleness (5 minutes)
    uint256 public constant MAX_ORACLE_STALENESS = 300;

    /// @notice Oracle failure override threshold (7 days)
    /// @dev After oracle is dead for 7+ days, emergency functions unlock
    uint256 public constant ORACLE_FAILURE_OVERRIDE = 7 days;

    /*//////////////////////////////////////////////////////////////
                              VAULT STRUCT
    //////////////////////////////////////////////////////////////*/

    struct Vault {
        uint256 collateral;               // WETH collateral amount
        uint256 debt;                     // bSunDAI debt amount
        uint256 lastDepositTime;          // Timestamp of last deposit
        uint256 lastWithdrawTime;         // Timestamp of last withdrawal
        uint256 lastLiquidationTime;      // Timestamp of last liquidation
        uint256 lastDebtAccrual;          // Timestamp of last interest accrual
        uint256 undercollateralizedSince; // Timestamp when first became liquidatable
    }

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    mapping(address => Vault) public vaults;

    /// @notice Total WETH collateral in system
    uint256 public totalCollateral;

    /// @notice Total bSunDAI debt in system
    uint256 public totalDebt;

    /// @notice Last validated oracle price
    uint256 public lastOraclePrice;

    /// @notice Timestamp of last oracle update (oracle committed time)
    uint256 public lastOracleUpdateTime;

    /*//////////////////////////////////////////////////////////////
                        VAULT ENUMERATION (v6.1.0)
    //////////////////////////////////////////////////////////////*/

    /// @notice Array of all vault owners (registered on first interaction)
    address[] public vaultOwners;

    /// @notice Tracks whether address has been registered
    mapping(address => bool) public hasVault;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed user, uint256 amount, uint256 ratio);
    event Withdraw(address indexed user, uint256 amount, uint256 ratio);
    event Mint(address indexed user, uint256 amount, uint256 ratio);
    event Repay(address indexed user, uint256 amount, uint256 ratio);
    event Liquidation(
        address indexed user,
        uint256 repayAmount,
        address indexed liquidator,
        uint256 reward,
        uint256 ratio
    );
    event PartialLiquidation(
        address indexed user,
        uint256 repayAmount,
        uint256 debtRemaining,
        address indexed liquidator
    );
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event OracleFallbackUsed(uint256 price, uint256 timestamp);
    event EmergencyRepay(address indexed user, uint256 amount, string reason);
    event EmergencyWithdrawETH(address indexed user, uint256 amount, string reason);
    event VaultRegistered(address indexed user);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _weth, address _bsundai, address _oracle) {
        require(
            _weth != address(0) && _bsundai != address(0) && _oracle != address(0),
            "Zero address"
        );

        weth = IERC20(_weth);
        bsundai = bSunDAI(_bsundai);
        oracle = bSunDAIoracleBASE_v6_0_2_FINAL(_oracle);

        // Initialize with current oracle price (view)
        (lastOraclePrice,) = oracle.peekPrice();
        if (lastOraclePrice == 0) lastOraclePrice = 3000 * 1e18;
        lastOracleUpdateTime = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL ETH SENDER
    //////////////////////////////////////////////////////////////*/

    function _sendETH(address to, uint256 amount) internal {
        (bool ok,) = payable(to).call{value: amount}("");
        require(ok, "ETH transfer failed");
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL BURN HELPER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Two-step burn for regulatory clarity
     * @dev Vault collects tokens, then burns from its own balance
     * @param from Address to collect tokens from
     * @param amount Amount to burn
     */
    function _collectAndBurn(address from, uint256 amount) internal {
        // STEP 1: Transfer tokens from user/liquidator to vault
        IERC20(address(bsundai)).safeTransferFrom(from, address(this), amount);
        
        // STEP 2: Vault burns its own balance (regulatory clarity)
        bsundai.burn(amount);
    }

    /*//////////////////////////////////////////////////////////////
                        VAULT REGISTRATION (v6.1.0)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register vault owner for enumeration (called automatically)
     * @dev One-time ~20k gas cost per user
     * @param user Address to register
     */
    function _registerVault(address user) internal {
        if (!hasVault[user]) {
            hasVault[user] = true;
            vaultOwners.push(user);
            emit VaultRegistered(user);
        }
    }

    /**
     * @notice Get total number of vault owners
     * @return count Number of registered vault owners
     */
    function getVaultOwnersCount() external view returns (uint256) {
        return vaultOwners.length;
    }

    /**
     * @notice Get paginated list of vault owners
     * @param start Starting index
     * @param count Number of addresses to return
     * @return Batch of vault owner addresses
     */
    function getVaultOwnersPaginated(uint256 start, uint256 count) 
        external 
        view 
        returns (address[] memory) 
    {
        require(start < vaultOwners.length, "Start out of bounds");
        
        uint256 end = start + count;
        if (end > vaultOwners.length) {
            end = vaultOwners.length;
        }
        
        uint256 resultCount = end - start;
        address[] memory result = new address[](resultCount);
        
        for (uint256 i = 0; i < resultCount; i++) {
            result[i] = vaultOwners[start + i];
        }
        
        return result;
    }

    /*//////////////////////////////////////////////////////////////
                           SAFETY CHECKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if system is safe for user operations
     * @dev Uses peekPrice for view-safety; state-changing ops use _safePrice()
     */
    function isUXSafe() public view returns (bool) {
        (uint256 p, uint256 ts) = oracle.peekPrice();

        // Oracle must return valid price and be recently committed by vault
        bool oracleHealthy = (p > 0 && block.timestamp - ts <= MAX_ORACLE_STALENESS);

        // System must maintain minimum health ratio
        return oracleHealthy && systemHealth() >= MIN_SYSTEM_HEALTH;
    }

    /**
     * @notice Check if oracle has been dead for catastrophic failure threshold
     * @dev Used by emergency functions to allow exits when oracle permanently fails
     * @return True if oracle has been stale for 7+ days
     */
    function isOracleCatastrophicallyFailed() public view returns (bool) {
        (, uint256 ts) = oracle.peekPrice();
        return block.timestamp - ts > ORACLE_FAILURE_OVERRIDE;
    }

    /**
     * @notice Get current ETH/USD price with dual-layer validation
     * @dev IMPORTANT: this function advances oracle state (confirmation/stepping/TWAP)
     */
    function _safePrice() internal returns (uint256 p) {
        uint256 ts;
        (p, ts) = oracle.getPriceWithTimestamp(); // <-- PATCH: advance oracle state

        // LAYER 1: Validate oracle freshness (ts is oracle-committed time)
        if (p == 0 || block.timestamp - ts > MAX_ORACLE_STALENESS) {
            emit OracleFallbackUsed(lastOraclePrice, block.timestamp);
            return lastOraclePrice > 0 ? lastOraclePrice : 3000 * 1e18;
        }

        // LAYER 2: Vault-side volatility check (defense in depth)
        if (lastOraclePrice > 0) {
            uint256 diff = p > lastOraclePrice ? p - lastOraclePrice : lastOraclePrice - p;
            uint256 volatilityBps = (diff * 10000) / lastOraclePrice;

            if (volatilityBps > MAX_VOLATILITY_BPS) {
                // Price moved >10% - check oracle confirmation state
                (
                    ,
                    ,
                    ,
                    bool inConfirmation,
                    ,
                    /*targetPrice*/
                ) = oracle.getPriceStatus();

                if (inConfirmation) {
                    // Oracle is handling large move with confirmation - accept
                    lastOraclePrice = p;
                    lastOracleUpdateTime = ts;
                } else {
                    // Unexpected move without confirmation - fallback
                    p = lastOraclePrice;
                    emit OracleFallbackUsed(p, block.timestamp);
                }
            } else {
                lastOraclePrice = p;
                lastOracleUpdateTime = ts;
            }
        } else {
            lastOraclePrice = p;
            lastOracleUpdateTime = ts;
        }

        return p;
    }

    /*//////////////////////////////////////////////////////////////
                           VAULT MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function _touch(address user) internal {
        Vault storage v = vaults[user];
        if (v.debt > 0) _accrueInterest(v);
    }

    function _accrueInterest(Vault storage v) internal {
        if (v.debt == 0) {
            // DO NOT update lastDebtAccrual when debt is 0
            // It gets set correctly in mint() when debt is first created
            return;
        }

        uint256 elapsed = block.timestamp - v.lastDebtAccrual;
        if (elapsed == 0) return;

        uint256 fee = (v.debt * STABILITY_FEE_BPS * elapsed) / (SECONDS_PER_YEAR * 10000);
        if (fee == 0 && elapsed > 0) fee = 1;

        v.debt += fee;
        totalDebt += fee;
        v.lastDebtAccrual = block.timestamp;

        if (v.debt <= 1e12) {
            totalDebt -= v.debt;
            v.debt = 0;
        }
    }

    function _addCollateral(address user, uint256 amount) internal {
        Vault storage v = vaults[user];
        
        // Register vault owner on first interaction (v6.1.0)
        _registerVault(user);
        
        v.collateral += amount;
        v.lastDepositTime = block.timestamp;
        totalCollateral += amount;
        emit Deposit(user, amount, _collateralRatio(user));
    }

    function _collateralRatio(address user) internal view returns (uint256) {
        Vault storage v = vaults[user];
        if (v.debt == 0) return type(uint256).max;

        (uint256 p,) = oracle.peekPrice();
        uint256 price = p > 0 ? p : lastOraclePrice;

        return (v.collateral * price * 100) / (v.debt * 1e18);
    }

    function _isSafe(uint256 col, uint256 debt) internal view returns (bool) {
        if (debt == 0) return true;

        (uint256 p,) = oracle.peekPrice();
        uint256 price = p > 0 ? p : lastOraclePrice;

        return col * price * 100 >= debt * COLLATERAL_RATIO * 1e18;
    }

    function systemHealth() public view returns (uint256) {
        if (totalDebt == 0) return type(uint256).max;

        (uint256 p,) = oracle.peekPrice();
        uint256 price = p > 0 ? p : lastOraclePrice;

        return (totalCollateral * price * 100) / (totalDebt * 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                           DEPOSIT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function depositETH() external payable nonReentrant {
        require(msg.value >= MIN_ACTION_AMOUNT, "Invalid amount");

        IWETH(address(weth)).deposit{value: msg.value}();
        _addCollateral(msg.sender, msg.value);
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount >= MIN_ACTION_AMOUNT, "Invalid amount");

        weth.safeTransferFrom(msg.sender, address(this), amount);
        _addCollateral(msg.sender, amount);
    }

    function depositAndAutoMintETH() external payable nonReentrant {
        require(msg.value >= MIN_ACTION_AMOUNT, "Invalid amount");
        require(isUXSafe(), "System not safe");

        IWETH(address(weth)).deposit{value: msg.value}();
        _addCollateral(msg.sender, msg.value);

        uint256 price = _safePrice(); // advances oracle state
        uint256 collateralValueUSD = (msg.value * price) / 1e18;
        uint256 mintAmount = (collateralValueUSD * 100) / AUTO_MINT_RATIO;

        if (mintAmount == 0) return;

        Vault storage v = vaults[msg.sender];

        if (v.debt == 0) {
            v.lastDebtAccrual = block.timestamp;
        }

        v.debt += mintAmount;
        totalDebt += mintAmount;

        bsundai.mint(msg.sender, mintAmount);
        emit Mint(msg.sender, mintAmount, _collateralRatio(msg.sender));
    }

    /*//////////////////////////////////////////////////////////////
                           MINTING & REPAYMENT
    //////////////////////////////////////////////////////////////*/

    function mint(uint256 amount) external nonReentrant {
        Vault storage v = vaults[msg.sender];
        require(amount > 0, "Invalid mint");
        require(isUXSafe(), "System not safe");

        // Register vault owner on first mint (v6.1.0)
        _registerVault(msg.sender);

        _accrueInterest(v);

        if (v.debt == 0) v.lastDebtAccrual = block.timestamp;

        require(systemHealth() >= MIN_SYSTEM_HEALTH, "Mint paused: system undercollateralized");

        // Advance oracle state before safety check
        uint256 price = _safePrice();

        // Must remain safe
        require(v.collateral * price * 100 >= (v.debt + amount) * COLLATERAL_RATIO * 1e18, "Not enough collateral");

        v.debt += amount;
        totalDebt += amount;

        bsundai.mint(msg.sender, amount);
        emit Mint(msg.sender, amount, _collateralRatio(msg.sender));
    }

    function repay(uint256 amount) external nonReentrant {
        Vault storage v = vaults[msg.sender];
        require(amount > 0 && v.debt >= amount, "Invalid repay");

        _accrueInterest(v);

        // Two-step burn: collect tokens, then burn vault's balance
        _collectAndBurn(msg.sender, amount);

        v.debt -= amount;
        totalDebt -= amount;

        emit Repay(msg.sender, amount, _collateralRatio(msg.sender));
    }

    /**
     * @notice Emergency repay when oracle is catastrophically failed (7+ days)
     * @dev Allows users to repay debt and recover funds if oracle permanently fails
     * @param amount Amount of bSunDAI to repay
     */
    function emergencyRepay(uint256 amount) external nonReentrant {
        Vault storage v = vaults[msg.sender];
        require(amount > 0 && v.debt >= amount, "Invalid repay");
        
        // Only allow if oracle has been dead for 7+ days
        require(isOracleCatastrophicallyFailed(), "Oracle not failed (use normal repay)");
        
        _accrueInterest(v);
        
        // Two-step burn: collect tokens, then burn vault's balance
        _collectAndBurn(msg.sender, amount);
        
        v.debt -= amount;
        totalDebt -= amount;
        
        emit EmergencyRepay(msg.sender, amount, "Oracle catastrophically failed");
        emit Repay(msg.sender, amount, _collateralRatio(msg.sender));
    }

    /*//////////////////////////////////////////////////////////////
                           WITHDRAWAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function withdrawETH(uint256 amount) external nonReentrant {
        Vault storage v = vaults[msg.sender];
        require(amount > 0 && v.collateral >= amount, "Invalid withdraw");
        require(block.timestamp > v.lastDepositTime + WITHDRAW_COOLDOWN, "Cooldown");
        require(isUXSafe() || v.debt == 0, "Withdraw paused");

        // If there's debt, advance oracle state before safety check (important)
        uint256 price = v.debt > 0 ? _safePrice() : 0;

        v.collateral -= amount;
        totalCollateral -= amount;

        if (v.debt > 0) {
            require(v.collateral * price * 100 >= v.debt * COLLATERAL_RATIO * 1e18, "Unsafe");
        }

        v.lastWithdrawTime = block.timestamp;

        IWETH(address(weth)).withdraw(amount);
        _sendETH(msg.sender, amount);

        emit Withdraw(msg.sender, amount, _collateralRatio(msg.sender));
    }

    /**
     * @notice Emergency withdraw when oracle is catastrophically failed (7+ days)
     * @dev Allows users to withdraw collateral without safety checks if oracle permanently fails
     * @dev Still requires 5-minute cooldown to prevent flash loan attacks
     * @param amount Amount of ETH to withdraw (in wei)
     */
    function emergencyWithdrawETH(uint256 amount) external nonReentrant {
        Vault storage v = vaults[msg.sender];
        require(amount > 0 && v.collateral >= amount, "Invalid withdraw");
        
        // Only allow if oracle has been dead for 7+ days
        require(isOracleCatastrophicallyFailed(), "Oracle not failed (use normal withdraw)");
        
        // Still enforce cooldown to prevent flash loan exploits
        require(block.timestamp > v.lastDepositTime + WITHDRAW_COOLDOWN, "Cooldown");
        
        v.collateral -= amount;
        totalCollateral -= amount;
        v.lastWithdrawTime = block.timestamp;
        
        IWETH(address(weth)).withdraw(amount);
        _sendETH(msg.sender, amount);
        
        emit EmergencyWithdrawETH(msg.sender, amount, "Oracle catastrophically failed");
        emit Withdraw(msg.sender, amount, _collateralRatio(msg.sender));
    }

    function repayAndAutoWithdraw(uint256 repayAmount) external nonReentrant {
        Vault storage v = vaults[msg.sender];

        _accrueInterest(v);
        require(repayAmount > 0 && v.debt >= repayAmount, "Invalid repay");

        // Two-step burn: collect tokens, then burn vault's balance
        _collectAndBurn(msg.sender, repayAmount);

        v.debt -= repayAmount;
        totalDebt -= repayAmount;

        if (v.debt <= 1e12) {
            totalDebt -= v.debt;
            v.debt = 0;
        }

        uint256 price = _safePrice(); // advances oracle state

        if (v.debt == 0) {
            uint256 amt = v.collateral;
            totalCollateral -= amt;
            delete vaults[msg.sender];

            IWETH(address(weth)).withdraw(amt);
            _sendETH(msg.sender, amt);

            emit EmergencyWithdraw(msg.sender, amt);
            return;
        }

        uint256 requiredCollateral = (v.debt * COLLATERAL_RATIO * 1e18) / (price * 100);

        if (v.collateral > requiredCollateral) {
            uint256 withdrawable = v.collateral - requiredCollateral;
            v.collateral = requiredCollateral;
            totalCollateral -= withdrawable;

            IWETH(address(weth)).withdraw(withdrawable);
            _sendETH(msg.sender, withdrawable);

            emit Withdraw(msg.sender, withdrawable, _collateralRatio(msg.sender));
        }

        emit Repay(msg.sender, repayAmount, _collateralRatio(msg.sender));
    }

    /*//////////////////////////////////////////////////////////////
                           LIQUIDATION SYSTEM
    //////////////////////////////////////////////////////////////*/

    function liquidate(address user, uint256 repayAmount) external nonReentrant {
        require(user != msg.sender, "Cannot self-liquidate");
        require(repayAmount > 0, "Invalid amount");

        Vault storage v = vaults[user];
        _accrueInterest(v);

        require(v.debt > 0, "No debt");
        require(repayAmount <= v.debt, "Exceeds debt");

        require(
            block.timestamp > v.lastLiquidationTime + LIQUIDATION_COOLDOWN,
            "Liquidation cooldown"
        );

        // Advance oracle state for liquidation-critical math
        uint256 price = _safePrice();

        // Compute current ratio using the price we are liquidating with
        uint256 currentRatio = (v.collateral * price * 100) / (v.debt * 1e18);
        require(currentRatio < LIQUIDATION_RATIO, "Vault is safe");

        // Track when vault first became liquidatable (Dutch auction start)
        if (v.undercollateralizedSince == 0) {
            v.undercollateralizedSince = block.timestamp;
        }

        uint256 baseCollateral = (repayAmount * 1e18) / price;

        // Dutch auction time since undercollateralized (fixed)
        uint256 t = block.timestamp - v.undercollateralizedSince;
        if (t > AUCTION_TIME) t = AUCTION_TIME;

        // Bonus decreases from MAX_BONUS_BPS to MIN_BONUS_BPS over AUCTION_TIME
        uint256 bonusBps = MAX_BONUS_BPS -
            ((MAX_BONUS_BPS - MIN_BONUS_BPS) * t) / AUCTION_TIME;

        uint256 bonusCollateral = (baseCollateral * bonusBps) / 10000;
        uint256 totalReward = baseCollateral + bonusCollateral;

        // Cap reward at available collateral
        if (totalReward > v.collateral) {
            totalReward = v.collateral;

            // Adjust repayAmount down to match what we can actually pay out
            // repayAmount' = totalReward * price / 1e18  (capped to remaining debt)
            uint256 impliedRepay = (totalReward * price) / 1e18;
            if (impliedRepay > v.debt) impliedRepay = v.debt;
            repayAmount = impliedRepay;

            // Recompute baseCollateral with adjusted repayAmount (keeps math coherent)
            baseCollateral = (repayAmount * 1e18) / price;
            bonusCollateral = (baseCollateral * bonusBps) / 10000;
            totalReward = baseCollateral + bonusCollateral;
            if (totalReward > v.collateral) totalReward = v.collateral;
        }

        v.debt -= repayAmount;
        v.collateral -= totalReward;
        v.lastLiquidationTime = block.timestamp;

        totalDebt -= repayAmount;
        totalCollateral -= totalReward;

        // Two-step burn: collect from liquidator, then burn vault's balance
        _collectAndBurn(msg.sender, repayAmount);

        // Send collateral reward
        IWETH(address(weth)).withdraw(totalReward);
        _sendETH(msg.sender, totalReward);

        // Reset undercollateralizedSince if vault is now safe (or fully repaid)
        if (v.debt == 0) {
            v.undercollateralizedSince = 0;
        } else {
            uint256 newRatio = (v.collateral * price * 100) / (v.debt * 1e18);
            if (newRatio >= LIQUIDATION_RATIO) {
                v.undercollateralizedSince = 0;
            }
        }

        if (v.debt > 0) {
            emit PartialLiquidation(user, repayAmount, v.debt, msg.sender);
        }

        emit Liquidation(
            user,
            repayAmount,
            msg.sender,
            totalReward,
            _collateralRatio(user)
        );
    }

    /*//////////////////////////////////////////////////////////////
                           EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function emergencyUnlock() external nonReentrant {
        Vault storage v = vaults[msg.sender];
        require(v.debt == 0, "Repay debt first");
        require(v.collateral > 0, "No collateral");
        require(block.timestamp > v.lastDepositTime + 30 days, "Vault recently active");

        uint256 amt = v.collateral;
        v.collateral = 0;
        totalCollateral -= amt;

        IWETH(address(weth)).withdraw(amt);
        _sendETH(msg.sender, amt);

        emit EmergencyWithdraw(msg.sender, amt);
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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

        (uint256 p, uint256 ts) = oracle.peekPrice();

        price = (block.timestamp - ts > MAX_ORACLE_STALENESS || p == 0)
            ? lastOraclePrice
            : p;

        oracleHealthy = (block.timestamp - ts <= MAX_ORACLE_STALENESS && p > 0);

        collateralUSD = (collateral * price) / 1e18;

        ratio = debt == 0
            ? type(uint256).max
            : (collateral * price * 100) / (debt * 1e18);

        uint256 safeDebtLimit = (collateralUSD * 100) / COLLATERAL_RATIO;
        mintable = safeDebtLimit > debt ? safeDebtLimit - debt : 0;

        systemRatio = systemHealth();
    }

    function repayToHealth(address user) external view returns (uint256 repayNeeded) {
        Vault storage v = vaults[user];
        if (v.debt == 0) return 0;

        (uint256 p,) = oracle.peekPrice();
        uint256 price = p > 0 ? p : lastOraclePrice;

        uint256 requiredDebt = (v.collateral * price * 100) / (COLLATERAL_RATIO * 1e18);

        repayNeeded = v.debt > requiredDebt ? v.debt - requiredDebt : 0;
    }

    function isLiquidatable(address user)
        external
        view
        returns (bool canLiquidate, uint256 currentRatio)
    {
        Vault storage v = vaults[user];
        if (v.debt == 0) return (false, type(uint256).max);

        (uint256 p,) = oracle.peekPrice();
        uint256 price = p > 0 ? p : lastOraclePrice;

        currentRatio = (v.collateral * price * 100) / (v.debt * 1e18);
        canLiquidate = currentRatio < LIQUIDATION_RATIO;
    }

    /*//////////////////////////////////////////////////////////////
                           FALLBACK
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}
    fallback() external payable {}
}
