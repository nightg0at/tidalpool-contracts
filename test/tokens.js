const { expect } = require("chai");
const { waffle, ethers } = require("hardhat");
const { loadFixture } = waffle;
const provider = waffle.provider;
const { isCallTrace } = require("hardhat/internal/hardhat-network/stack-traces/message-trace");
const { deployMockContract } = require("ethereum-waffle");

function nice(thing) {
  let name = Object.keys(thing)[0];
  let val = thing[name];
  console.log(`${name}: ${ethers.utils.formatEther(val)} (${val})`);
}

async function main(provider) {
  const wallets = await ethers.getSigners();
  const owner = wallets[0];
  const user = {
    alice: wallets[1],
    bob: wallets[2],
    carol: wallets[3]
  }

  const mock = {
    poseidon: await deployMockContract(
      owner,
      require("../artifacts/contracts/Poseidon.sol/Poseidon.json").abi
    ),
    erc20: await deployMockContract(
      owner,
      require("../artifacts/@openzeppelin/contracts/token/ERC20/ERC20.sol/ERC20.json").abi
    ),
    erc1155: await deployMockContract(
      owner,
      require("../artifacts/@openzeppelin/contracts/token/ERC1155/ERC1155.sol/ERC1155.json").abi
    ),
    registry: await deployMockContract(
      owner,
      require("../artifacts/@openzeppelin/contracts/introspection/IERC1820Registry.sol/IERC1820Registry.json").abi
    ),
    uniswapPair: await deployMockContract(
      owner,
      require("../artifacts/@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol/IUniswapV2Pair.json").abi
    )
  }



  const Parent = await ethers.getContractFactory("contracts/TideParent.sol:TideParent");
  const parent = await Parent.deploy(mock.registry.address);

  const Token = await ethers.getContractFactory("contracts/TideToken.sol:TideToken");
  const tidal = await Token.deploy("Tidal Token", "TIDAL", parent.address);
  const riptide = await Token.deploy("Riptide Token", "RIPTIDE", parent.address);

  await mock.registry.mock.implementsERC165Interface.returns(false);
  await mock.registry.mock.implementsERC165Interface.withArgs(mock.erc1155.address, "0xd9b67a26").returns(true);
  await mock.uniswapPair.mock.factory.returns("0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f");
  await mock.poseidon.mock.getPhase.returns(tidal.address);

  await parent.setAddresses(tidal.address, riptide.address, mock.poseidon.address);

  return {parent, tidal, riptide, owner, user, mock}
}


describe("Tide parent config", () => {
  beforeEach(async () => {
    c = await loadFixture(main);
    parent = c.parent;
    tidal = c.tidal;
    riptide = c.riptide;
    owner = c.owner;
    user = c.user;
    mock = c.mock;
  });  
  
  it("Burn rate initialized at 6.9%", async () => {
    expect(await parent.burnRate()).to.equal("6900000000000000000");
  });

  it("Burn rate max setting of 20%", async () => {
    await parent.setBurnRate("200000000000000000");
    await expect(parent.setBurnRate("200000000000000001")).to.be.revertedWith("TIDEPARENT:setBurnRate: 20% max");
  });

  it("Transmute rate initialized at 0.42%", async () => {
    expect(await parent.transmuteRate()).to.equal("420000000000000000");
  });

  it("Transmute rate max setting of 10%", async () => {
    await parent.setTransmuteRate("100000000000000000");
    await expect(parent.setTransmuteRate("100000000000000001")).to.be.revertedWith("TIDEPARENT:setTransmuteRate: 10% max");
  });

  it("Tidal's sibling is Riptide", async () => {
    expect(await parent.sibling(tidal.address)).to.equal(riptide.address);
  });

  it("Riptide's sibling is Tidal", async () => {
    expect(await parent.sibling(riptide.address)).to.equal(tidal.address);
  });

  it("Poseidon can be replaced in parent config and whitelist", async () => {
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
    const Parent = await ethers.getContractFactory("contracts/TideParent.sol:TideParent");
    const newParent = await Parent.deploy(mock.registry.address);
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
    expect(parent.connect(user.alice).setPoseidon(user.bob.address)).to.be.revertedWith("Ownable: caller is not the owner");
    expect(parent.connect(user.alice).setSibling(0,user.bob.address)).to.be.revertedWith("Ownable: caller is not the owner");
    expect(parent.connect(user.alice).setSibling(1,user.bob.address)).to.be.revertedWith("Ownable: caller is not the owner");
    expect(parent.connect(user.alice).setAddresses(user.alice.address, user.bob.address, user.carol.address)).to.be.revertedWith("Ownable: caller is not the owner");
    expect(parent.connect(user.alice).setBurnRate(1)).to.be.revertedWith("Ownable: caller is not the owner");
    expect(parent.connect(user.alice).setTransmuteRate(1)).to.be.revertedWith("Ownable: caller is not the owner");
    expect(parent.connect(user.alice).setNewParent(user.bob.address)).to.be.revertedWith("Ownable: caller is not the owner");
  });
});

