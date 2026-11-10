const { expect } = require("chai");
const { ethers } = require("hardhat");
const manifest = require("../../deck/manifest.json");

const BASE_URI = "https://agentrune.vercel.app/metadata/";
const DECK_HASH = manifest.deckHash;
const BITMAP = manifest.rarityBitmap;

describe("AgentRune (THYRK-style deck-draw)", function () {
  let owner, alice, bob, carol, dave;
  let registry, rune, nft, market;
  let aliceTokens = []; // tokenIds minted by alice (bulk 30)
  let bobTokenId = null; // a token bob minted, later sold to carol

  async function mint30(wallet) {
    const tx = await nft.connect(wallet).mint(30, { value: ethers.parseEther("0.0138") });
    const rc = await tx.wait();
    const ids = [];
    for (const log of rc.logs) {
      try {
        const parsed = nft.interface.parseLog(log);
        if (parsed && parsed.name === "Minted") ids.push(Number(parsed.args.tokenId));
      } catch (e) { /* not our event */ }
    }
    return ids;
  }

  before(async function () {
    [owner, alice, bob, carol, dave] = await ethers.getSigners();

    const Registry = await ethers.getContractFactory("MockAgentIdRegistry");
    registry = await Registry.deploy();
    await registry.mintBatch([alice.address, bob.address, carol.address, dave.address]);

    const Rune = await ethers.getContractFactory("RuneToken");
    rune = await Rune.deploy(owner.address);

    const Nft = await ethers.getContractFactory("AgentRune");
    nft = await Nft.deploy(
      owner.address,
      owner.address, // revenue = owner (BAW rule: BAW for everything)
      await registry.getAddress(),
      BASE_URI,
      DECK_HASH,
      BITMAP,
      await rune.getAddress()
    );

    await rune.setMinter(await nft.getAddress(), true);

    const Market = await ethers.getContractFactory("AgentRuneMarketplace");
    market = await Market.deploy(await nft.getAddress());

    await nft.setMintActive(true);
  });

  it("deploy: name/symbol/supply/deckHash/bitmap match the manifest", async function () {
    expect(await nft.name()).to.equal("AgentRune");
    expect(await nft.symbol()).to.equal("ARUNE");
    expect(await nft.MAX_SUPPLY()).to.equal(4443);
    expect(await nft.PRIME_TOKEN_ID()).to.equal(4444);
    expect(await nft.deckHash()).to.equal(DECK_HASH);
    expect(await nft.deckRemaining()).to.equal(4443);
    expect(await nft.dormantsRemaining()).to.equal(2222);
    expect(await nft.awakenedsRemaining()).to.equal(1333);
    expect(await nft.empoweredsRemaining()).to.equal(666);
    expect(await nft.ascendedsRemaining()).to.equal(222);
    expect(await nft.primeRemaining()).to.equal(1);
    expect(await rune.MAX_SUPPLY()).to.equal(ethers.parseEther("444444"));
    expect(await rune.name()).to.equal("Rune");
    expect(await rune.symbol()).to.equal("RUNE");
    // bitmap spot-check: rarityOf matches the manifest deck
    for (const t of [1, 2, 3, 50, 100, 500, 1000, 2222, 3333, 4443]) {
      const want = ["Dormant", "Awakened", "Empowered", "Ascended"].indexOf(
        manifest.tokens[t - 1].rarity
      );
      expect(await nft.rarityOf(t)).to.equal(want, `rarityOf(${t})`);
    }
    expect(await nft.rarityOf(4444)).to.equal(4); // Prime
  });

  it("pricing: ladder + quoteBulk(30) = 0.0138 BNB, freeSlot 0", async function () {
    expect(await nft.priceForCount(0)).to.equal(ethers.parseEther("0.0002"));
    expect(await nft.priceForCount(9)).to.equal(ethers.parseEther("0.0002"));
    expect(await nft.priceForCount(10)).to.equal(ethers.parseEther("0.0004"));
    expect(await nft.priceForCount(19)).to.equal(ethers.parseEther("0.0004"));
    expect(await nft.priceForCount(20)).to.equal(ethers.parseEther("0.0008"));
    expect(await nft.priceForCount(29)).to.equal(ethers.parseEther("0.0008"));
    expect(await nft.priceFor(alice.address)).to.equal(0); // free mint unused
    const [price, freeSlot] = await nft.quoteBulk(alice.address, 30);
    expect(price).to.equal(ethers.parseEther("0.0138"));
    expect(freeSlot).to.equal(0);
    const [p1, fs1] = await nft.quoteBulk(alice.address, 1);
    expect(p1).to.equal(0);
    expect(fs1).to.equal(0);
  });

  it("mint rejects: no Agent ID, contract caller, bad quantity", async function () {
    const [, , , , , noId] = await ethers.getSigners();
    await expect(nft.connect(noId).mint(1)).to.be.revertedWithCustomError(nft, "NoAgentId");
    const Caller = await ethers.getContractFactory("MockGenericCaller");
    const caller = await Caller.deploy();
    await registry.mintTo(await caller.getAddress()); // give the CALLER an Agent ID
    const data = nft.interface.encodeFunctionData("mint", [1]);
    await expect(
      caller.tryCallRevert(await nft.getAddress(), data, { value: ethers.parseEther("0.0002") })
    ).to.be.revertedWithCustomError(nft, "NoContracts");
    await expect(nft.connect(alice).mint(0)).to.be.revertedWithCustomError(nft, "MaxPerWallet");
    await expect(nft.connect(alice).mint(31)).to.be.revertedWithCustomError(nft, "MaxPerWallet");
  });

  it("free mint: first mint(1) costs 0, earns 40 $RUNE; underpayment reverts after free is used", async function () {
    await nft.connect(bob).mint(1, { value: 0 });
    expect(await nft.freeUsed(bob.address)).to.equal(true);
    expect(await nft.freeMinted()).to.equal(1);
    expect(await nft.mintCount(bob.address)).to.equal(1);
    expect(await rune.balanceOf(bob.address)).to.equal(ethers.parseEther("40"));
    expect(await nft.priceFor(bob.address)).to.equal(ethers.parseEther("0.0002"));
    expect(await nft.deckRemaining()).to.equal(4442);
    await expect(nft.connect(bob).mint(1, { value: 1 }))
      .to.be.revertedWithCustomError(nft, "IncorrectPayment");
  });

  it("bulk 30: fresh wallet pays exactly 0.0138, earns 1200 $RUNE, revenue forwarded", async function () {
    const revBefore = await ethers.provider.getBalance(owner.address);
    aliceTokens = await mint30(alice);
    expect(aliceTokens.length).to.equal(30);
    expect(new Set(aliceTokens).size).to.equal(30); // unique draws
    expect(await nft.mintCount(alice.address)).to.equal(30);
    expect(await nft.freeUsed(alice.address)).to.equal(true);
    expect(await rune.balanceOf(alice.address)).to.equal(ethers.parseEther("1200"));
    const revAfter = await ethers.provider.getBalance(owner.address);
    expect(revAfter - revBefore).to.equal(ethers.parseEther("0.0138"));
    expect(await nft.deckRemaining()).to.equal(4443 - 1 - 30);
    expect(await nft.totalSupply()).to.equal(31);
    // 30-cap enforced
    await expect(nft.connect(alice).mint(1, { value: ethers.parseEther("0.0002") }))
      .to.be.revertedWithCustomError(nft, "MaxPerWallet");
    // overpayment refunded
    await expect(nft.connect(bob).mint(1, { value: ethers.parseEther("0.001") }))
      .to.changeEtherBalance(bob, -ethers.parseEther("0.0002"));
  });

  it("mintWithToken: 200 $RUNE per mint, max 3, does not consume free mint", async function () {
    // carol: 1 free + 14 paid = 600 $RUNE (9 x 0.0002 + 5 x 0.0004 = 0.0038 BNB)
    await nft.connect(carol).mint(1, { value: 0 });
    await nft.connect(carol).mint(14, { value: ethers.parseEther("0.0038") });
    expect(await rune.balanceOf(carol.address)).to.equal(ethers.parseEther("600"));
    await rune.connect(carol).approve(await nft.getAddress(), ethers.parseEther("1000"));
    const before = await rune.balanceOf(carol.address);
    await nft.connect(carol).mintWithToken(1);
    expect(await nft.tokenMints(carol.address)).to.equal(1);
    expect(await nft.mintCount(carol.address)).to.equal(16);
    expect(await rune.balanceOf(carol.address)).to.equal(before - ethers.parseEther("200"));
    await nft.connect(carol).mintWithToken(2);
    expect(await nft.tokenMints(carol.address)).to.equal(3);
    expect(await nft.mintCount(carol.address)).to.equal(18);
    expect(await rune.balanceOf(carol.address)).to.equal(0);
    await expect(nft.connect(carol).mintWithToken(1)).to.be.revertedWithCustomError(nft, "TokenMintLimit");
    await expect(nft.connect(carol).mintWithToken(1, { value: 1 })).to.be.revertedWithCustomError(nft, "IncorrectPayment");
    // dave: token-mints do NOT consume the free mint (RUNE gifted by alice)
    await rune.connect(alice).transfer(dave.address, ethers.parseEther("600"));
    await rune.connect(dave).approve(await nft.getAddress(), ethers.parseEther("600"));
    await nft.connect(dave).mintWithToken(3);
    expect(await nft.tokenMints(dave.address)).to.equal(3);
    expect(await nft.freeUsed(dave.address)).to.equal(false);
    await nft.connect(dave).mint(1, { value: 0 }); // free mint still available
    expect(await nft.freeUsed(dave.address)).to.equal(true);
    expect(await rune.balanceOf(dave.address)).to.equal(ethers.parseEther("40"));
  });

  it("burn: Dormant burns for 40 $RUNE; burned token is gone", async function () {
    // find a Dormant among alice's 30
    let dormant = null;
    for (const id of aliceTokens) {
      if (Number(await nft.rarityOf(id)) === 0) { dormant = id; break; }
    }
    expect(dormant).to.not.equal(null);
    const balBefore = await rune.balanceOf(alice.address);
    const burnedBefore = await nft.burnedCount();
    await nft.connect(alice).burn(dormant);
    expect(await rune.balanceOf(alice.address)).to.equal(balBefore + ethers.parseEther("40"));
    expect(await nft.burnedCount()).to.equal(burnedBefore + 1n);
    await expect(nft.ownerOf(dormant)).to.be.revertedWithCustomError(nft, "ERC721NonexistentToken");
    aliceTokens = aliceTokens.filter((id) => id !== dormant);
  });

  it("upgrade: 3 Dormant + 100 $RUNE -> 1 Awakened; mixed tiers revert", async function () {
    const dormantIds = [];
    for (const id of aliceTokens) {
      if (Number(await nft.rarityOf(id)) === 0) dormantIds.push(id);
      if (dormantIds.length === 3) break;
    }
    expect(dormantIds.length).to.equal(3);
    // mixed tiers revert
    const other = aliceTokens.find((id) => !dormantIds.includes(id));
    await expect(nft.connect(alice).upgrade(dormantIds[0], dormantIds[1], other))
      .to.be.revertedWithCustomError(nft, "InvalidUpgrade");
    const balBefore = await rune.balanceOf(alice.address);
    await rune.connect(alice).approve(await nft.getAddress(), ethers.parseEther("100"));
    const tx = await nft.connect(alice).upgrade(dormantIds[0], dormantIds[1], dormantIds[2]);
    const rc = await tx.wait();
    let outId = null;
    for (const log of rc.logs) {
      try {
        const parsed = nft.interface.parseLog(log);
        if (parsed && parsed.name === "Upgraded") outId = Number(parsed.args.tokenId);
      } catch (e) { /* ignore */ }
    }
    expect(outId).to.not.equal(null);
    expect(await nft.rarityOf(outId)).to.equal(1); // Awakened
    expect(await nft.ownerOf(outId)).to.equal(alice.address);
    expect(await rune.balanceOf(alice.address)).to.equal(balBefore - ethers.parseEther("100"));
    expect(await nft.mintCount(alice.address)).to.equal(30); // upgrade does not count
    aliceTokens = aliceTokens.filter((id) => !dormantIds.includes(id));
    aliceTokens.push(outId);
  });

  it("redeem Prime: 3000 $RUNE -> token 4444; second redeem reverts", async function () {
    // burn alice's remaining tokens until she can afford 3000
    for (const id of [...aliceTokens]) {
      if ((await rune.balanceOf(alice.address)) >= ethers.parseEther("3000")) break;
      await nft.connect(alice).burn(id);
      aliceTokens = aliceTokens.filter((x) => x !== id);
    }
    expect(await rune.balanceOf(alice.address)).to.be.gte(ethers.parseEther("3000"));
    await rune.connect(alice).approve(await nft.getAddress(), ethers.parseEther("3000"));
    const balBefore = await rune.balanceOf(alice.address);
    await nft.connect(alice).redeemPrime();
    expect(await rune.balanceOf(alice.address)).to.equal(balBefore - ethers.parseEther("3000"));
    expect(await nft.primeMinted()).to.equal(1);
    expect(await nft.primeRemaining()).to.equal(0);
    expect(await nft.ownerOf(4444)).to.equal(alice.address);
    expect(await nft.rarityOf(4444)).to.equal(4);
    expect(await nft.tokenURI(4444)).to.equal(BASE_URI + "prime.json");
    await expect(nft.connect(alice).redeemPrime()).to.be.revertedWithCustomError(nft, "PrimeExhausted");
    await expect(nft.connect(alice).burn(4444)).to.be.revertedWithCustomError(nft, "BurnPrimeNotAllowed");
  });

  it("marketplace: list / buy (5% royalty) / cancel / updatePrice", async function () {
    // bob lists one of his tokens (find it by scanning ownerOf)
    expect(await nft.balanceOf(bob.address)).to.be.gte(1);
    for (let id = 1; id <= 4443 && bobTokenId === null; id++) {
      try { if ((await nft.ownerOf(id)) === bob.address) bobTokenId = id; } catch (e) { /* unminted */ }
    }
    expect(bobTokenId).to.not.equal(null);
    await nft.connect(bob).setApprovalForAll(await market.getAddress(), true);
    await market.connect(bob).list(bobTokenId, ethers.parseEther("0.01"));
    expect(await market.getListedIds()).to.deep.equal([BigInt(bobTokenId)]);
    const [seller, price, active] = await market.getListing(bobTokenId);
    expect(seller).to.equal(bob.address);
    expect(price).to.equal(ethers.parseEther("0.01"));
    expect(active).to.equal(true);
    // buy: 5% royalty to owner, 95% to seller
    const revBefore = await ethers.provider.getBalance(owner.address);
    const bobBefore = await ethers.provider.getBalance(bob.address);
    await market.connect(carol).buy(bobTokenId, { value: ethers.parseEther("0.01") });
    expect(await nft.ownerOf(bobTokenId)).to.equal(carol.address);
    expect((await ethers.provider.getBalance(owner.address)) - revBefore).to.equal(ethers.parseEther("0.0005"));
    expect((await ethers.provider.getBalance(bob.address)) - bobBefore).to.equal(ethers.parseEther("0.0095"));
    expect(await market.getListedIds()).to.deep.equal([]);
    // cancel + updatePrice (carol must approve the marketplace first)
    await nft.connect(carol).setApprovalForAll(await market.getAddress(), true);
    await market.connect(carol).list(bobTokenId, ethers.parseEther("0.02"));
    await market.connect(carol).updatePrice(bobTokenId, ethers.parseEther("0.03"));
    expect((await market.getListing(bobTokenId))[1]).to.equal(ethers.parseEther("0.03"));
    await market.connect(carol).cancel(bobTokenId);
    expect(await nft.ownerOf(bobTokenId)).to.equal(carol.address);
    await expect(market.connect(carol).buy(bobTokenId, { value: ethers.parseEther("0.03") }))
      .to.be.revertedWith("not listed");
  });

  it("admin + views: royalty 5%, tokenURI format, withdraw safety valve", async function () {
    const [receiver, amount] = await nft.royaltyInfo(1, ethers.parseEther("1"));
    expect(receiver).to.equal(owner.address);
    expect(amount).to.equal(ethers.parseEther("0.05"));
    expect(await nft.supportsInterface("0x80ac58cd")).to.equal(true); // ERC721
    expect(await nft.supportsInterface("0x2a55205a")).to.equal(true); // ERC2981
    expect(await nft.tokenURI(bobTokenId)).to.equal(BASE_URI + bobTokenId + ".json");
    // force-send BNB (constructor selfdestruct works on Cancun) then withdraw
    const ForceCtor = await ethers.getContractFactory("MockForceSendCtor");
    await ForceCtor.deploy(await nft.getAddress(), { value: ethers.parseEther("0.5") });
    const revBefore = await ethers.provider.getBalance(owner.address);
    const tx = await nft.withdraw();
    const rc = await tx.wait();
    const gas = rc.gasUsed * rc.gasPrice;
    expect((await ethers.provider.getBalance(owner.address)) - revBefore + gas)
      .to.equal(ethers.parseEther("0.5"));
    await expect(nft.withdraw()).to.be.revertedWithCustomError(nft, "NoFunds");
    // agent-id check escape hatch
    await nft.setAgentIdCheckRequired(false);
    const [, , , , , noId] = await ethers.getSigners();
    await nft.connect(noId).mint(1, { value: 0 });
    await nft.setAgentIdCheckRequired(true);
    await expect(nft.connect(noId).mint(1, { value: 0 })).to.be.revertedWithCustomError(nft, "NoAgentId");
  });
});
