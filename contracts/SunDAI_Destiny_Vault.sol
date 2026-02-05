// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

interface IPSunDAIVault {
    function depositPLS() external payable;
    function mint(uint256 amount) external;
    function maxMintable(address user) external view returns (uint256);
}

interface IPSunDAI is IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWPLS {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

interface ISunDialOracle {
    function getPrice() external view returns (uint256 price);
}

/// @notice Destiny Vault in Black Hole mode: nukes all SunDAI/PLP into PLS Collateral
contract DestinyVaultBlackHole is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable sundai;
    IPSunDAI public immutable psundaiToken;
    IERC20 public immutable wpls;
    IPSunDAIVault public immutable vault;
    IUniswapV2Router02 public immutable router;
    IUniswapV2Pair public immutable pairV1;
    ISunDialOracle public immutable oracle;

    uint256 public constant LP_MULTIPLIER_BPS = 15000; // 1.5x weight for LP
    uint256 public constant SAFETY_BPS = 9000; // 90% of maxMint

    bool public ignited;
    bool public supernovaTriggered;
    bool public rebirthTriggered;
    uint256 public totalWeight;
    uint256 public totalPayout;

    uint256 public threshold = 1e18; // Default $1
    bool public thresholdLocked;

    struct Stake {
        uint256 sundaiAmt;
        uint256 plpAmt;
        uint256 weight;
        bool claimed;
    }

    mapping(address => Stake) public stakes;

    event Staked(address indexed user, uint256 sundaiAmt, uint256 plpAmt, uint256 weight);
    event Withdrawn(address indexed user, uint256 sundaiAmt, uint256 plpAmt);
    event Ignited(uint256 plsRecovered);
    event Supernova(uint256 plsDeposited);
    event Rebirth(uint256 minted);
    event Claimed(address indexed user, uint256 amount);
    event ThresholdUpdated(uint256 newThreshold);
    event ThresholdLocked();

    constructor(
        address _sundai,
        address _psundai,
        address _wpls,
        address _vault,
        address _router,
        address _pairV1,
        address _oracle
    ) Ownable(msg.sender) {
        sundai = IERC20(_sundai);
        psundaiToken = IPSunDAI(_psundai);
        wpls = IERC20(_wpls);
        vault = IPSunDAIVault(_vault);
        router = IUniswapV2Router02(_router);
        pairV1 = IUniswapV2Pair(_pairV1);
        oracle = ISunDialOracle(_oracle);
    }

    /* ---------------- Threshold Control ---------------- */
    function setThreshold(uint256 newThreshold) external onlyOwner {
        require(!thresholdLocked, "Threshold locked");
        threshold = newThreshold;
        emit ThresholdUpdated(newThreshold);
    }

    function lockThreshold() external onlyOwner {
        require(!thresholdLocked, "Already locked");
        thresholdLocked = true;
        emit ThresholdLocked();
    }

    function isLocked() external view returns (bool) {
        uint256 price = oracle.getPrice();
        return (price >= threshold || ignited);
    }

    /* ---------------- Modifiers ---------------- */
    modifier vaultUnlocked() {
        uint256 price = oracle.getPrice();
        require(price < threshold && !ignited, "Vault locked");
        _;
    }

    modifier notIgnited() {
        require(!ignited, "Already ignited");
        _;
    }

    /* ---------------- Staking ---------------- */
    function stake(uint256 sundaiAmt, uint256 plpAmt) 
        external 
        nonReentrant 
        vaultUnlocked 
    {
        require(sundaiAmt > 0 || plpAmt > 0, "Zero stake");

        Stake storage s = stakes[msg.sender];
        uint256 newWeight;

        if (sundaiAmt > 0) {
            sundai.safeTransferFrom(msg.sender, address(this), sundaiAmt);
            s.sundaiAmt += sundaiAmt;
            newWeight += sundaiAmt;
        }

        if (plpAmt > 0) {
            IERC20(address(pairV1)).safeTransferFrom(msg.sender, address(this), plpAmt);
            s.plpAmt += plpAmt;
            uint256 lpWeight = (plpAmt * LP_MULTIPLIER_BPS) / 10000;
            newWeight += lpWeight;
        }

        s.weight += newWeight;
        totalWeight += newWeight;

        emit Staked(msg.sender, sundaiAmt, plpAmt, newWeight);
    }

    function withdraw(uint256 sundaiAmt, uint256 plpAmt) 
        external 
        nonReentrant 
        vaultUnlocked 
    {
        Stake storage s = stakes[msg.sender];
        require(s.weight > 0, "Nothing staked");
        require(s.sundaiAmt >= sundaiAmt, "Not enough SunDAI staked");
        require(s.plpAmt >= plpAmt, "Not enough LP staked");

        uint256 weightRemoved;

        if (sundaiAmt > 0) {
            s.sundaiAmt -= sundaiAmt;
            sundai.safeTransfer(msg.sender, sundaiAmt);
            weightRemoved += sundaiAmt;
        }

        if (plpAmt > 0) {
            s.plpAmt -= plpAmt;
            IERC20(address(pairV1)).safeTransfer(msg.sender, plpAmt);
            uint256 lpWeight = (plpAmt * LP_MULTIPLIER_BPS) / 10000;
            weightRemoved += lpWeight;
        }

        if (weightRemoved > 0) {
            s.weight -= weightRemoved;
            totalWeight -= weightRemoved;
        }

        emit Withdrawn(msg.sender, sundaiAmt, plpAmt);
    }

