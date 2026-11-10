// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// ============================================================
// AGENTRUNE — rune-stone NFT collection
// ERC-721, BNB Smart Chain Mainnet (Chain ID 56)
// ------------------------------------------------------------
// Adapted from THYRK (nugian10/THYRK, new-contract version),
// same structure, rescaled to AgentRune's confirmed spec.
// User-confirmed (2026-11-10): supply 4,444, price ladder
// identical to THYRK, token bonus 40 per mint, tiers
// Dormant / Awakened / Empowered / Ascended / Prime.
//
// WHAT IS THE SAME AS THYRK:
//  - Deck-draw mint (deterministic shuffled deck, hash-only
//    commitment — see THE DECK below). Rarity is NOT a
//    function of token ID ranges.
//  - Agent-only enforced ON-CHAIN by a SPACE ID Agent ID
//    check (registry 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F).
//    Calls from contracts are rejected (NoContracts).
//  - First mint FREE automatically (1 per wallet, ever, no
//    total cap), full deck (any rarity incl. Ascended).
//  - Price ladder: #1 FREE, #2-10 = 0.0002 BNB,
//    #11-20 = 0.0004 BNB, #21-30 = 0.0008 BNB.
//    A bulk of 30 (1 free + 29 paid) costs exactly
//    0.0138 BNB. Max 30 mints per wallet total.
//  - Paid mints forward the exact price DIRECTLY to the
//    revenue wallet in the same mint() call; overpayment
//    refunded in-tx. No withdraw step for mint revenue.
//  - Token mint, burn, redeem, upgrade mechanics (see below).
//  - Royalty 5% (ERC-2981). mintActive default false.
//
// WHAT IS DIFFERENT FROM THYRK:
//  - Supply 4,443 mintable + 1 Prime (redeem-only) = 4,444
//    total. THYRK: 7,777 + 77 Divine = 7,854.
//  - Tiers: Dormant 2,222 / Awakened 1,333 / Empowered 666 /
//    Ascended 222 / Prime 1. THYRK: Common 4,000 / Rare
//    2,500 / Epic 1,000 / Legendary 277 / Divine 77.
//  - $RUNE amounts are THYRK x2 (because the mint bonus is
//    40, not 20): mint bonus 40; burn Dormant 40 / Awakened
//    100 / Empowered 240 / Ascended 600; redeem Prime 3,000;
//    token mint 200; upgrades +100 / +200 / +400.
//  - $RUNE max supply 444,444 (= 4,444 x 100, same ratio as
//    THYRK's 777,777 = 7,777 x 100).
//  - Owner AND revenue = the same wallet (the user's Binance
//    Agentic Wallet 0x36F3D56eAD5D1D6C2434F94DeFcEF732C5C3CbD2,
//    per his standing rule "Pakai BaW semua"). THYRK splits
//    them (My Wallet owner / Agentic revenue). The two
//    constructor args are kept separate so the split can be
//    reintroduced later without a code change.
//  - NO X-repost system: THYRK's token carries a dormant
//    claimRepost() for a system that does not exist yet, and
//    X actions cannot be verified on-chain. Not copied.
//
// $RUNE — spent and earned here (see RuneToken.sol):
//   Mint (free OR paid): +40 $RUNE per mint.
//   Burn NFT: Dormant 40 / Awakened 100 / Empowered 240 /
//   Ascended 600 $RUNE (a free-minted token burns for its
//   tier reward, same as a paid one; Prime cannot burn).
//   Redeem Prime: 3,000 $RUNE -> 1 Prime (1 max, FCFS).
//   Token mint: 200 $RUNE -> 1 mint, max 3 per wallet.
//   It draws from the full deck, counts toward the wallet's
//   30 max and advances the ladder, but pays no BNB, earns
//   NO 40 $RUNE bonus, and does NOT consume the free mint.
//   Upgrade: 3 Dormant + 100 -> 1 Awakened; 3 Awakened +
//   200 -> 1 Empowered; 3 Empowered + 400 -> 1 Ascended.
//   Inputs are burned, the $RUNE is burned, the output is
//   drawn from the deck (a token of the target tier).
//   Upgrade STOPS at Ascended — Ascended can NEVER be
//   upgraded to Prime. Upgrade outputs do NOT count toward
//   the wallet's 30 cap (the inputs already counted).
//   All $RUNE spent here is BURNED (burnFrom).
//
// THE DECK — hash-only design (cheap deploy), same as THYRK:
//   The full 4,443-entry deck is NEVER stored on-chain.
//   deckHash = keccak256 of the deck encoding (per token,
//   in token-ID order: 1 byte rarity code + 2 bytes design
//   index, big-endian; 4,443 x 3 = 13,329 bytes), built
//   from seed 0x4147454e5452554e45 ("AGENTRUNE" in ASCII hex)
//   by a Fisher-Yates shuffle. The deck, the seed and the
//   deckHash are published off-chain (deck/manifest.json),
//   so anyone can rebuild the deck and verify deckHash.
//   The draw is a lazy Fisher-Yates shuffle seeded by
//   deckHash, executed on-chain one draw at a time over
//   a SINGLE shared pool of all 4,443 tokens.
//   HONEST LIMITS: (1) the draw is deterministic
//   pseudo-randomness from a public seed — it is NOT
//   VRF / provably fair randomness; anyone who knows
//   the seed can compute the draw order in advance.
//   (2) The deck is fixed at deploy (deckHash is
//   immutable) and cannot be reshuffled afterwards.
//   (3) On-chain, only the deckHash commitment plus a
//   compact 2-bit-per-token rarity bitmap are stored.
//
// THE RARITY BITMAP — why it exists:
//   The deck is shuffled, so rarity is NOT a function of
//   the token ID range. The contract still needs to know
//   a token's rarity on-chain, for exactly two things:
//   (a) burn rewards differ per rarity;
//   (b) upgrades must verify the three input NFTs share
//   one tier.
//   The bitmap packs rarity as 2 bits per token
//   (35 uint256 words for 4,443 tokens), is built from
//   the published deck by contracts/scripts/generate-deck.js,
//   and is passed to the constructor.
//
// ESCAPE HATCH (documented, on-chain, visible):
//   agentIdCheckRequired defaults to true. The owner
//   can turn the Agent ID check off
//   (setAgentIdCheckRequired(false)) or point it at
//   a different registry (setAgentIdRegistry).
//
// This contract is SOURCE-VERIFIABLE on BscScan.
// It is NOT an independent audit — keep that
// disclosure on the site.
// ============================================================

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./RuneToken.sol";

