const { expect } = require("chai");
const { waffle, ethers } = require("hardhat");
const { loadFixture } = waffle;
const provider = waffle.provider;
const { isCallTrace } = require("hardhat/internal/hardhat-network/stack-traces/message-trace");

function nice(thing) {
  let name = Object.keys(thing)[0];
  let val = thing[name];
  console.log(`${name}: ${ethers.utils.formatEther(val)} (${val})`);
}

async function fixture(provider) {
  const Parent = await ethers.getContractFactory("contracts/TideParent.sol:TideParent");
  const parent = await Parent.deploy();

  const Token = await ethers.getContractFactory("contracts/TideToken.sol:TideToken");
  const tidal = await Token.deploy("Tidal Token", "TIDAL", parent.address);
  const riptide = await Token.deploy("Riptide Token", "RIPTIDE", parent.address);

  const Poseidon = await ethers.getContractFactory("contracts/dummies/PoseidonDummy.sol:Poseidon");
  const poseidon = await Poseidon.deploy(tidal.address, riptide.address);

  await parent.setAddresses(tidal.address, riptide.address, poseidon.address);


  const wallets = await ethers.getSigners();
  const owner = wallets[0];
  const user = {
    alice: wallets[1],
    bob: wallets[2],
    carol: wallets[3]
  }    

  return {parent, tidal, riptide, poseidon, owner, user}
}

describe("Tide parent", () => {
  beforeEach(async () => {
    c = await loadFixture(fixture);
    parent = c.parent;
    tidal = c.tidal;
    riptide = c.riptide;
    poseidon = c.poseidon;
    owner = c.owner;
    user = c.user;
  });  
  
  it("Burn rate initialized at 6.9%", async () => {
    const {parent} = await loadFixture(fixture);
    expect(await parent.burnRate()).to.equal("6900000000000000000");
  });

  it("Burn rate max setting of 20%", async () => {
    const {parent} = await loadFixture(fixture);
    await parent.setBurnRate("200000000000000000");
    await expect(parent.setBurnRate("200000000000000001")).to.be.revertedWith("TIDEPARENT:setBurnRate: 20% max");
  });

  it("Transmute rate initialized at 0.42%", async () => {
    const {parent} = await loadFixture(fixture);
    expect(await parent.transmuteRate()).to.equal("420000000000000000");
  });

  it("Transmute rate max setting of 10%", async () => {
    const {parent} = await loadFixture(fixture);
    await parent.setTransmuteRate("100000000000000000");
    await expect(parent.setTransmuteRate("100000000000000001")).to.be.revertedWith("TIDEPARENT:setTransmuteRate: 10% max");
  });

  it("Tidal's sibling is Riptide", async () => {
    const {parent, tidal, riptide} = await loadFixture(fixture);
    expect(await parent.sibling(tidal.address)).to.equal(riptide.address);
  });

  it("Riptide's sibling is Tidal", async () => {
    const {parent, tidal, riptide} = await loadFixture(fixture);
    expect(await parent.sibling(riptide.address)).to.equal(tidal.address);
  });

  it("Poseidon can be replaced in parent config and whitelist", async () => {
    const {parent, user} = await loadFixture(fixture);
    const originalPoseidon = await parent.poseidon();
    const originalDetails = {
      whitelist: await parent.getWhitelist(originalPoseidon),
      protected: await parent.getProtectedAddress(originalPoseidon)
    }
    await parent.setPoseidon(user.alice.address);
    const newPoseidon = await parent.poseidon();
    expect(newPoseidon).to.not.equal(originalPoseidon);
    const newDetails = {
      whitelist: await parent.getWhitelist(newPoseidon),
      protected: await parent.getProtectedAddress(newPoseidon)
    }
    Object.keys(originalDetails).forEach(function(category) {
      for (i = 0; i < originalDetails[category].length; i++) {
        expect(originalDetails[category][i]).to.equal(newDetails[category][i]);
      }
    });
    oldDetails = {
      whitelist: await parent.getWhitelist(originalPoseidon),
      protected: await parent.getProtectedAddress(originalPoseidon)
    }
    expect(oldDetails.whitelist[0]).to.equal(false); // index 0 is bool: active
    expect(oldDetails.protected[0]).to.equal(false); // index 0 is bool: active
  });

  it("Siblings can be replaced", async () => {
    const {parent, user} = await loadFixture(fixture);
    const originalSiblings = [
      await parent.siblings(0),
      await parent.siblings(1)
    ];
    await parent.setSibling(0, user.alice.address);
    await parent.setSibling(1, user.bob.address);
    const newSiblings = [
      await parent.siblings(0),
      await parent.siblings(1)
    ];
    expect(originalSiblings[0]).to.not.equal(newSiblings[0]);
    expect(originalSiblings[1]).to.not.equal(newSiblings[1]);
  });

  it("Parent can be replaced", async () => {
    const {parent, tidal, riptide} = await loadFixture(fixture);
    const Parent = await ethers.getContractFactory("contracts/TideParent.sol:TideParent");
    const newParent = await Parent.deploy();
    const originalTidalParent = await tidal.parent();
    const originalRiptideParent = await riptide.parent();
    expect(originalTidalParent).to.equal(originalRiptideParent);
    await parent.setNewParent(newParent.address);
    const newTidalParent = await tidal.parent();
    const newRiptideParent = await riptide.parent();
    expect(originalTidalParent).to.not.equal(newTidalParent);
    expect(newTidalParent).to.equal(newRiptideParent);
  });

  it("onlyOwner functions cannot be called by others", async () => {
    const {parent, user} = await loadFixture(fixture);
    expect(parent.connect(user.alice).setPoseidon(user.bob.address)).to.be.revertedWith("Ownable: caller is not the owner");
    expect(parent.connect(user.alice).setSibling(0,user.bob.address)).to.be.revertedWith("Ownable: caller is not the owner");
    expect(parent.connect(user.alice).setSibling(1,user.bob.address)).to.be.revertedWith("Ownable: caller is not the owner");
    expect(parent.connect(user.alice).setAddresses(user.alice.address, user.bob.address, user.carol.address)).to.be.revertedWith("Ownable: caller is not the owner");
    expect(parent.connect(user.alice).setBurnRate(1)).to.be.revertedWith("Ownable: caller is not the owner");
    expect(parent.connect(user.alice).setTransmuteRate(1)).to.be.revertedWith("Ownable: caller is not the owner");
    expect(parent.connect(user.alice).setNewParent(user.bob.address)).to.be.revertedWith("Ownable: caller is not the owner");
  });
});





