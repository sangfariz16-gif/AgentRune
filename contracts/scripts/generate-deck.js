// Generate the AgentRune deck (THYRK-style, hash-only design).
//
// Deck = 4,443 mintable tokens (Dormant 2,222 / Awakened 1,333 /
// Empowered 666 / Ascended 222). Prime (token ID 4,444) is NOT in
// the deck — it is redeem-only for 3,000 $RUNE, exactly like
// THYRK's Divine (77) sits outside its 7,777 deck. Total supply
// 4,444 = 4,443 deck + 1 Prime.
//
// Method (mirrors THYRK's documented design):
//   - Build the ordered multiset of (rarity, design) pairs.
//   - Fisher-Yates shuffle with a deterministic keccak PRNG
//     seeded by the ASCII seed "AGENTRUNE" (0x4147454e5452554e45).
//   - The shuffled list IS the deck: deck[i] is token ID i+1.
//   - deckHash = keccak256(deck encoding), per token in token-ID
//     order: 1 byte rarity code + 2 bytes design index (BE).
//     4,443 x 3 = 13,329 bytes.
//   - Rarity bitmap: 2 bits per token ID (1..4,443), 35 uint256
//     words. word (t-1)/128, offset ((t-1)%128)*2.
// Anyone can rebuild deck + deckHash + bitmap from the seed and
// this script and verify they match the on-chain commitment.
//
// Design indices (global, 0-15):
//   Dormant   (0): 0 Ember, 1 Frost, 2 Verdant, 3 Void
//   Awakened  (1): 4 Solar, 5 Storm, 6 Terra, 7 Arcane
//   Empowered (2): 8 Gale, 9 Astral, 10 Chrono, 11 Rust
//   Ascended  (3): 12 Tide, 13 Blood, 14 Hero (circuit)
//   Prime     (4): 15 Limited (obsidian gold) — NOT in the deck.

const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const SEED_ASCII = "AGENTRUNE";
const SEED = ethers.toUtf8Bytes(SEED_ASCII);

const RARITY = { DORMANT: 0, AWAKENED: 1, EMPOWERED: 2, ASCENDED: 3, PRIME: 4 };
const RARITY_NAMES = ["Dormant", "Awakened", "Empowered", "Ascended", "Prime"];

const TIERS = [
  { rarity: RARITY.DORMANT, count: 2222, designs: ["ember", "frost", "verdant", "void"] },
  { rarity: RARITY.AWAKENED, count: 1333, designs: ["solar", "storm", "terra", "arcane"] },
  { rarity: RARITY.EMPOWERED, count: 666, designs: ["gale", "astral", "chrono", "rust"] },
  { rarity: RARITY.ASCENDED, count: 222, designs: ["tide", "blood", "hero"] },
];
const DESIGN_INDEX = {};
TIERS.forEach((t) => t.designs.forEach((d, i) => {
  DESIGN_INDEX[d] = TIERS.slice(0, TIERS.indexOf(t)).reduce((a, x) => a + x.designs.length, 0) + i;
}));
const DESIGN_FILES = {};
Object.keys(DESIGN_INDEX).forEach((d) => { DESIGN_FILES[d] = `${d}.webp`; });
DESIGN_FILES.limited = "limited.webp";

// Deterministic PRNG: keccak256(seed || counter32) mod n.
let counter = 0;
function randBelow(n) {
  const h = ethers.keccak256(ethers.concat([SEED, ethers.toBeHex(counter, 32)]));
  counter++;
  return Number(BigInt(h) % BigInt(n));
}

function main() {
  // 1. Ordered multiset, designs round-robin within each tier.
  const deck = [];
  for (const tier of TIERS) {
    for (let i = 0; i < tier.count; i++) {
      const design = tier.designs[i % tier.designs.length];
      deck.push({ rarity: tier.rarity, design, designIndex: DESIGN_INDEX[design] });
    }
  }
  console.log("deck size:", deck.length);

  // 2. Fisher-Yates shuffle (deterministic).
  for (let i = deck.length - 1; i > 0; i--) {
    const j = randBelow(i + 1);
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }

  // 3. Encode + deckHash.
  const encoded = Buffer.alloc(deck.length * 3);
  deck.forEach((e, idx) => {
    encoded[idx * 3] = e.rarity;
    encoded.writeUInt16BE(e.designIndex, idx * 3 + 1);
  });
  const deckHash = ethers.keccak256(encoded);
  console.log("deckHash:", deckHash);

  // 4. Rarity bitmap (35 words).
  const WORDS = 35;
  const bitmap = new Array(WORDS).fill(0n);
  deck.forEach((e, idx) => {
    const t = idx + 1;
    const word = Math.floor((t - 1) / 128);
    const offset = BigInt(((t - 1) % 128) * 2);
    bitmap[word] |= BigInt(e.rarity) << offset;
  });
  const bitmapHex = bitmap.map((w) => "0x" + w.toString(16).padStart(64, "0"));

  // 5. Verify round-trip: bitmap decodes to the deck rarities.
  for (let t = 1; t <= deck.length; t++) {
    const word = Math.floor((t - 1) / 128);
    const offset = BigInt(((t - 1) % 128) * 2);
    const r = Number((bitmap[word] >> offset) & 0x3n);
    if (r !== deck[t - 1].rarity) throw new Error(`bitmap mismatch at token ${t}`);
  }
  // Verify counts.
  const counts = [0, 0, 0, 0, 0];
  deck.forEach((e) => counts[e.rarity]++);
  console.log("rarity counts:", counts.map((c, i) => `${RARITY_NAMES[i]} ${c}`).join(" / "));
  if (counts[0] !== 2222 || counts[1] !== 1333 || counts[2] !== 666 || counts[3] !== 222) {
    throw new Error("rarity counts do not match spec");
  }
  // Verify deckHash recomputation.
  if (ethers.keccak256(encoded) !== deckHash) throw new Error("deckHash mismatch");

  // 6. Write outputs.
  const outDir = path.join(__dirname, "..", "..", "deck");
  fs.mkdirSync(outDir, { recursive: true });
  const manifest = {
    project: "AgentRune",
    seedAscii: SEED_ASCII,
    seedHex: ethers.hexlify(SEED),
    deckSize: deck.length,
    prime: { tokenId: 4444, rarity: "Prime", design: "limited", designIndex: 15, redeemCostRune: "3000" },
    totalSupply: 4444,
    deckHash,
    rarityBitmapWords: WORDS,
    rarityBitmap: bitmapHex,
    tiers: TIERS.map((t) => ({
      rarity: RARITY_NAMES[t.rarity], count: t.count,
      designs: t.designs.map((d) => ({ name: d, designIndex: DESIGN_INDEX[d], file: DESIGN_FILES[d] })),
    })),
    // tokenId (1-based) -> { rarity, design, designIndex }
    tokens: deck.map((e, idx) => ({
      tokenId: idx + 1,
      rarity: RARITY_NAMES[e.rarity],
      design: e.design,
      designIndex: e.designIndex,
      file: DESIGN_FILES[e.design],
    })),
  };
  fs.writeFileSync(path.join(outDir, "manifest.json"), JSON.stringify(manifest, null, 2));
  fs.writeFileSync(path.join(outDir, "deckHash.txt"), deckHash + "\n");
  fs.writeFileSync(path.join(outDir, "bitmap.json"), JSON.stringify(bitmapHex, null, 2));
  console.log("wrote", path.join(outDir, "manifest.json"));
  console.log("bitmap words:", WORDS);
}

main();