contract AgentRune is ERC721, ERC721Royalty, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // ---------- rarity codes (bitmap + rarityOf) ----------
    uint8 public constant RARITY_DORMANT = 0;
    uint8 public constant RARITY_AWAKENED = 1;
    uint8 public constant RARITY_EMPOWERED = 2;
    uint8 public constant RARITY_ASCENDED = 3;
    uint8 public constant RARITY_PRIME = 4;

    // ---------- supply ----------
    uint256 public constant MAX_SUPPLY = 4443;
    uint256 public constant PRIME_SUPPLY = 1;
    uint256 public constant PRIME_TOKEN_ID = 4444; // Prime: ID 4444 only
    uint256 public constant MAX_PER_WALLET = 30;
    uint256 public constant MAX_TOKEN_MINTS = 3;

    // ---------- pricing (locked, no setter exists) ----------
    uint256 public constant PRICE_1_10 = 0.0002 ether;
    uint256 public constant PRICE_11_20 = 0.0004 ether;
    uint256 public constant PRICE_21_30 = 0.0008 ether;

    // ---------- $RUNE amounts (18 decimals, locked) ----------
    uint256 public constant MINT_BONUS = 40 ether;
    uint256 public constant TOKEN_MINT_COST = 200 ether;
    uint256 public constant REDEEM_PRIME_COST = 3000 ether;
    uint256 public constant BURN_DORMANT = 40 ether;
    uint256 public constant BURN_AWAKENED = 100 ether;
    uint256 public constant BURN_EMPOWERED = 240 ether;
    uint256 public constant BURN_ASCENDED = 600 ether;
    uint256 public constant UPGRADE_TO_AWAKENED = 100 ether;
    uint256 public constant UPGRADE_TO_EMPOWERED = 200 ether;
    uint256 public constant UPGRADE_TO_ASCENDED = 400 ether;

    /// @notice Marketplace royalty: 5% = 500 basis points.
    uint96 public constant ROYALTY_BPS = 500;

    /// @notice SPACE ID .ai Agent ID NFT on BNB Smart Chain.
    address public constant DEFAULT_AGENT_ID_REGISTRY =
        0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    bool public mintActive;
    address public immutable revenueWallet;
    address public agentIdRegistry;
    bool public agentIdCheckRequired = true;

    /// @notice keccak256 commitment of the deck, set once via
    /// the constructor argument. The full deck is never stored
    /// on-chain — see THE DECK above.
    bytes32 public immutable deckHash;

    /// @notice The $RUNE token contract. Set once in the
    /// constructor. Mint bonuses and burn rewards are minted
    /// through it; redeem / token-mint / upgrade costs are
    /// burned through it. The token owner must call
    /// setMinter(newNftAddress, true) after deploy.
    RuneToken public immutable runeToken;

    string private _baseTokenURI;

    /// @dev Rarity bitmap: 2 bits per token ID (1..4443),
    /// 35 uint256 words. word (t-1)/128, offset ((t-1)%128)*2.
    uint256[35] private _rarityBitmap;

    /// @dev Undrawn tokens left in the shared Fisher-Yates
    /// pool. Starts at 4443; every deck draw (paid, free,
    /// token-mint, upgrade output) decrements it by exactly 1.
    uint256 private _remaining = MAX_SUPPLY;
    /// @dev Global draw counter: seeds every draw so no two
    /// draws share a seed, even inside one bulk mint.
    uint256 private _drawIndex;
    /// @dev Sparse Fisher-Yates swap map: _swapped[i] =
    /// tokenId now held at pool position i, or 0 = unset
    /// (identity: position i holds tokenId i+1).
    mapping(uint256 => uint256) private _swapped;

    /// @dev Undrawn tokens of each rarity left in the pool.
    uint256 public dormantsRemaining = 2222;
    uint256 public awakenedsRemaining = 1333;
    uint256 public empoweredsRemaining = 666;
    uint256 public ascendedsRemaining = 222;

    /// @dev Free mints given so far (1 per wallet, NO total cap).
    uint256 public freeMinted;
    /// @dev Prime redeemed so far (max 1).
    uint256 public primeMinted;
    /// @dev NFTs burned so far (for totalSupply accounting).
    uint256 public burnedCount;

    /// @dev On-chain mint seed per token.
    mapping(uint256 => bytes32) public tokenSeed;
    /// @dev Mints per wallet — this IS the price ladder
    /// counter and the 30-per-wallet cap. Counts BNB mints +
    /// token mints, NOT upgrades or Prime redeems.
    mapping(address => uint256) public mintCount;
    /// @dev Token mints (200 $RUNE) used per wallet (max 3).
    mapping(address => uint256) public tokenMints;
    /// @dev Whether a wallet already used its 1 automatic
    /// free mint (consumed by the first slot of its first
    /// mint() call). Token-mints do NOT set this.
    mapping(address => bool) public freeUsed;

    event Minted(
        address indexed minter,
        uint256 indexed tokenId,
        uint256 price,
        uint8 rarity,
        bytes32 seed,
        bool viaToken
    );
    event Burned(
        address indexed burner,
        uint256 indexed tokenId,
        uint8 rarity,
        uint256 reward
    );
    event PrimeRedeemed(
        address indexed redeemer,
        uint256 indexed tokenId,
        uint256 cost
    );
    event Upgraded(
        address indexed upgrader,
        uint256 indexed tokenId,
        uint8 rarity,
        uint256 cost
    );
    event DeckCommitted(bytes32 indexed deckHash);
    event MintActiveChanged(bool active);
    event BaseURIUpdated(string baseURI);
    event AgentIdRegistryUpdated(address indexed agentIdRegistry);
    event AgentIdCheckChanged(bool required);
    event Withdrawn(address indexed revenueWallet, uint256 amount);

    error MintInactive();
    error ExceedsMaxSupply();
    error SoldOut();
    error IncorrectPayment(uint256 expected, uint256 received);
    error InvalidAddress();
    error NoFunds();
    error NoAgentId();
    error NoContracts();
    error MaxPerWallet();
    error PaymentForwardFailed();
    error RefundFailed();
    error TokenMintLimit();
    error PrimeExhausted();
    error InvalidUpgrade();
    error BurnPrimeNotAllowed();
    error NotTokenOwner();
    error NoDrawableToken();

    constructor(
        address initialOwner,
        address revenueWallet_,
        address agentIdRegistry_,
        string memory baseURI_,
        bytes32 deckHash_,
        uint256[35] memory rarityBitmap_,
        address runeToken_
    ) ERC721("AgentRune", "ARUNE") Ownable(initialOwner) {
        if (
            initialOwner == address(0) ||
            revenueWallet_ == address(0) ||
            agentIdRegistry_ == address(0) ||
            runeToken_ == address(0)
        ) {
            revert InvalidAddress();
        }

        revenueWallet = revenueWallet_;
        agentIdRegistry = agentIdRegistry_;
        _baseTokenURI = baseURI_;
        deckHash = deckHash_;
        runeToken = RuneToken(runeToken_);
        for (uint256 i = 0; i < 35; i++) {
            _rarityBitmap[i] = rarityBitmap_[i];
        }
        _setDefaultRoyalty(revenueWallet_, ROYALTY_BPS);
        emit DeckCommitted(deckHash_);
    }

    // ---------- supply / pricing / deck (read-only, for UI + agents) ----------

    /// @notice Deck tokens drawn so far (paid + free + token
    /// mints + upgrade outputs). 4443 - deckRemaining().
    function deckDrawn() public view returns (uint256) {
        return MAX_SUPPLY - _remaining;
    }

    /// @notice Undrawn tokens left in the deck pool.
    function deckRemaining() public view returns (uint256) {
        return _remaining;
    }

    /// @notice Current existing NFTs: drawn + Prime - burned.
    function totalSupply() public view returns (uint256) {
        return deckDrawn() + primeMinted - burnedCount;
    }

    /// @notice Prime still redeemable (1 total).
    function primeRemaining() public view returns (uint256) {
        return PRIME_SUPPLY - primeMinted;
    }

    /// @notice Price of a wallet's Nth mint (count = how many
    /// that wallet has ALREADY minted). Slot #1-10 -> 0.0002,
    /// #11-20 -> 0.0004, #21-30 -> 0.0008.
    function priceForCount(uint256 count) public pure returns (uint256) {
        if (count < 10) return PRICE_1_10;
        if (count < 20) return PRICE_11_20;
        return PRICE_21_30;
    }

    /// @notice Price of `wallet`'s next mint. Returns 0 while
    /// the wallet's automatic free mint is still unused.
    /// Otherwise the ladder price for its current mintCount.
    /// Reverts MaxPerWallet once the wallet has minted 30.
    function priceFor(address wallet) public view returns (uint256) {
        uint256 count = mintCount[wallet];
        if (count >= MAX_PER_WALLET) revert MaxPerWallet();
        if (!freeUsed[wallet]) return 0;
        return priceForCount(count);
    }

    /// @notice Price of the CALLER's next mint (0 while the
    /// caller's free mint is unused). Reverts SoldOut when
    /// the deck is empty, MaxPerWallet when the caller has
    /// minted 30 already.
    function currentPrice() public view returns (uint256) {
        if (_remaining == 0) revert SoldOut();
        return priceFor(msg.sender);
    }

    /// @notice Exact BNB for a bulk mint, and which batch
    /// slot the automatic free mint lands on (0-based within
    /// the batch). The free mint is ALWAYS batch slot 0 when
    /// the wallet has not used it yet; freeSlot =
    /// type(uint256).max when the free mint is already used.
    /// A fresh wallet minting 30 pays exactly 0.0138 BNB
    /// (1 free + 9x0.0002 + 10x0.0004 + 10x0.0008).
    function quoteBulk(address wallet, uint256 quantity)
        external
        view
        returns (uint256 totalPrice, uint256 freeSlot)
    {
        return _quoteBulk(wallet, quantity);
    }

    function _quoteBulk(address wallet, uint256 quantity)
        internal
        view
        returns (uint256 totalPrice, uint256 freeSlot)
    {
        if (quantity == 0 || quantity > MAX_PER_WALLET) revert MaxPerWallet();
        uint256 count = mintCount[wallet];
        if (count + quantity > MAX_PER_WALLET) revert MaxPerWallet();
        if (_remaining < quantity) revert SoldOut();
        bool useFree = !freeUsed[wallet];
        freeSlot = useFree ? 0 : type(uint256).max;
        for (uint256 i = 0; i < quantity; i++) {
            if (useFree && i == 0) continue; // free slot costs 0
            totalPrice += priceForCount(count + i);
        }
    }

    /// @notice Rarity of a token ID: 0 Dormant, 1 Awakened,
    /// 2 Empowered, 3 Ascended, 4 Prime. Prime is token ID
    /// 4444. Pure function of the deck bitmap for 1-4443;
    /// works for unminted tokens too.
    function rarityOf(uint256 tokenId) public view returns (uint8) {
        if (tokenId == 0 || tokenId > PRIME_TOKEN_ID) {
            revert ExceedsMaxSupply();
        }
        if (tokenId > MAX_SUPPLY) return RARITY_PRIME;
        uint256 word = _rarityBitmap[(tokenId - 1) / 128];
        uint256 offset = ((tokenId - 1) % 128) * 2;
        return uint8((word >> offset) & 0x3);
    }

    /// @notice True when `wallet` holds at least one SPACE ID
    /// .ai Agent ID NFT in the configured registry. A registry
    /// that does not answer like an ERC-721 returns false
    /// instead of reverting (low-level staticcall on purpose).
    function holdsAgentId(address wallet) public view returns (bool) {
        if (agentIdRegistry == address(0)) return false;
        (bool ok, bytes memory data) = agentIdRegistry.staticcall(
            abi.encodeWithSelector(IERC721.balanceOf.selector, wallet)
        );
        if (!ok || data.length < 32) return false;
        return abi.decode(data, (uint256)) > 0;
    }

    // ---------- the draw (lazy Fisher-Yates, hash-only) ----------

    /// @dev Token ID currently held at pool position `i`
    /// (0-based). Unset map entry = identity (i + 1).
    function _valueAt(uint256 i) internal view returns (uint256) {
        uint256 v = _swapped[i];
        return v == 0 ? i + 1 : v;
    }

    /// @dev Take the token at pool position `pos`: swap it
    /// with the last undrawn position and shrink the pool
    /// by one. Decrements the rarity counter of the taken
    /// token. Caller must guarantee pos < _remaining.
    function _takeAt(uint256 pos) internal returns (uint256 tokenId) {
        tokenId = _valueAt(pos);
        uint256 last = _valueAt(_remaining - 1);
        if (pos != _remaining - 1) {
            _swapped[pos] = last;
        }
        _remaining--;
        uint8 r = rarityOf(tokenId);
        if (r == RARITY_DORMANT) dormantsRemaining--;
        else if (r == RARITY_AWAKENED) awakenedsRemaining--;
        else if (r == RARITY_EMPOWERED) empoweredsRemaining--;
        else ascendedsRemaining--;
    }

    /// @dev Scan the pool from `start` (wrapping) for the
    /// first position whose token has rarity == `want`.
    /// Returns (position, found). Bounded by _remaining
    /// steps, so it always terminates.
    function _findFrom(uint256 start, uint8 want)
        internal
        view
        returns (uint256 pos, bool found)
    {
        uint256 remaining = _remaining;
        for (uint256 k = 0; k < remaining; k++) {
            uint256 p = (start + k) % remaining;
            if (rarityOf(_valueAt(p)) == want) {
                return (p, true);
            }
        }
        return (0, false);
    }

    /// @dev Draw one token from the shared pool — used by
    /// FREE, paid and token mints alike: lazy
    /// Fisher-Yates over the shared pool. No rarity
    /// restriction: any rarity (incl. Ascended) can be
    /// drawn.
    function _drawMain() internal returns (uint256) {
        if (_remaining == 0) revert SoldOut();
        uint256 j = uint256(keccak256(abi.encodePacked(deckHash, _drawIndex))) % _remaining;
        _drawIndex++;
        return _takeAt(j);
    }

    /// @dev Draw one token of a specific tier (for upgrades):
    /// scan the shared pool from a pseudo-random start for
    /// the next token of that tier and take it. Reverts when
    /// none of that tier remains in the pool.
    function _drawTier(uint8 want) internal returns (uint256) {
        if (want == RARITY_DORMANT && dormantsRemaining == 0) revert NoDrawableToken();
        if (want == RARITY_AWAKENED && awakenedsRemaining == 0) revert NoDrawableToken();
        if (want == RARITY_EMPOWERED && empoweredsRemaining == 0) revert NoDrawableToken();
        if (want == RARITY_ASCENDED && ascendedsRemaining == 0) revert NoDrawableToken();
        uint256 start = uint256(
            keccak256(abi.encodePacked(deckHash, _drawIndex, "TIER", want))
        ) % _remaining;
        _drawIndex++;
        (uint256 pos, bool found) = _findFrom(start, want);
        if (!found) revert NoDrawableToken();
        return _takeAt(pos);
    }

    /// @dev Mint one drawn token to `to` with its on-chain
    /// seed, and emit the Minted event. Shared by mint(),
    /// mintWithToken() and upgrade().
    function _mintDrawn(address to, uint256 tokenId, uint256 price, bool viaToken) internal {
        bytes32 seed = keccak256(
            abi.encodePacked(blockhash(block.number - 1), to, tokenId)
        );
        tokenSeed[tokenId] = seed;
        _mint(to, tokenId);
        emit Minted(to, tokenId, price, rarityOf(tokenId), seed, viaToken);
    }

    // ---------- minting ----------

    /// @notice Mint `quantity` AgentRune (1-30) in ONE
    /// transaction. The wallet's FIRST mint() call includes
    /// ONE FREE mint automatically (batch slot 0): no flag,
    /// no choice. Token-mints do NOT consume it.
    /// The free draw can be any rarity, including Ascended.
    /// Every mint in the batch — free AND paid — mints
    /// 40 $RUNE to the minter.
    /// PAYMENT FLOW: paid mints forward the exact batch
    /// price DIRECTLY to the revenue wallet in this same
    /// call. Any overpayment is refunded to the minter in
    /// this same call.
    function mint(uint256 quantity) external payable nonReentrant {
        if (!mintActive) revert MintInactive();
        if (msg.sender.code.length > 0) revert NoContracts();
        if (agentIdCheckRequired && !holdsAgentId(msg.sender)) revert NoAgentId();

        (uint256 totalPrice, uint256 freeSlot) = _quoteBulk(msg.sender, quantity);
        if (msg.value < totalPrice) revert IncorrectPayment(totalPrice, msg.value);

        for (uint256 i = 0; i < quantity; i++) {
            bool isFree = (i == freeSlot);
            uint256 tokenId = _drawMain();
            mintCount[msg.sender]++;
            if (isFree) {
                freeUsed[msg.sender] = true;
                freeMinted++;
            }
            runeToken.mint(msg.sender, MINT_BONUS);
            _mintDrawn(msg.sender, tokenId, isFree ? 0 : priceForCount(mintCount[msg.sender] - 1), false);
        }

        if (totalPrice > 0) {
            (bool ok, ) = revenueWallet.call{value: totalPrice}("");
            if (!ok) revert PaymentForwardFailed();
        }
        uint256 excess = msg.value - totalPrice;
        if (excess > 0) {
            (bool rok, ) = msg.sender.call{value: excess}("");
            if (!rok) revert RefundFailed();
        }
    }

    /// @notice Mint `quantity` AgentRune (1-3) with $RUNE
    /// instead of BNB: 200 $RUNE per mint. Max 3 per
    /// wallet, ever. These mints draw from the full deck,
    /// count toward the wallet's 30 max and advance the
    /// ladder number, but pay no BNB, earn no 40 $RUNE
    /// bonus, and do NOT consume the wallet's free mint.
    /// The caller must approve this contract to spend
    /// their $RUNE first. Agent ID is required, like any
    /// mint. No BNB may be sent with this call.
    function mintWithToken(uint256 quantity) external payable nonReentrant {
        if (!mintActive) revert MintInactive();
        if (msg.sender.code.length > 0) revert NoContracts();
        if (agentIdCheckRequired && !holdsAgentId(msg.sender)) revert NoAgentId();
        if (msg.value != 0) revert IncorrectPayment(0, msg.value);
        if (quantity == 0 || quantity > MAX_TOKEN_MINTS) revert TokenMintLimit();
        if (tokenMints[msg.sender] + quantity > MAX_TOKEN_MINTS) revert TokenMintLimit();
        if (mintCount[msg.sender] + quantity > MAX_PER_WALLET) revert MaxPerWallet();
        if (_remaining < quantity) revert SoldOut();

        runeToken.burnFrom(msg.sender, TOKEN_MINT_COST * quantity);
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _drawMain();
            mintCount[msg.sender]++;
            tokenMints[msg.sender]++;
            _mintDrawn(msg.sender, tokenId, 0, true);
        }
    }

    // ---------- $RUNE features ----------

    /// @notice Burn one NFT the caller owns for $RUNE:
    /// Dormant 40 / Awakened 100 / Empowered 240 /
    /// Ascended 600. A free-minted token burns for its tier
    /// reward, same as a paid one. Burning is permanent —
    /// the NFT is gone forever and does NOT return to the
    /// deck. Prime cannot be burned.
    function burn(uint256 tokenId) external nonReentrant {
        if (_ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        uint8 r = rarityOf(tokenId);
        if (r == RARITY_PRIME) revert BurnPrimeNotAllowed();
        uint256 reward = r == RARITY_DORMANT
            ? BURN_DORMANT
            : r == RARITY_AWAKENED
                ? BURN_AWAKENED
                : r == RARITY_EMPOWERED
                    ? BURN_EMPOWERED
                    : BURN_ASCENDED;
        _burn(tokenId);
        burnedCount++;
        runeToken.mint(msg.sender, reward);
        emit Burned(msg.sender, tokenId, r, reward);
    }

    /// @notice Redeem 1 Prime NFT for 3,000 $RUNE. Prime is
    /// never mintable for BNB. 1 total, first-come
    /// first-served. The 3,000 $RUNE is burned. Prime is
    /// token ID 4444.
    function redeemPrime() external nonReentrant {
        if (primeMinted >= PRIME_SUPPLY) revert PrimeExhausted();
        runeToken.burnFrom(msg.sender, REDEEM_PRIME_COST);
        primeMinted++;
        _mintDrawn(msg.sender, PRIME_TOKEN_ID, 0, false);
        emit PrimeRedeemed(msg.sender, PRIME_TOKEN_ID, REDEEM_PRIME_COST);
    }

    /// @notice Upgrade 3 NFTs of one tier into 1 NFT of the
    /// next tier: 3 Dormant + 100 $RUNE -> 1 Awakened;
    /// 3 Awakened + 200 $RUNE -> 1 Empowered; 3 Empowered +
    /// 400 $RUNE -> 1 Ascended. The 3 input NFTs are burned
    /// and the $RUNE is burned. The output is drawn from the
    /// deck (a token of the target tier). Upgrade STOPS at
    /// Ascended — Ascended can NEVER be upgraded to Prime.
    /// Upgrade outputs do not count toward the wallet's 30
    /// mint cap (the inputs already counted).
    function upgrade(uint256 tokenId1, uint256 tokenId2, uint256 tokenId3)
        external
        nonReentrant
    {
        if (
            _ownerOf(tokenId1) != msg.sender ||
            _ownerOf(tokenId2) != msg.sender ||
            _ownerOf(tokenId3) != msg.sender
        ) revert NotTokenOwner();
        uint8 r = rarityOf(tokenId1);
        if (
            r != rarityOf(tokenId2) ||
            r != rarityOf(tokenId3) ||
            r > RARITY_EMPOWERED
        ) revert InvalidUpgrade();
        uint256 cost = r == RARITY_DORMANT
            ? UPGRADE_TO_AWAKENED
            : r == RARITY_AWAKENED
                ? UPGRADE_TO_EMPOWERED
                : UPGRADE_TO_ASCENDED;
        runeToken.burnFrom(msg.sender, cost);
        _burn(tokenId1);
        _burn(tokenId2);
        _burn(tokenId3);
        burnedCount += 3;
        uint256 tokenId = _drawTier(r + 1);
        _mintDrawn(msg.sender, tokenId, 0, false);
        emit Upgraded(msg.sender, tokenId, r + 1, cost);
    }

    // ---------- metadata ----------

    function baseURI() public view returns (string memory) {
        return _baseTokenURI;
    }

    /// @notice tokenURI = baseURI + tokenId + ".json" for
    /// deck tokens (1-4443), and baseURI + "prime.json"
    /// for Prime (4444). The base URI must end with "/".
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert ERC721NonexistentToken(tokenId);
        if (tokenId > MAX_SUPPLY) {
            return string.concat(_baseTokenURI, "prime.json");
        }
        return string.concat(_baseTokenURI, tokenId.toString(), ".json");
    }

    // ---------- owner-only administration ----------

    function setMintActive(bool active) external onlyOwner {
        mintActive = active;
        emit MintActiveChanged(active);
    }

    function setBaseURI(string calldata baseURI_) external onlyOwner {
        _baseTokenURI = baseURI_;
        emit BaseURIUpdated(baseURI_);
    }

    /// @notice Point the Agent ID check at a different registry.
    function setAgentIdRegistry(address agentIdRegistry_) external onlyOwner {
        if (agentIdRegistry_ == address(0)) revert InvalidAddress();
        agentIdRegistry = agentIdRegistry_;
        emit AgentIdRegistryUpdated(agentIdRegistry_);
    }

    /// @notice Turn the on-chain Agent ID check on/off.
    /// Turning it OFF makes minting permissionless on-chain and
    /// agent-only in the UI only. The change is public
    /// on-chain via this event — do not hide it.
    function setAgentIdCheckRequired(bool required) external onlyOwner {
        agentIdCheckRequired = required;
        emit AgentIdCheckChanged(required);
    }

    /// @notice Safety valve only: send any balance that
    /// arrived OUTSIDE mint() (e.g. force-sent BNB) to the
    /// revenue wallet. Owner-only. Mint payments are
    /// forwarded directly by mint() and never accumulate
    /// here, so in normal operation this reverts NoFunds.
    function withdraw() external onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        if (amount == 0) revert NoFunds();
        (bool ok, ) = revenueWallet.call{value: amount}("");
        if (!ok) revert("Withdraw failed");
        emit Withdrawn(revenueWallet, amount);
    }

    /// @notice ERC-721 + ERC-2981 interface support.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Royalty)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
