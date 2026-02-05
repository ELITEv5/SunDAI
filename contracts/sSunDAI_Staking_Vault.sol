// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║           sSunDAI Auto-Compounding LP Vault V1.0                 ║
 * ║                                                                  ║
 * ║   Auto-compounds pSunDAI/PLS LP trading fees                     ║
 * ║   - Deposit LP → receive sSunDAI receipt tokens                  ║
 * ║   - Permissionless harvest compounds fees for all stakers        ║
 * ║   - sSunDAI appreciates vs LP over time                          ║
 * ║   - Withdraw anytime for your share of compounded LP             ║
 * ║                                                                  ║
 * ║   Pure auto-compounder, no external rewards needed               ║
 * ║   Immutable, no admin keys, no governance                        ║
 * ║                                                                  ║
 * ║   Dev: ELITE TEAM6                                               ║
 * ║   Website: https://www.sundaitoken.com                           ║
 * ╚══════════════════════════════════════════════════════════════════╝
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IPulseXPair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function mint(address to) external returns (uint256 liquidity);
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
}

interface IPulseXRouter {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
}

contract sSunDAI is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════ IMMUTABLES ═══════════════════════════
    IPulseXPair public immutable lpToken;           // pSunDAI/PLS LP token
    IERC20 public immutable token0;                 // First token in pair
    IERC20 public immutable token1;                 // Second token in pair
    IPulseXRouter public immutable router;          // PulseX router for re-adding liquidity

    string public constant VERSION = "sSunDAI_v1.0_AutoCompounder";

    // ═══════════════════════════ CONSTANTS ═══════════════════════════
    uint256 public constant MIN_DEPOSIT = 1e14;         // Minimum 0.0001 LP to prevent dust attacks
    uint256 public constant HARVEST_BATCH_BPS = 100;    // Harvest 1% of pool per call (adjustable via new deployment)
    uint256 public constant MIN_HARVEST_INTERVAL = 1 hours;  // Minimum time between harvests
    uint256 public constant SLIPPAGE_BPS = 50;          // 0.5% max slippage on re-adding liquidity

    // ═══════════════════════════ STATE ═══════════════════════════
    uint256 public lastHarvestTime;
    uint256 public totalHarvests;
    uint256 public totalFeesCompounded;  // Tracked in LP token units

    // ═══════════════════════════ EVENTS ═══════════════════════════
    event Deposited(address indexed user, uint256 lpAmount, uint256 sharesReceived);
    event Withdrawn(address indexed user, uint256 sharesRedeemed, uint256 lpAmount);
    event Harvested(address indexed caller, uint256 lpBurned, uint256 lpMinted, uint256 netGain);
    event EmergencyWithdraw(address indexed user, uint256 lpAmount);

    // ═══════════════════════════ CONSTRUCTOR ═══════════════════════════
    constructor(
        address _lpToken,
        address _router
    ) ERC20("Staked SunDAI LP", "sSunDAI") {
        require(_lpToken != address(0), "Zero LP");
        require(_router != address(0), "Zero router");
        
        lpToken = IPulseXPair(_lpToken);
        router = IPulseXRouter(_router);
        
        // Get pair tokens
        token0 = IERC20(lpToken.token0());
        token1 = IERC20(lpToken.token1());
        
        // Approve router for compounding
        token0.approve(_router, type(uint256).max);
        token1.approve(_router, type(uint256).max);
        
        lastHarvestTime = block.timestamp;
    }

    // ═══════════════════════════ USER ACTIONS ═══════════════════════════

    /**
     * @notice Deposit LP tokens and receive sSunDAI shares
     * @param lpAmount Amount of LP tokens to deposit
     * @return shares Amount of sSunDAI shares minted
     */
    function deposit(uint256 lpAmount) external nonReentrant returns (uint256 shares) {
        require(lpAmount >= MIN_DEPOSIT, "Amount too small");
        
        // Calculate shares to mint BEFORE transfer (using current pool state)
        uint256 totalLP = lpToken.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        
        if (totalShares == 0 || totalLP == 0) {
            // First deposit: 1:1 ratio
            shares = lpAmount;
        } else {
            // shares = (lpAmount * totalShares) / totalLP
            shares = (lpAmount * totalShares) / totalLP;
        }
        
        require(shares > 0, "Zero shares");
        
        // Transfer LP from user (CEI: external call after checks)
        IERC20(address(lpToken)).safeTransferFrom(msg.sender, address(this), lpAmount);
        
        // Mint sSunDAI shares
        _mint(msg.sender, shares);
        
        emit Deposited(msg.sender, lpAmount, shares);
        return shares;
    }

    /**
     * @notice Withdraw LP tokens by burning sSunDAI shares
     * @param shares Amount of sSunDAI shares to burn
     */
    function withdraw(uint256 shares) external nonReentrant returns (uint256 lpAmount) {
        require(shares > 0, "Zero shares");
        require(balanceOf(msg.sender) >= shares, "Insufficient balance");
        
        // Calculate LP to return
        uint256 totalLP = lpToken.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        
        // lpAmount = (shares * totalLP) / totalShares
        lpAmount = (shares * totalLP) / totalShares;
        require(lpAmount > 0, "Zero LP");
        
        // Burn shares
        _burn(msg.sender, shares);
        
        // Transfer LP to user
        IERC20(address(lpToken)).safeTransfer(msg.sender, lpAmount);
        
        emit Withdrawn(msg.sender, shares, lpAmount);
        return lpAmount;
    }

    /**
     * @notice Withdraw all LP by burning all user's sSunDAI shares
     */
    function withdrawAll() external nonReentrant returns (uint256 lpAmount) {
        uint256 shares = balanceOf(msg.sender);
        require(shares > 0, "No shares");
        
        // Calculate LP to return
        uint256 totalLP = lpToken.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        
        lpAmount = (shares * totalLP) / totalShares;
        require(lpAmount > 0, "Zero LP");
        
        // Burn all shares
        _burn(msg.sender, shares);
        
        // Transfer LP to user
        IERC20(address(lpToken)).safeTransfer(msg.sender, lpAmount);
        
        emit Withdrawn(msg.sender, shares, lpAmount);
        return lpAmount;
    }

    /**
     * @notice Withdraw only earned yield (compounded gains), keep principal staked
     * @dev Assumes user deposited at ~1:1 rate. Actual gains may vary based on deposit timing.
     */
    function withdrawYieldOnly() external nonReentrant returns (uint256 yieldAmount) {
        uint256 shares = balanceOf(msg.sender);
        require(shares > 0, "No shares");
        
        // Calculate current LP value
        uint256 totalLP = lpToken.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        uint256 currentValue = (shares * totalLP) / totalShares;
        
        // Estimate yield (assumes ~1:1 deposit rate)
        // If currentValue <= shares, no yield to withdraw
        require(currentValue > shares, "No yield earned yet");
        
        uint256 estimatedYield = currentValue - shares;
        
        // Calculate shares to burn for this yield amount
        uint256 sharesToBurn = (estimatedYield * totalShares) / totalLP;
        require(sharesToBurn > 0 && sharesToBurn < shares, "Invalid yield calculation");
        
        // Burn shares for yield
        _burn(msg.sender, sharesToBurn);
        
        // Transfer yield LP to user
        IERC20(address(lpToken)).safeTransfer(msg.sender, estimatedYield);
        
        emit Withdrawn(msg.sender, sharesToBurn, estimatedYield);
        return estimatedYield;
    }

    // ═══════════════════════════ HARVEST (PERMISSIONLESS) ═══════════════════════════

    /**
     * @notice Harvest trading fees and compound them back into LP
     * @dev Anyone can call this. Removes liquidity, re-adds with fees, net gain compounds
     */
    function harvest() external nonReentrant returns (uint256 netGain) {
        require(block.timestamp >= lastHarvestTime + MIN_HARVEST_INTERVAL, "Too soon");
        
        uint256 totalLP = IERC20(address(lpToken)).balanceOf(address(this));
        require(totalLP > 0, "Nothing to harvest");
        
        // Prevent harvesting dust (gas would exceed gains)
        require(totalLP >= 1e18, "TVL too small to harvest");
        
        // Calculate amount to harvest (1% of pool)
        uint256 harvestAmount = (totalLP * HARVEST_BATCH_BPS) / 10000;
        require(harvestAmount > 0, "Harvest too small");
        
        // Prevent dust harvesting
        require(harvestAmount >= MIN_DEPOSIT, "Harvest amount too small");
        
        // Step 1: Transfer LP tokens to the pair (required before calling burn)
        IERC20(address(lpToken)).safeTransfer(address(lpToken), harvestAmount);
        
        // Step 2: Burn LP tokens to get underlying tokens (with accumulated fees)
        (uint256 amount0, uint256 amount1) = lpToken.burn(address(this));
        require(amount0 > 0 && amount1 > 0, "Burn failed");
        
        // Step 3: Re-add liquidity with the tokens (including fees)
        // Calculate minimum amounts (0.5% slippage tolerance)
        uint256 amount0Min = (amount0 * (10000 - SLIPPAGE_BPS)) / 10000;
        uint256 amount1Min = (amount1 * (10000 - SLIPPAGE_BPS)) / 10000;
        
        // Add liquidity back
        (,, uint256 lpMinted) = router.addLiquidity(
            address(token0),
            address(token1),
            amount0,
            amount1,
            amount0Min,
            amount1Min,
            address(this),
            block.timestamp + 300  // 5 min deadline
        );
        
        // Step 4: Calculate net gain
        // If fees existed: lpMinted > harvestAmount
        if (lpMinted > harvestAmount) {
            netGain = lpMinted - harvestAmount;
        } else {
            netGain = 0;  // No gain (very low fees or IL)
        }
        
        // Update state
        lastHarvestTime = block.timestamp;
        totalHarvests++;
        totalFeesCompounded += netGain;
        
        emit Harvested(msg.sender, harvestAmount, lpMinted, netGain);
        
        return netGain;
    }

    // ═══════════════════════════ EMERGENCY ═══════════════════════════

    /**
     * @notice Emergency withdraw for users if contract has issues
     * @dev Bypasses normal withdraw logic, proportional share only
     */
    function emergencyWithdraw() external nonReentrant {
        uint256 shares = balanceOf(msg.sender);
        require(shares > 0, "No shares");
        
        uint256 totalLP = lpToken.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        
        uint256 lpAmount = (shares * totalLP) / totalShares;
        
        _burn(msg.sender, shares);
        IERC20(address(lpToken)).safeTransfer(msg.sender, lpAmount);
        
        emit EmergencyWithdraw(msg.sender, lpAmount);
    }

    // ═══════════════════════════ VIEW FUNCTIONS ═══════════════════════════

    /**
     * @notice Get the current exchange rate (LP per sSunDAI)
     * @return rate Amount of LP backing each sSunDAI (18 decimals)
     */
    function exchangeRate() external view returns (uint256 rate) {
        uint256 totalShares = totalSupply();
        if (totalShares == 0) return 1e18;  // 1:1 initially
        
        uint256 totalLP = lpToken.balanceOf(address(this));
        // rate = (totalLP * 1e18) / totalShares
        rate = (totalLP * 1e18) / totalShares;
        return rate;
    }

    /**
     * @notice Calculate LP amount for given shares
     * @param shares Amount of sSunDAI shares
     * @return lpAmount Equivalent LP tokens
     */
    function previewWithdraw(uint256 shares) external view returns (uint256 lpAmount) {
        uint256 totalShares = totalSupply();
        if (totalShares == 0) return 0;
        
        uint256 totalLP = lpToken.balanceOf(address(this));
        lpAmount = (shares * totalLP) / totalShares;
        return lpAmount;
    }

    /**
     * @notice Calculate shares for given LP amount
     * @param lpAmount Amount of LP tokens
     * @return shares Equivalent sSunDAI shares
     */
    function previewDeposit(uint256 lpAmount) external view returns (uint256 shares) {
        uint256 totalLP = lpToken.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        
        if (totalShares == 0 || totalLP == 0) {
            shares = lpAmount;
        } else {
            shares = (lpAmount * totalShares) / totalLP;
        }
        return shares;
    }

    /**
     * @notice Check if harvest is ready to be called
     * @return ready True if enough time has passed
     * @return timeUntilReady Seconds until harvest can be called (0 if ready)
     */
    function canHarvest() external view returns (bool ready, uint256 timeUntilReady) {
        if (block.timestamp >= lastHarvestTime + MIN_HARVEST_INTERVAL) {
            return (true, 0);
        } else {
            uint256 elapsed = block.timestamp - lastHarvestTime;
            timeUntilReady = MIN_HARVEST_INTERVAL - elapsed;
            return (false, timeUntilReady);
        }
    }

    /**
     * @notice Get user's LP balance and appreciation
     * @param user Address to check
     * @return shares User's sSunDAI balance
     * @return lpValue Equivalent LP tokens
     * @return appreciation Percentage gain over 1:1 (in basis points)
     */
    function userInfo(address user) external view returns (
        uint256 shares,
        uint256 lpValue,
        uint256 appreciation
    ) {
        shares = balanceOf(user);
        
        uint256 totalShares = totalSupply();
        if (totalShares == 0 || shares == 0) {
            return (shares, 0, 0);
        }
        
        uint256 totalLP = lpToken.balanceOf(address(this));
        lpValue = (shares * totalLP) / totalShares;
        
        // appreciation = ((lpValue - shares) * 10000) / shares
        if (lpValue > shares) {
            appreciation = ((lpValue - shares) * 10000) / shares;
        } else {
            appreciation = 0;
        }
        
        return (shares, lpValue, appreciation);
    }

    /**
     * @notice Get vault statistics
     */
    function vaultStats() external view returns (
        uint256 totalLPHeld,
        uint256 totalSharesIssued,
        uint256 currentExchangeRate,
        uint256 harvestCount,
        uint256 feesCompounded,
        uint256 timeSinceLastHarvest
    ) {
        totalLPHeld = lpToken.balanceOf(address(this));
        totalSharesIssued = totalSupply();
        
        if (totalSharesIssued == 0) {
            currentExchangeRate = 1e18;
        } else {
            currentExchangeRate = (totalLPHeld * 1e18) / totalSharesIssued;
        }
        
        harvestCount = totalHarvests;
        feesCompounded = totalFeesCompounded;
        timeSinceLastHarvest = block.timestamp - lastHarvestTime;
        
        return (
            totalLPHeld,
            totalSharesIssued,
            currentExchangeRate,
            harvestCount,
            feesCompounded,
            timeSinceLastHarvest
        );
    }

    /**
     * @notice Get user's max withdrawable LP (all their shares)
     * @param user Address to check
     * @return maxLP Maximum LP tokens user can withdraw
     */
    function maxWithdraw(address user) external view returns (uint256 maxLP) {
        uint256 shares = balanceOf(user);
        if (shares == 0) return 0;
        
        uint256 totalShares = totalSupply();
        uint256 totalLP = lpToken.balanceOf(address(this));
        
        maxLP = (shares * totalLP) / totalShares;
        return maxLP;
    }

    /**
     * @notice Get user's complete position info (all-in-one for frontend)
     * @param user Address to check
     * @return sharesOwned User's sSunDAI balance
     * @return lpValue Current LP value of shares
     * @return appreciationBps Gain in basis points (100 = 1%)
     * @return appreciationPercent Gain as percentage string representation
     * @return depositedLP Original LP deposited (approximation, assumes 1:1 at deposit)
     * @return earnedLP Earned LP from compounding
     */
    function positionInfo(address user) external view returns (
        uint256 sharesOwned,
        uint256 lpValue,
        uint256 appreciationBps,
        uint256 appreciationPercent,
        uint256 depositedLP,
        uint256 earnedLP
    ) {
        sharesOwned = balanceOf(user);
        
        if (sharesOwned == 0) {
            return (0, 0, 0, 0, 0, 0);
        }
        
        uint256 totalShares = totalSupply();
        uint256 totalLP = lpToken.balanceOf(address(this));
        
        lpValue = (sharesOwned * totalLP) / totalShares;
        
        // Approximation: assume user deposited when rate was closer to 1:1
        // This is an estimate - actual deposit could be at different rate
        depositedLP = sharesOwned;
        
        if (lpValue > depositedLP) {
            earnedLP = lpValue - depositedLP;
            appreciationBps = ((lpValue - depositedLP) * 10000) / depositedLP;
            appreciationPercent = appreciationBps / 100;  // 156 bps = 1.56%
        } else {
            earnedLP = 0;
            appreciationBps = 0;
            appreciationPercent = 0;
        }
        
        return (sharesOwned, lpValue, appreciationBps, appreciationPercent, depositedLP, earnedLP);
    }

    /**
     * @notice Simple check: does user have a position?
     * @param user Address to check
     * @return True if user owns any sSunDAI
     */
    function hasPosition(address user) external view returns (bool) {
        return balanceOf(user) > 0;
    }

    /**
     * @notice Get LP token address
     * @return lpAddress The PulseX LP token address
     */
    function getLPToken() external view returns (address lpAddress) {
        return address(lpToken);
    }

    /**
     * @notice Get underlying pair tokens
     * @return token0Address First token in the pair
     * @return token1Address Second token in the pair
     */
    function getPairTokens() external view returns (address token0Address, address token1Address) {
        return (address(token0), address(token1));
    }
}
