// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * ╔══════════════════════════════════════════════════════════════════════╗
 * ║             pSunDAIoraclePLSXHybrid — ELITE TEAM6 (v5.1 Final)       ║
 * ║                                                                      ║
 * ║   Self-Healing Oracle for Autonomous Stable Assets (ASA)             ║
 * ║   - Median-filtered TWAP + Spot hybrid                               ║
 * ║   - 4h confirmation before stepping (prevents flash crashes)         ║
 * ║   - Incremental price stepping after confirmation                    ║
 * ║   - Poke rate limiting (30min cooldown)                              ║
 * ║   - Asymmetric: 4h/5% down, 1h/10% up                                ║
 * ║   - Auto-fallback after 24h using live Uniswap pairs                 ║
 * ║   - Safe decimal normalization and low-gas median sort               ║
 * ║                                                                      ║
 * ║   IMPROVEMENTS IN V5.1:                                              ║
 * ║   ✓ 4h confirmation prevents flash crash liquidations                ║
 * ║   ✓ After confirmation, steps 5% every 30min toward target           ║
 * ║   ✓ If price recovers during confirmation, cancels & updates fast    ║
 * ║   ✓ Poke rate limiting prevents griefing                             ║
 * ║   ✓ Maintains all V4.1 safety properties                             ║
 * ║   ✓ 24h fallback still works as emergency escape                     ║
 * ║                                                                      ║
 * ║   TOTAL UPDATE TIME:                                                 ║
 * ║   Flash crash (<4h):  Ignored completely, no liquidations            ║
 * ║   Real drop (>4h):    4h confirm + 2h stepping = 6h total            ║
 * ║   Real pump (>1h):    1h confirm + 1h stepping = 2h total            ║
 * ║                                                                      ║
 * ║   Dev:     ELITE TEAM6                                               ║
 * ║   Website: https://www.sundaitoken.com                               ║
 * ║   License: MIT | Autonomous | Immutable After Launch                 ║
 * ╚══════════════════════════════════════════════════════════════════════╝
 */

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract pSunDAIoraclePLSXHybrid_5_1 {
    using Math for uint256;

    struct PairData {
        IUniswapV2Pair pair;
        uint256 priceCumulativeLast;
        uint40  blockTimestampLast;
        bool    wplsIsToken0;
    }

    // NEW: Track pending price that needs confirmation
    struct PendingPriceUpdate {
        uint256 targetPrice;      // The price we're moving toward
        uint256 firstSeenTime;    // When we first saw this divergence
        bool    isActive;         // Whether we have a pending update
    }

    // --- Core Pair Data ---
    PairData public pairDAIv1;
    PairData public pairDAIv2;
    PairData public pairUSDCv1;
    PairData public pairUSDCv2;
    PairData public pairUSDT;

    // --- Immutable Token Addresses ---
    address public immutable wpls;
    address public immutable dai;
    address public immutable usdc;
    address public immutable usdt;
    address public immutable deployer;

    address public vault;
    bool    public immutableSet;

    uint256 public lastPrice;
    uint256 public lastUpdateTimestamp;
    uint256 public lastPokeTime;
    PendingPriceUpdate public pendingUpdate;  // NEW

    // --- Constants (All from V4.1 plus new ones) ---
    uint256 public constant PRECISION         = 1e18;
    uint256 public constant MIN_RESERVE_USD   = 10_000 * 1e18;
    uint256 public constant MAX_PRICE_AGE     = 300;   // 5 min
    uint256 public constant MIN_TWAP_INTERVAL = 60;    // 1 min
    
    // NEW: Confirmation periods before stepping
    uint256 public constant CONFIRM_TIME_DOWN = 4 hours;   // 4h for drops (safe)
    uint256 public constant CONFIRM_TIME_UP   = 1 hours;   // 1h for pumps (faster)
    
    // NEW: Step sizes after confirmation
    uint256 public constant STEP_SIZE_DOWN_BPS = 500;   // 5% per step down
    uint256 public constant STEP_SIZE_UP_BPS   = 1000;  // 10% per step up
    
    // NEW: Poke rate limiting
    uint256 public constant MIN_POKE_INTERVAL = 30 minutes;
    
    // Keep small moves instant (under this threshold)
    uint256 public constant INSTANT_UPDATE_BPS = 300;  // 3% - accept immediately

    event PriceUpdated(uint256 price, uint256 timestamp, bool stepped);
    event ConfirmationStarted(uint256 targetPrice, uint256 confirmTime, bool isDown);
    event ConfirmationCancelled(uint256 reason); // reason: 0=price recovered, 1=new divergence
    event VaultSet(address vault);

    modifier onlyVault() {
        require(msg.sender == vault && vault != address(0), "Not vault");
        _;
    }

    constructor(
        address _pairDAIv1,
        address _pairDAIv2,
        address _pairUSDCv1,
        address _pairUSDCv2,
        address _pairUSDT,
        address _wpls,
        address _dai,
        address _usdc,
        address _usdt
    ) {
        require(
            _pairDAIv1 != address(0) &&
            _pairDAIv2 != address(0) &&
            _pairUSDCv1 != address(0) &&
            _pairUSDCv2 != address(0) &&
            _pairUSDT != address(0),
            "Invalid pair address"
        );
        require(
            _wpls != address(0) && _dai != address(0) && _usdc != address(0) && _usdt != address(0),
            "Invalid token address"
        );

        deployer = msg.sender;
        wpls = _wpls;
        dai  = _dai;
        usdc = _usdc;
        usdt = _usdt;

        pairDAIv1  = _initPair(_pairDAIv1, _wpls);
        pairDAIv2  = _initPair(_pairDAIv2, _wpls);
        pairUSDCv1 = _initPair(_pairUSDCv1, _wpls);
        pairUSDCv2 = _initPair(_pairUSDCv2, _wpls);
        pairUSDT   = _initPair(_pairUSDT,  _wpls);

        // Initialize with actual median price from pairs
        (uint256 initialPrice,) = _spotMedian();
        lastPrice = initialPrice > 0 ? initialPrice : 1e18;
        lastUpdateTimestamp = block.timestamp;
        lastPokeTime = block.timestamp;

        emit PriceUpdated(lastPrice, block.timestamp, false);
    }

    /* ---------------- Pair Initialization (UNCHANGED from V4.1) ---------------- */
    function _initPair(address pairAddr, address _wpls) internal view returns (PairData memory d) {
        IUniswapV2Pair p = IUniswapV2Pair(pairAddr);
        bool wplsIs0 = p.token0() == _wpls;
        require(wplsIs0 || p.token1() == _wpls, "Pair missing WPLS");
        (, , uint32 ts) = p.getReserves();
        d = PairData({
            pair: p,
            priceCumulativeLast: wplsIs0 ? p.price0CumulativeLast() : p.price1CumulativeLast(),
            blockTimestampLast: ts,
            wplsIsToken0: wplsIs0
        });
    }

    /* ---------------- Vault Link (UNCHANGED) ---------------- */
    function setVault(address _vault) external {
        require(!immutableSet, "Vault locked");
        require(msg.sender == deployer, "Only deployer");
        require(_vault != address(0), "Invalid vault");
        vault = _vault;
        immutableSet = true;
        emit VaultSet(_vault);
    }

    /* ---------------- Oracle Interface (UNCHANGED) ---------------- */
    function getPriceWithTimestamp()
        external
        onlyVault
        returns (uint256 price, uint256 timestamp)
    {
        (price, timestamp) = _updateIfNeeded();
        require(price > 0, "Invalid price");
    }

    function peekPriceView() external view returns (uint256 price, uint256 timestamp) {
        // UNCHANGED: 24h fallback still works
        if (block.timestamp - lastUpdateTimestamp > 24 hours) {
            (price,) = _spotMedian();
            if (price == 0) return (lastPrice, lastUpdateTimestamp);
            return (price, block.timestamp);
        }
        return (lastPrice, lastUpdateTimestamp);
    }

    function isHealthy() external view returns (bool) {
        return (block.timestamp - lastUpdateTimestamp) < (MAX_PRICE_AGE * 2);
    }

    /* ---------------- Internal Refresh Logic (UNCHANGED) ---------------- */
    function _updateIfNeeded() internal returns (uint256, uint256) {
        if (block.timestamp - lastUpdateTimestamp > MIN_TWAP_INTERVAL) {
            return _updateIfValid();
        }
        return (lastPrice, lastUpdateTimestamp);
    }

    /* ---------------- NEW: Main Update Logic with Confirmation ---------------- */
    function _updateIfValid() internal returns (uint256, uint256) {
        // Get median price from all pairs
        uint256 newPrice = _getMedianPrice();
        if (newPrice == 0) return (lastPrice, lastUpdateTimestamp);

        // Bootstrap mode: accept any price
        if (lastPrice == 1e18 || lastPrice == 0) {
            lastPrice = newPrice;
            lastUpdateTimestamp = block.timestamp;
            emit PriceUpdated(newPrice, block.timestamp, false);
            return (newPrice, block.timestamp);
        }

        // Process price update with confirmation logic
        return _processPriceUpdate(newPrice);
    }

    function _getMedianPrice() internal returns (uint256) {
        uint256[5] memory px;
        bool[5] memory valid;

        (px[0],, valid[0]) = _tryTWAP(pairDAIv1);
        (px[1],, valid[1]) = _tryTWAP(pairDAIv2);
        (px[2],, valid[2]) = _tryTWAP(pairUSDCv1);
        (px[3],, valid[3]) = _tryTWAP(pairUSDCv2);
        (px[4],, valid[4]) = _tryTWAP(pairUSDT);

        uint256[5] memory prices;
        uint8 count;
        for (uint8 i; i < 5; i++) {
            if (!valid[i] || px[i] == 0) continue;
            uint8 dec = (i >= 2) ? 6 : 18;
            prices[count++] = _normalizeTo1e18(px[i], dec);
        }

        if (count == 0) return 0;
        return _median(prices, count);
    }

    function _processPriceUpdate(uint256 newPrice) internal returns (uint256, uint256) {
        uint256 diff = newPrice > lastPrice ? newPrice - lastPrice : lastPrice - newPrice;
        uint256 divergenceBps = (diff * 10_000) / lastPrice;

        // Small move - accept immediately
        if (divergenceBps <= INSTANT_UPDATE_BPS) {
            if (pendingUpdate.isActive) {
                delete pendingUpdate;
                emit ConfirmationCancelled(0);
            }
            
            lastPrice = newPrice;
            lastUpdateTimestamp = block.timestamp;
            emit PriceUpdated(newPrice, block.timestamp, false);
            return (newPrice, block.timestamp);
        }

        // Large move - handle with confirmation
        return _handleLargeMove(newPrice, divergenceBps);
    }

    function _handleLargeMove(uint256 newPrice, uint256 divergenceBps) internal returns (uint256, uint256) {
        bool isDownward = newPrice < lastPrice;
        
        if (!pendingUpdate.isActive) {
            // Start new confirmation period
            return _startConfirmation(newPrice, isDownward);
        }
        
        // Check existing pending update
        return _processPendingUpdate(newPrice, divergenceBps, isDownward);
    }

    function _startConfirmation(uint256 newPrice, bool isDownward) internal returns (uint256, uint256) {
        uint256 confirmTime = isDownward ? CONFIRM_TIME_DOWN : CONFIRM_TIME_UP;
        
        pendingUpdate = PendingPriceUpdate({
            targetPrice: newPrice,
            firstSeenTime: block.timestamp,
            isActive: true
        });
        
        emit ConfirmationStarted(newPrice, confirmTime, isDownward);
        return (lastPrice, lastUpdateTimestamp);
    }

    function _processPendingUpdate(uint256 newPrice, uint256 divergenceBps, bool isDownward) internal returns (uint256, uint256) {
        // Check if target price changed significantly
        uint256 pendingDiff = newPrice > pendingUpdate.targetPrice 
            ? newPrice - pendingUpdate.targetPrice 
            : pendingUpdate.targetPrice - newPrice;
        uint256 pendingDivergenceBps = (pendingDiff * 10_000) / pendingUpdate.targetPrice;
        
        if (pendingDivergenceBps > INSTANT_UPDATE_BPS) {
            // Target changed - restart confirmation
            emit ConfirmationCancelled(1);
            return _startConfirmation(newPrice, isDownward);
        }
        
        // Check if price recovered
        if (divergenceBps <= INSTANT_UPDATE_BPS) {
            delete pendingUpdate;
            emit ConfirmationCancelled(0);
            
            lastPrice = newPrice;
            lastUpdateTimestamp = block.timestamp;
            emit PriceUpdated(newPrice, block.timestamp, false);
            return (newPrice, block.timestamp);
        }
        
        // Check if confirmation period passed
        uint256 confirmTime = isDownward ? CONFIRM_TIME_DOWN : CONFIRM_TIME_UP;
        uint256 timeInConfirmation = block.timestamp - pendingUpdate.firstSeenTime;
        
        if (timeInConfirmation < confirmTime) {
            return (lastPrice, lastUpdateTimestamp);
        }
        
        // Confirmation passed - step toward target
        return _stepTowardTarget(isDownward);
    }

    function _stepTowardTarget(bool isDownward) internal returns (uint256, uint256) {
        uint256 stepSizeBps = isDownward ? STEP_SIZE_DOWN_BPS : STEP_SIZE_UP_BPS;
        uint256 maxMove = (lastPrice * stepSizeBps) / 10_000;
        
        uint256 remainingDiff = pendingUpdate.targetPrice > lastPrice
            ? pendingUpdate.targetPrice - lastPrice
            : lastPrice - pendingUpdate.targetPrice;
        
        uint256 updatedPrice;
        if (remainingDiff <= maxMove) {
            // Reached target
            updatedPrice = pendingUpdate.targetPrice;
            delete pendingUpdate;
        } else {
            // Step toward target
            updatedPrice = pendingUpdate.targetPrice > lastPrice
                ? lastPrice + maxMove
                : lastPrice - maxMove;
        }
        
        lastPrice = updatedPrice;
        lastUpdateTimestamp = block.timestamp;
        emit PriceUpdated(updatedPrice, block.timestamp, true);
        return (updatedPrice, block.timestamp);
    }

    /* ---------------- TWAP + Spot (COMPLETELY UNCHANGED from V4.1) ---------------- */
    function _tryTWAP(PairData storage d)
        internal
        returns (uint256 price, uint256 timestamp, bool valid)
    {
        (uint112 r0, uint112 r1, uint32 tsPair) = d.pair.getReserves();
        if (r0 == 0 || r1 == 0) return (0, tsPair, false);
        if (block.timestamp <= d.blockTimestampLast) return (0, tsPair, false);

        uint112 stableReserve = d.wplsIsToken0 ? r1 : r0;
        uint8 dec = d.wplsIsToken0 ? _getDecimals(d.pair.token1()) : _getDecimals(d.pair.token0());
        uint256 scaledReserve = stableReserve * (10 ** (18 - dec));
        if (scaledReserve < MIN_RESERVE_USD) return (0, tsPair, false);

        uint32 elapsed = uint32(block.timestamp - uint256(d.blockTimestampLast));
        if (elapsed < MIN_TWAP_INTERVAL) {
            price = d.wplsIsToken0 ? (uint256(r1) * PRECISION) / r0 : (uint256(r0) * PRECISION) / r1;
            return (price, tsPair, true);
        }

        uint256 cumulative = d.wplsIsToken0
            ? d.pair.price0CumulativeLast()
            : d.pair.price1CumulativeLast();

        unchecked {
            uint32 delta = uint32(block.timestamp) - tsPair;
            if (delta > 0) {
                uint256 px = d.wplsIsToken0 ? (uint256(r1) << 112) / r0 : (uint256(r0) << 112) / r1;
                cumulative += px * delta;
            }
        }

        uint256 diff = cumulative - d.priceCumulativeLast;
        uint256 avg = Math.mulDiv(diff, PRECISION, uint256(elapsed) << 112);

        d.priceCumulativeLast = cumulative;
        d.blockTimestampLast = uint40(block.timestamp);
        bool fresh = (block.timestamp - tsPair <= MAX_PRICE_AGE);
        return (avg, tsPair, fresh);
    }

    /* ---------------- Helpers (COMPLETELY UNCHANGED from V4.1) ---------------- */
    function _normalizeTo1e18(uint256 price, uint8 dec) internal pure returns (uint256) {
        if (dec == 18) return price;
        if (dec < 18) return price * 10 ** (18 - dec);
        return price / 10 ** (dec - 18);
    }

    function _getDecimals(address token) internal view returns (uint8) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSignature("decimals()"));
        if (!ok || data.length == 0) return 18;
        uint8 d = abi.decode(data, (uint8));
        return (d < 6 || d > 18) ? 18 : d;
    }

    function _median(uint256[5] memory a, uint8 count) internal pure returns (uint256) {
        for (uint8 i = 1; i < count; i++) {
            uint256 key = a[i];
            uint8 j = i;
            while (j > 0 && a[j - 1] > key) {
                a[j] = a[j - 1];
                j--;
            }
            a[j] = key;
        }
        return a[count / 2];
    }

    function _spotMedian() internal view returns (uint256 price, uint256 ts) {
        uint256[5] memory px;
        uint8 count;
        PairData[5] memory arr = [pairDAIv1, pairDAIv2, pairUSDCv1, pairUSDCv2, pairUSDT];
        for (uint i = 0; i < 5; i++) {
            (uint112 r0, uint112 r1, uint32 t0) = arr[i].pair.getReserves();
            if (r0 == 0 || r1 == 0) continue;
            uint256 p = arr[i].wplsIsToken0 ? (uint256(r1) * PRECISION) / r0 : (uint256(r0) * PRECISION) / r1;
            uint8 dec = arr[i].wplsIsToken0 ? _getDecimals(arr[i].pair.token1()) : _getDecimals(arr[i].pair.token0());
            p = _normalizeTo1e18(p, dec);
            px[count++] = p;
            ts = t0;
        }
        if (count == 0) return (0, block.timestamp);
        return (_median(px, count), ts);
    }

    /* ---------------- Manual Refresh with Rate Limiting ---------------- */
    function poke() external {
        require(
            block.timestamp >= lastPokeTime + MIN_POKE_INTERVAL,
            "Poke cooldown - wait 30 min"
        );
        
        lastPokeTime = block.timestamp;
        _updateIfValid();
    }

    /* ---------------- NEW: Monitoring Functions ---------------- */
    
    function canPoke() external view returns (bool) {
        return block.timestamp >= lastPokeTime + MIN_POKE_INTERVAL;
    }
    
    function timeUntilNextPoke() external view returns (uint256) {
        if (block.timestamp >= lastPokeTime + MIN_POKE_INTERVAL) {
            return 0;
        }
        return (lastPokeTime + MIN_POKE_INTERVAL) - block.timestamp;
    }
    
    function getPriceStatus() external view returns (
        uint256 currentPrice,
        uint256 marketPrice,
        uint256 divergenceBps,
        bool inConfirmation,
        uint256 confirmTimeRemaining,
        uint256 targetPrice
    ) {
        currentPrice = lastPrice;
        (marketPrice,) = _spotMedian();
        
        if (marketPrice > 0 && currentPrice > 0) {
            uint256 diff = marketPrice > currentPrice 
                ? marketPrice - currentPrice 
                : currentPrice - marketPrice;
            divergenceBps = (diff * 10_000) / currentPrice;
        }
        
        inConfirmation = pendingUpdate.isActive;
        targetPrice = pendingUpdate.targetPrice;
        
        if (inConfirmation) {
            bool isDown = targetPrice < currentPrice;
            uint256 confirmTime = isDown ? CONFIRM_TIME_DOWN : CONFIRM_TIME_UP;
            uint256 elapsed = block.timestamp - pendingUpdate.firstSeenTime;
            
            if (elapsed < confirmTime) {
                confirmTimeRemaining = confirmTime - elapsed;
            } else {
                confirmTimeRemaining = 0; // Ready to step
            }
        }
    }
}
