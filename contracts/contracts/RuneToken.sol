// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// ============================================================
// $RUNE — the AgentRune utility token (BEP-20 / ERC-20)
// BNB Smart Chain Mainnet (Chain ID 56)
// Adapted from THYRK's $THYRK (nugian10/THYRK), rescaled x2
// because AgentRune pays 40 $RUNE per mint (THYRK: 20).
// ------------------------------------------------------------
// - Name "Rune", symbol "RUNE", 18 decimals.
// - Max supply 444,444, enforced on-chain by ERC20Capped.
//   NOTHING may mint above the cap, from any source.
//   The reserve is NEVER pre-minted to anyone.
// - How $RUNE is created (all amounts fixed):
//     mint (free OR paid): 40 $RUNE per mint (via AgentRune)
//     burn NFT            : Dormant 40 / Awakened 100 /
//                           Empowered 240 / Ascended 600
//                           (a free Dormant also burns for 40)
// - How $RUNE is spent (all spent token is BURNED):
//     redeem Prime : 3,000 $RUNE -> 1 Prime NFT (1 max)
//     token mint   : 200 $RUNE -> 1 mint (max 3 per wallet)
//     upgrade      : 3 Dormant + 100 -> 1 Awakened
//                    3 Awakened + 200 -> 1 Empowered
//                    3 Empowered + 400 -> 1 Ascended
// - Minting is restricted to authorized minters (the
//   AgentRune NFT contract). The owner manages the minter
//   list; the owner itself cannot mint.
// - NO X-repost claim system: THYRK's token carries a
//   dormant claimRepost() for a system that does not exist
//   yet, and X actions cannot be verified on-chain. It is
//   deliberately NOT copied here.
// - Owner = deployer wallet. Deploy this contract FIRST,
//   then AgentRune with this contract's address, then call
//   setMinter(nft, true).
//
// This contract is SOURCE-VERIFIABLE on BscScan.
// It is NOT an independent audit — keep that
// disclosure on the site.
// ============================================================

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RuneToken is ERC20, ERC20Burnable, ERC20Capped, Ownable {
    /// @notice Hard cap: 444,444 $RUNE. Enforced by ERC20Capped
    /// on every mint. Max creatable from mint+burn is
    /// 177,720 (4,443 mints x 40) + burn rewards; the rest
    /// is RESERVE and is never minted by this contract.
    uint256 public constant MAX_SUPPLY = 444444 ether;

    /// @notice Addresses allowed to mint (AgentRune NFT).
    /// Managed by the owner.
    mapping(address => bool) public minters;

    event MinterSet(address indexed minter, bool allowed);

    error NotMinter();

    constructor(address initialOwner)
        ERC20("Rune", "RUNE")
        ERC20Capped(MAX_SUPPLY)
        Ownable(initialOwner)
    {}

    /// @notice Cap enforcement: ERC20Capped checks totalSupply
    /// + value <= cap on every mint (via _update).
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Capped)
    {
        super._update(from, to, value);
    }

    /// @notice Authorize / revoke a minter (AgentRune NFT).
    /// Owner-only.
    function setMinter(address minter, bool allowed) external onlyOwner {
        minters[minter] = allowed;
        emit MinterSet(minter, allowed);
    }

    /// @notice Mint $RUNE to `to`. Only authorized minters
    /// (AgentRune for mint bonuses and burn rewards).
    /// The cap is enforced by ERC20Capped.
    function mint(address to, uint256 amount) external {
        if (!minters[msg.sender]) revert NotMinter();
        _mint(to, amount);
    }
}
