// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title pSunDAI_ASA - Autonomous Stable Asset for SunDAI Vault
/// @notice Immutable, vault-linked, non-upgradeable SunDAI ASA
contract pSunDAI is ERC20, ReentrancyGuard {
    address public vault;
    address public immutable deployer;
    bool public vaultSet;

    modifier onlyVault() {
        require(msg.sender == vault && vault != address(0), "Not Vault");
        _;
    }

    constructor() ERC20("SunDai (Autonomous Stable Asset)", "pSUNDAI") {
        deployer = msg.sender;
    }

    /// @notice One-time vault linkage
    function setVault(address _vault) external {
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

    function burn(address from, uint256 amount) external onlyVault nonReentrant {
        _burn(from, amount);
        emit Burned(from, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /* ---------------- Events ---------------- */
    event VaultLinked(address indexed vault, address indexed by);
    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);
}