describe("Tide parent whitelist management", () => {
  beforeEach(async () => {
    c = await loadFixture(main);
    parent = c.parent;
    tidal = c.tidal;
    riptide = c.riptide;
    owner = c.owner;
    user = c.user;
    mock = c.mock;
  });

  it("Protector: add", async () => {
    const index = 0;
    const detailsBefore = await parent.getProtectorAttributes(mock.erc20.address, index);
    expect(detailsBefore[0]).to.equal(false);
    const proportion = "1000000000000000000";
    const floor = "249600000000000000";
    await parent.addProtector(mock.erc20.address, index, proportion, floor);
    const detailsAfter = await parent.getProtectorAttributes(mock.erc20.address, index);
    expect(detailsAfter[0]).to.equal(true);
    expect(detailsAfter[1]).to.equal(proportion);
    expect(detailsAfter[2]).to.equal(floor);
  });

  it("Protector: edit", async () => {
    const index = 0;    
    await parent.addProtector(mock.erc20.address, index, 1, 2);
    const detailsBefore = await parent.getProtectorAttributes(mock.erc20.address, index);
    expect(detailsBefore[0]).to.equal(true);
    expect(detailsBefore[1]).to.equal(1);
    expect(detailsBefore[2]).to.equal(2);
    await parent.editProtector(mock.erc20.address, true, index, 2, 3);
    const detailsAfter = await parent.getProtectorAttributes(mock.erc20.address, index);
    expect(detailsAfter[0]).to.equal(true);
    expect(detailsAfter[1]).to.equal(2);
    expect(detailsAfter[2]).to.equal(3);
  });

  it("Protector: disable", async () => {
    const index = 0;    
    await parent.addProtector(mock.erc20.address, index, 0, 0);
    const detailsBefore = await parent.getProtectorAttributes(mock.erc20.address, index);
    expect(detailsBefore[0]).to.equal(true);
    await parent.editProtector(mock.erc20.address, false, index, 0, 0);
    const detailsAfter = await parent.getProtectorAttributes(mock.erc20.address, index);
    expect(detailsAfter[0]).to.equal(false);
  });

  it("Protector: address has token", async () => {
    const index = 0;
    await mock.erc1155.mock.balanceOf.withArgs(owner.address, index).returns(1);
    await parent.addProtector(mock.erc1155.address, index, 2, 3);
    expect(await parent.hasProtector(owner.address, mock.erc1155.address, index)).to.equal(true);
  })

  it("Protector: cumulative protection of address",async () => {
    const surfboard = {
      index: 0,
      proportion: "500000000000000000",
      floor:0
    }
    await mock.erc1155.mock.balanceOf.withArgs(owner.address, surfboard.index).returns(1);
    await parent.addProtector(
      mock.erc1155.address,
      surfboard.index,
      surfboard.proportion,
      surfboard.floor
    );

    const silverTrident = {
      index: 1,
      proportion: "1000000000000000000",
      floor: "420000000000000000"
    }
    await mock.erc1155.mock.balanceOf.withArgs(owner.address, silverTrident.index).returns(1);
    await parent.addProtector(
      mock.erc1155.address,
      silverTrident.index,
      silverTrident.proportion,
      silverTrident.floor
    );

    const cumulative = await parent.cumulativeProtectionOf(owner.address);
    expect(cumulative[0]).to.equal(surfboard.proportion);
    expect(cumulative[1]).to.equal(silverTrident.floor);

  });
  
  it("Protected address: add", async () => {
    const detailsBefore = await parent.getProtectedAddress(user.alice.address);
    expect(detailsBefore[0]).to.equal(false);
    const proportion = "1000000000000000000";
    const floor = "249600000000000000";
    await parent.setProtectedAddress(user.alice.address, true, proportion, floor);
    const detailsAfter = await parent.getProtectedAddress(user.alice.address);
    expect(detailsAfter[0]).to.equal(true);
    expect(detailsAfter[1]).to.equal(proportion);
    expect(detailsAfter[2]).to.equal(floor);

  });

  it("Protected address: edit", async () => {
    await parent.setProtectedAddress(user.alice.address, true, 1, 2);
    const detailsBefore = await parent.getProtectedAddress(user.alice.address);
    expect(detailsBefore[0]).to.equal(true);
    expect(detailsBefore[1]).to.equal(1);
    expect(detailsBefore[2]).to.equal(2);
    await parent.setProtectedAddress(user.alice.address, true, 8, 9);
    const detailsAfter = await parent.getProtectedAddress(user.alice.address);
    expect(detailsAfter[0]).to.equal(true);
    expect(detailsAfter[1]).to.equal(8);
    expect(detailsAfter[2]).to.equal(9);
  });

  it("Protected address: disable", async () => {
    await parent.setProtectedAddress(user.alice.address, true, 0, 0);
    const detailsBefore = await parent.getProtectedAddress(user.alice.address);
    expect(detailsBefore[0]).to.equal(true);
    await parent.setProtectedAddress(user.alice.address, false, 0, 0);
    const detailsAfter = await parent.getProtectedAddress(user.alice.address);
    expect(detailsAfter[0]).to.equal(false);
  });


  it("Whitelist: add")
  it("Whitelist: edit")
  it("Whitelist: disable")
  it("Whitelist: get")

  it("Whitelist: burn protected")
  it("Whitelist: wipeout protected")

});



