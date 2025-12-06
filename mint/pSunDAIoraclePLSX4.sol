// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * ╔══════════════════════════════════════════════════════════════════════╗
 * ║               pSunDAIoraclePLSX4 — ELITE TEAM6 (Creeping Oracle)     ║
 * ║                                                                      ║
 * ║   Immutable Multi-Pair Oracle for Autonomous Stable Assets (ASA)     ║
 * ║   - Median-filtered TWAP + Spot hybrid                               ║
 * ║   - Self-refreshing every minute (no upkeep required)                ║
 * ║   - Slow "creep" toward confirmed multi-pair consensus               ║
 * ║   - Fully autonomous — PulseChain native                             ║
 * ║                                                                      ║
 * ║   Pairs: DAI v1, DAI v2, USDC v1, USDC v2, USDT v1                   ║
 * ║                                                                      ║
 * ║   Dev:     ELITE TEAM6                                               ║
 * ║   Website: https://www.sundaitoken.com                               ║
 * ║   License: MIT | Autonomous | Immutable                              ║
 * ╚══════════════════════════════════════════════════════════════════════╝
 */

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract pSunDAIoraclePLSX4 {
    using Math for uint256;

    struct PairData {
        IUniswapV2Pair pair;
        uint256 priceCumulativeLast;
        uint40  blockTimestampLast;
        bool    wplsIsToken0;
    }

    // --- Core Pairs ---
    PairData public pairDAIv1;
    PairData public pairDAIv2;
    PairData public pairUSDCv1;
    PairData public pairUSDCv2;
    PairData public pairUSDT;

    // --- Immutable Addresses ---
    address public immutable wpls;
    address public immutable dai;
    address public immutable usdc;
    address public immutable usdt;
    address public immutable deployer;

    // --- Vault Binding ---
    address public vault;
    bool    public immutableSet;

    // --- Oracle State ---
    uint256 public lastPrice = 1e18;
    uint256 public lastUpdateTimestamp;

    // --- Constants ---
    uint256 public constant PRECISION         = 1e18;
    uint256 public constant MIN_RESERVE_USD   = 10_000 * 1e18;
    uint256 public constant MAX_DEVIATION_BPS = 500;     // ±5 %
    uint256 public constant MAX_PRICE_AGE     = 300;     // 5 min
    uint256 public constant MIN_TWAP_INTERVAL = 60;      // 1 min

    // --- Creep Logic ---
    uint256 private pendingPrice;
    uint8    private confirmations;
    uint8    private constant MAX_CONFIRMATIONS = 3;
    uint16   private constant CREEP_STEP_BPS = 1000; // 10%

    event PriceUpdated(uint256 price, uint256 timestamp);
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

        lastUpdateTimestamp = block.timestamp;
    }

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

    /* ---------------- One-time vault linkage ---------------- */
    function setVault(address _vault) external {
        require(!immutableSet, "Vault locked");
        require(msg.sender == deployer, "Only deployer");
        require(_vault != address(0), "Invalid vault");
        vault = _vault;
        immutableSet = true;
        emit VaultSet(_vault);
    }

    /* ---------------- Oracle interface ---------------- */
    function getPriceWithTimestamp()
        external
        onlyVault
        returns (uint256 price, uint256 timestamp)
    {
        (price, timestamp) = _updateIfNeeded();
        require(price > 0, "Invalid price");
    }

    function peekPriceView() external view returns (uint256 price, uint256 timestamp) {
        return (lastPrice, lastUpdateTimestamp);
    }

    function isHealthy() external view returns (bool) {
        return (block.timestamp - lastUpdateTimestamp) < (MAX_PRICE_AGE * 2);
    }

    function _updateIfNeeded() internal returns (uint256, uint256) {
        if (block.timestamp - lastUpdateTimestamp > MIN_TWAP_INTERVAL) {
            return _updateIfValid();
        }
        return (lastPrice, lastUpdateTimestamp);
    }

    /* ---------------- Core price computation with creeping ---------------- */
    function _updateIfValid() internal returns (uint256, uint256) {
        uint256[5] memory px;
        bool[5] memory valid;

        (px[0],, valid[0]) = _tryTWAP(pairDAIv1);
        (px[1],, valid[1]) = _tryTWAP(pairDAIv2);
        (px[2],, valid[2]) = _tryTWAP(pairUSDCv1);
        (px[3],, valid[3]) = _tryTWAP(pairUSDCv2);
        (px[4],, valid[4]) = _tryTWAP(pairUSDT);

        uint256[5] memory prices;
        uint8 count;
        if (valid[0]) prices[count++] = px[0];
        if (valid[1]) prices[count++] = px[1];
        if (valid[2]) prices[count++] = _normalizeTo1e18(px[2], 6);
        if (valid[3]) prices[count++] = _normalizeTo1e18(px[3], 6);
        if (valid[4]) prices[count++] = _normalizeTo1e18(px[4], 6);

        uint256 newPrice;
        if (count == 0) newPrice = lastPrice;
        else if (count == 1) newPrice = prices[0];
        else {
            for (uint i = 0; i < count; i++) {
                for (uint j = i + 1; j < count; j++) {
                    if (prices[j] < prices[i]) (prices[i], prices[j]) = (prices[j], prices[i]);
                }
            }
            newPrice = prices[count / 2];
        }

        bool bootstrap = (lastPrice == 1e18 || lastPrice == 0);
        if (bootstrap) {
            lastPrice = newPrice;
            lastUpdateTimestamp = block.timestamp;
            emit PriceUpdated(newPrice, block.timestamp);
            return (newPrice, block.timestamp);
        }

        uint256 diff = newPrice > lastPrice ? newPrice - lastPrice : lastPrice - newPrice;
        bool outOfRange = (diff * 10_000 / lastPrice > MAX_DEVIATION_BPS);

        if (outOfRange) {
            if (_multiPairAgreement(newPrice)) {
                confirmations++;
                if (pendingPrice == 0) pendingPrice = newPrice;

                if (confirmations >= MAX_CONFIRMATIONS) {
                    uint256 delta = pendingPrice > lastPrice
                        ? ((pendingPrice - lastPrice) * CREEP_STEP_BPS) / 10_000
                        : ((lastPrice - pendingPrice) * CREEP_STEP_BPS) / 10_000;

                    lastPrice = pendingPrice > lastPrice
                        ? lastPrice + delta
                        : lastPrice - delta;

                    confirmations = 0;
                    pendingPrice = 0;
                }
            } else {
                confirmations = 0;
                pendingPrice = 0;
            }
        } else {
            lastPrice = newPrice;
            confirmations = 0;
            pendingPrice = 0;
        }

        lastUpdateTimestamp = block.timestamp;
        emit PriceUpdated(lastPrice, block.timestamp);
        return (lastPrice, block.timestamp);
    }

    /* ---------------- TWAP + Spot hybrid ---------------- */
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

    /* ---------------- Helper: Multi-Pair Confirmation ---------------- */
    function _multiPairAgreement(uint256 candidate) internal view returns (bool) {
        uint256 agree;
        uint256[3] memory px;

        (px[0],) = _spotPrice(pairDAIv1);
        (px[1],) = _spotPrice(pairUSDCv1);
        (px[2],) = _spotPrice(pairUSDT);

        for (uint i = 0; i < 3; i++) {
            if (px[i] > (candidate * 90) / 100 && px[i] < (candidate * 110) / 100) {
                agree++;
            }
        }
        return agree >= 2;
    }

    /* --- ✅ Normalized spot price --- */
    function _spotPrice(PairData storage d) internal view returns (uint256 price, uint256 ts) {
        (uint112 r0, uint112 r1, uint32 tsPair) = d.pair.getReserves();
        if (r0 == 0 || r1 == 0) return (0, tsPair);

        address tokenStable = d.wplsIsToken0 ? d.pair.token1() : d.pair.token0();
        uint8 dec = _getDecimals(tokenStable);
        uint256 scale = 10 ** (18 - dec);

        if (d.wplsIsToken0) {
            price = (uint256(r1) * scale * PRECISION) / r0;
        } else {
            price = (uint256(r0) * scale * PRECISION) / r1;
        }

        ts = tsPair;
    }

    /* ---------------- Helpers ---------------- */
    function _normalizeTo1e18(uint256 price, uint8 dec)
        internal
        pure
        returns (uint256)
    {
        return dec == 6 ? price * 1e12 : price;
    }

    function _getDecimals(address token) internal view returns (uint8) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSignature("decimals()"));
        if (!ok || data.length != 32) return 18;
        uint8 d = abi.decode(data, (uint8));
        return (d < 6 || d > 18) ? 18 : d;
    }
}
