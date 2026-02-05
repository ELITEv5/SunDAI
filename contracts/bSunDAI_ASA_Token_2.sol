// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * ╔════════════════════════════════════════════════════════════╗
 * ║                SunDAI Autonomous Stable Asset              ║
 * ║          Autonomous Stable Asset for Base Chain            ║
 * ║                                                            ║
 * ║   License:  MIT | Autonomous | No Admin | No Upgrade Keys  ║
 * ║                                                            ║
 * ║   v1.0.1 PATCH (TVL-GRADE TRUST MINIMIZATION):             ║
 * ║   ✓ Vault can ONLY burn its OWN balance                    ║
 * ║   ✓ Users/liquidators repay by transferring to vault       ║
 * ║   ✓ Optional burnFrom uses ERC20 allowance (standard)      ║
 * ║   ✓ Keeps one-time vault linkage + immutable design        ║
 * ╚════════════════════════════════════════════════════════════╝
 *
 * IMPORTANT INTEGRATION NOTE:
 * - With this token, the vault MUST collect bSUNDAI first (transferFrom or permit)
 *   then burn from itself.
 * - This removes "vault can burn anyone" authority (trust-minimized).
 */

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract bSunDAI is ERC20Permit, ReentrancyGuard {
    address public immutable deployer;

    address public vault;
    bool public vaultSet;

    string public constant PROTOCOL_NAME = "SunDAI - Autonomous Stable Asset for Base";
    string public constant PROTOCOL_VERSION = "v1.0.1";
    string public constant PROTOCOL_DEV = "Elite Team6";

    modifier onlyVault() {
        require(msg.sender == vault && vault != address(0), "Not authorized");
        _;
    }

    event VaultLinked(address indexed vault, address indexed by);
    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);

    constructor()
        ERC20("SunDAI Autonomous Stable Asset", "bSUNDAI")
        ERC20Permit("SunDAI Autonomous Stable Asset")
    {
        deployer = msg.sender;
    }

    function setVault(address _vault) external nonReentrant {
        require(!vaultSet, "Vault already set");
        require(msg.sender == deployer, "Only deployer");
        require(_vault != address(0), "Invalid vault");
        vault = _vault;
        vaultSet = true;
        emit VaultLinked(_vault, msg.sender);
    }

    function mint(address to, uint256 amount) external onlyVault nonReentrant {
        _mint(to, amount);
        emit Minted(to, amount);
    }

    /**
     * @notice Burn tokens from the VAULT's own balance
     * @dev Vault must hold tokens first (vault pulls tokens via transferFrom)
     */
    function burn(uint256 amount) external onlyVault nonReentrant {
        _burn(msg.sender, amount); // msg.sender == vault
        emit Burned(msg.sender, amount);
    }

    /**
     * @notice Optional allowance-based burn from a user (standard)
     * @dev Spender is the vault (msg.sender). Requires user approval or permit.
     */
    function burnFrom(address from, uint256 amount) external onlyVault nonReentrant {
        uint256 currentAllowance = allowance(from, msg.sender); // vault is spender
        require(currentAllowance >= amount, "Insufficient allowance");
        _approve(from, msg.sender, currentAllowance - amount);
        _burn(from, amount);
        emit Burned(from, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function getVersion() external pure returns (string memory) {
        return "bSunDAI v1.0.1 | Base Autonomous Edition | Elite Team6";
    }
}