    /* ---------------- Ignite ---------------- */
    function ignite() external nonReentrant notIgnited {
        uint256 price = oracle.getPrice();
        require(price >= threshold, "Not at threshold yet");

        ignited = true;

        uint256 sundaiBal = sundai.balanceOf(address(this));
        uint256 plpBal = IERC20(address(pairV1)).balanceOf(address(this));
        require(sundaiBal > 0 || plpBal > 0, "Empty vault");

        // 1️⃣ Break LP → unwrap LP’s WPLS
        if (plpBal > 0) {
            IERC20(address(pairV1)).approve(address(router), 0);
            IERC20(address(pairV1)).approve(address(router), plpBal);

            (uint256 amtSundai, uint256 amtWPLS) = router.removeLiquidity(
                address(sundai),
                address(wpls),
                plpBal,
                1,
                1,
                address(this),
                block.timestamp + 600
            );

            sundaiBal += amtSundai;

            if (amtWPLS > 0) {
                IWPLS(address(wpls)).withdraw(amtWPLS);
            }
        }

        // 2️⃣ Swap ALL SunDAI → WPLS → unwrap
if (sundaiBal > 0) {
    sundai.approve(address(router), 0);
    sundai.approve(address(router), sundaiBal);

    address[] memory path = new address[](2);
    path[0] = address(sundai);
    path[1] = address(wpls);

    router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
        sundaiBal,
        0, // ⚠️ Consider adding slippage protection
        path,
        address(this),
        block.timestamp + 600
    );

    uint256 wplsBal = wpls.balanceOf(address(this));
    if (wplsBal > 0) {
        IWPLS(address(wpls)).withdraw(wplsBal);
    }
}

        // 3️⃣ Final PLS balance check
        uint256 plsBal = address(this).balance;
        require(plsBal > 0, "No PLS recovered");

        emit Ignited(plsBal);
    }

    /* ---------------- Supernova ---------------- */
    function supernova() external nonReentrant {
        require(ignited, "Not ignited");
        require(!supernovaTriggered, "Already triggered");

        uint256 plsBal = address(this).balance;
        require(plsBal > 0, "No PLS");

        vault.depositPLS{value: plsBal}();
        supernovaTriggered = true;

        emit Supernova(plsBal);
    }

    /* ---------------- Rebirth ---------------- */
    function rebirth() external nonReentrant {
        require(ignited && supernovaTriggered, "Not ready");
        require(!rebirthTriggered, "Already rebirthed");

        uint256 maxMint = vault.maxMintable(address(this));
        require(maxMint > 0, "Vault says 0 mintable");

        uint256 safeMint = (maxMint * SAFETY_BPS) / 10000;
        require(safeMint > 0, "Zero mint");

        uint256 preBal = psundaiToken.balanceOf(address(this));
        vault.mint(safeMint);
        uint256 minted = psundaiToken.balanceOf(address(this)) - preBal;
        require(minted > 0, "No pSunDAI minted");

        totalPayout = minted;
        rebirthTriggered = true;

        emit Rebirth(minted);
    }

    /* ---------------- Claim ---------------- */
    function claim() external nonReentrant {
        require(rebirthTriggered, "Not finished");
        require(totalWeight > 0, "No total weight");

        Stake storage s = stakes[msg.sender];
        require(!s.claimed && s.weight > 0, "Already claimed or none");

        uint256 share = (totalPayout * s.weight) / totalWeight;
        require(share > 0, "Zero payout");

        s.claimed = true;
        IERC20(address(psundaiToken)).safeTransfer(msg.sender, share);

        emit Claimed(msg.sender, share);
    }

    receive() external payable {}

            /* ---------------- Emergency Exit ---------------- */

    bool public emergencyExitTriggered;
    uint256 public snapshotPlsBal;

    event EmergencyExitEnabled(uint256 totalPlsAvailable);
    event EmergencyClaim(address indexed user, uint256 amountSundai, uint256 amountPlp, uint256 amountPls);

    function enableEmergencyExit() external onlyOwner nonReentrant {
        require(!supernovaTriggered, "Supernova already moved funds");
        require(!emergencyExitTriggered, "Already triggered");
        require(oracle.getPrice() >= threshold, "Vault not locked by threshold");

        if (ignited) {
            // Ignite happened, PLS is in vault
            snapshotPlsBal = address(this).balance;
            require(snapshotPlsBal > 0, "No PLS to recover");
        }

        emergencyExitTriggered = true;

        emit EmergencyExitEnabled(snapshotPlsBal);
    }

    function claimEmergency() external nonReentrant {
        require(emergencyExitTriggered, "Exit not enabled");

        Stake storage s = stakes[msg.sender];
        require(!s.claimed && s.weight > 0, "Already claimed or none");

        if (!ignited) {
            // 🔹 Pre-Ignite: return original assets (SunDAI + PLP)
            uint256 sundaiAmt = s.sundaiAmt;
            uint256 plpAmt = s.plpAmt;

            s.claimed = true;
            s.sundaiAmt = 0;
            s.plpAmt = 0;

            if (sundaiAmt > 0) {
                sundai.safeTransfer(msg.sender, sundaiAmt);
            }
            if (plpAmt > 0) {
                IERC20(address(pairV1)).safeTransfer(msg.sender, plpAmt);
            }

            emit EmergencyClaim(msg.sender, sundaiAmt, plpAmt, 0);

        } else {
            // 🔹 Post-Ignite, Pre-Supernova: return proportional PLS
            uint256 share = (snapshotPlsBal * s.weight) / totalWeight;
            require(share > 0, "Zero payout");

            s.claimed = true;
            (bool success, ) = msg.sender.call{value: share}("");
            require(success, "PLS transfer failed");

            emit EmergencyClaim(msg.sender, 0, 0, share);
        }
    }


}