describe("Tide tokens: non-transfer functionality", () => {
  beforeEach(async () => {
    c = await loadFixture(main);
    parent = c.parent;
    tidal = c.tidal;
    riptide = c.riptide;
    owner = c.owner;
    user = c.user;
  });


  it("Tidal total supply of 0", async () => {
    expect(await tidal.totalSupply()).to.equal(0);
  });

  it("Owner can mint Tidal", async () => {
    const tidalSupplyBefore = await tidal.totalSupply();
    const tidalBalBefore = await tidal.balanceOf(owner.address);
    expect(tidalSupplyBefore).to.equal(0);
    expect(tidalBalBefore).to.equal(0);
    await tidal.mint(owner.address, 10);
    expect(await tidal.totalSupply()).to.equal(10);
    expect(await tidal.balanceOf(owner.address)).to.equal(10);
  });

  it("Other user cannot mint Tidal", async () => {
    await expect(tidal.connect(user.alice).mint(user.alice.address, 10))
      .to.be.revertedWith(
        "TIDE::onlyMinter: Must be owner or sibling to call mint"
      );
  });

  it("Only parent can set a new parent", async () => {
    const originalParent = tidal.parent();
    await expect(tidal.setParent(user.alice.address)).to.be.revertedWith(
      "TIDE::onlyParent: Only current parent can change parent"
    );
    // parent being able to do this is tested in the parent section
  });

});


describe("Tide tokens: transfers", () => {
  beforeEach(async () => {
    c = await loadFixture(main);
    parent = c.parent;
    tidal = c.tidal;
    riptide = c.riptide;
    owner = c.owner;
    user = c.user;
  });

  it("An out of phase token has 6.9% burned during transfer")

  it("An in phase token has 0.42% transmuted during transfer")

  it("Wipeout as expected with no protection")

  it("Wipeout as expected with protection: surfboard")
  it("Wipeout as expected with protection: bronze trident")
  it("Wipeout as expected with protection: bronze trident + surfboard")
  it("Wipeout as expected with protection: silver trident")
  it("Wipeout as expected with protection: silver trident + surfboard")
  it("Wipeout as expected with protection: gold trident")
  it("Wipeout as expected with protection: gold trident + surfboard")

  it("Wipeout as expected with protected address")
  it("Wipeout as expected with uniswap token pair")
  it("Wipeout as expected with whitelisted address: sendWipeout")
  it("Wipeout as expected with whitelisted address: receiveWipeout")

  it("Transfer as expected with whitelisted address: sendBurn")
  it("Transfer as expected with whitelisted address: receiveBurn")


});