describe("Tide tokens", () => {
  beforeEach(async () => {
    c = await loadFixture(fixture);
    parent = c.parent;
    tidal = c.tidal;
    riptide = c.riptide;
    poseidon = c.poseidon;
    owner = c.owner;
    user = c.user;
  });


  it("Tidal is initially in phase", async () => {
    const {tidal, poseidon} = await loadFixture(fixture);
    expect(await poseidon.getPhase()).to.equal(tidal.address);
  })

  it("Tidal total supply of 0", async () => {
    const {tidal} = await loadFixture(fixture);
    expect(await tidal.totalSupply()).to.equal(0);
  });

  it("Owner can mint Tidal", async () => {
    const {tidal, owner} = await loadFixture(fixture);

    const tidalSupplyBefore = await tidal.totalSupply();
    const tidalBalBefore = await tidal.balanceOf(owner.address);
    expect(tidalSupplyBefore).to.equal(0);
    expect(tidalBalBefore).to.equal(0);
    await tidal.mint(owner.address, 10);
    expect(await tidal.totalSupply()).to.equal(10);
    expect(await tidal.balanceOf(owner.address)).to.equal(10);
  });

  it("Other user cannot mint Tidal", async () => {
    const {tidal, user} = await loadFixture(fixture);
    await expect(tidal.connect(user.alice).mint(user.alice.address, 10))
      .to.be.revertedWith(
        "TIDE::onlyMinter: Must be owner or sibling to call mint"
      );
  });

  it("Only parent can set a new parent", async () => {
    const {parent, tidal, user} = await loadFixture(fixture);
    const originalParent = tidal.parent();
    await expect(tidal.setParent(user.alice.address)).to.be.revertedWith(
      "TIDE::onlyParent: Only current parent can change parent"
    );
    // parent being able to do this is tested in the parent section
  });

  

});