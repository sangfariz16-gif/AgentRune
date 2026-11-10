# AgentRune

Rune-stone NFT collection on BNB Smart Chain (BEP-721), modelled on THYRK's
deck-draw structure. 4,444 supply, agent-only mint, $RUNE utility token.

## Spec

- **Supply:** 4,444 — 4,443 deck tokens + 1 Prime (ID 4444, redeem-only)
- **Tiers:** Dormant 2,222 / Awakened 1,333 / Empowered 666 / Ascended 222 / Prime 1
- **Price:** mint #1 FREE (Agent ID, full deck), #2–10 @ 0.0002 BNB,
  #11–20 @ 0.0004 BNB, #21–30 @ 0.0008 BNB; max 30/wallet (bulk 30 = 0.0138 BNB)
- **Mint:** agent-only — SPACE ID `.ai` Agent ID checked on-chain
  (registry `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`); contracts rejected
- **Token:** $RUNE, 40 per mint (free AND paid), max supply 444,444
- **Burn:** Dormant 40 / Awakened 100 / Empowered 240 / Ascended 600 $RUNE
- **Redeem Prime:** 3,000 $RUNE → 1 Prime (1 max, first-come first-served)
- **Token mint:** 200 $RUNE → 1 mint, max 3/wallet (does not consume the free mint)
- **Upgrade:** 3 Dormant + 100 → Awakened; 3 Awakened + 200 → Empowered;
  3 Empowered + 400 → Ascended (stops at Ascended)
- **Royalty:** 5% (ERC-2981) · **Marketplace:** own escrow, 0% fee
- **Language:** Japanese primary + English toggle · **X:** not yet

## Deck

The 4,443-token deck is a deterministic Fisher-Yates shuffle seeded by
`AGENTRUNE` (`0x4147454e5452554e45`). Only the `deckHash` commitment and a
35-word rarity bitmap live on-chain; the full deck is published here so
anyone can rebuild and verify it.

- `deck/manifest.json` — full deck (tokenId → rarity, design), deckHash, bitmap
- `deck/deckHash.txt` — `0x48ba2ea5d13d124e7b87aca5955a2d00ecd60adb879dc63f9b0d26c1712f1e76`
- `deck/bitmap.json` — 35-word rarity bitmap
- Regenerate: `node contracts/scripts/generate-deck.js`

## Contracts

- `contracts/contracts/AgentRune.sol` — the NFT (deck-draw, ladder, burn/redeem/upgrade)
- `contracts/contracts/RuneToken.sol` — $RUNE (ERC-20, capped, minter-gated)
- `contracts/contracts/AgentRuneMarketplace.sol` — fixed-price escrow, 0% fee
- `contracts/test/agentrune.test.js` — Hardhat tests, **11/11 passing**

```sh
cd contracts
npm install   # @openzeppelin/contracts, hardhat toolbox
npx hardhat test
```

Deploy order: RuneToken → AgentRune → Marketplace → `setMinter(nft, true)` →
`setMintActive(true)`. Owner + revenue wallet: the deployer wallet.

## Status

Contracts written and tested. **Not deployed yet.** Site preview is a separate
build; artwork (16 rune stones) lives in `assets/` (added with the site).
