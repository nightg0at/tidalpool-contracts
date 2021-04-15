const { expect } = require("chai");
const { waffle, ethers } = require("hardhat");
const { loadFixture } = waffle;
const provider = waffle.provider;
const { isCallTrace } = require("hardhat/internal/hardhat-network/stack-traces/message-trace");
const { deployMockContract } = require("ethereum-waffle");
const { experimentalAddHardhatNetworkMessageTraceHook } = require("hardhat/config");


async function blockTo(endBlock, verbose = false) {
  if (verbose) console.log("block:", (await ethers.provider.getBlockNumber()));
  while ((await ethers.provider.getBlockNumber() < endBlock)) {
    await ethers.provider.send("evm_increaseTime", [60]);
    await ethers.provider.send("evm_mine");
  }
  if (verbose) console.log("block:", (await ethers.provider.getBlockNumber()));  
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
    surf: await deployMockContract(
      owner,
      require("../artifacts/@openzeppelin/contracts/token/ERC20/ERC20.sol/ERC20.json").abi
    ),
    surfEth: await deployMockContract(
      owner,
      require("../artifacts/@openzeppelin/contracts/token/ERC20/ERC20.sol/ERC20.json").abi
    ),
    weth: await deployMockContract(
      owner,
      require("../artifacts/@openzeppelin/contracts/token/ERC20/ERC20.sol/ERC20.json").abi
    ),
    registry: await deployMockContract(
      owner,
      require("../artifacts/@openzeppelin/contracts/introspection/IERC1820Registry.sol/IERC1820Registry.json").abi
    ),
    router: await deployMockContract(
      owner,
      require("../artifacts/@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol/IUniswapV2Router02.json").abi
    ),
    adapter: await deployMockContract(
      owner,
      require("../artifacts/contracts/restaking/PickleAdapter.sol/PickleAdapter.json").abi
    ),
  }
/*
  const Surf = await ethers.getContractFactory("contracts/dummies/erc20.sol:Surf");
  const surf = await Surf.deploy();
*/
  const Parent = await ethers.getContractFactory("contracts/TideParent.sol:TideParent");
  const parent = await Parent.deploy(mock.registry.address);

  const Token = await ethers.getContractFactory("contracts/TideToken.sol:TideToken");
  const tidal = await Token.deploy("Tidal Token", "TIDAL", parent.address);
  const riptide = await Token.deploy("Riptide Token", "RIPTIDE", parent.address);

  const boon = await (await ethers.getContractFactory("contracts/BoonToken.sol:BoonToken")).deploy();

  const generic = [
    await (await ethers.getContractFactory("contracts/dummies/erc20.sol:Generic")).deploy("zero"),
    await (await ethers.getContractFactory("contracts/dummies/erc20.sol:Generic")).deploy("one"),
    await (await ethers.getContractFactory("contracts/dummies/erc20.sol:Generic")).deploy("two"),
    await (await ethers.getContractFactory("contracts/dummies/erc20.sol:Generic")).deploy("three"),
    await (await ethers.getContractFactory("contracts/dummies/erc20.sol:Generic")).deploy("four"),
    await (await ethers.getContractFactory("contracts/dummies/erc20.sol:Generic")).deploy("five"),
  ]

  const lp = await (await ethers.getContractFactory("contracts/dummies/UniswapV2Pair.sol:UniswapV2Pair")).deploy();

  const Poseidon = await ethers.getContractFactory("contracts/Poseidon.sol:Poseidon");
  const poseidon = await Poseidon.deploy(
    mock.router.address,
    tidal.address,
    riptide.address,
    boon.address,
    generic[5].address, // mock surf
    "0x999b1e6EDCb412b59ECF0C5e14c20948Ce81F40b",
    owner.address,
    1
  );


  await tidal.transferOwnership(poseidon.address);
  await riptide.transferOwnership(poseidon.address);

  await parent.setAddresses(tidal.address, riptide.address, poseidon.address);

  await mock.surfEth.mock.balanceOf.returns(0);
  await mock.weth.mock.balanceOf.returns(0);

  /* may not be necessary for testing poseidon

  // surf-eth uniswap pair balances 10k:1
  await mock.weth.mock.balanceOf.withArgs(mock.surfEth.address).returns(1000);
  await surf.mint(mock.surfEth.address, 10000000);

  await mock.router.mock.WETH.returns(mock.weth.address);
  await mock.router.mock.factory.returns("0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f");
  await mock.router.mock.swapETHForExactTokens.returns([0,0,0]);
  await mock.router.mock.addLiquidity.returns(0,0,0);
  */
  await mock.router.mock.removeLiquidity.returns(0, 0);

  return {parent, tidal, riptide, boon, poseidon, owner, user, mock, generic, lp}
}

describe("Ownership and migration", () => {
  beforeEach(async () => {
    c = await loadFixture(main);
    parent = c.parent;
    tidal = c.tidal;
    riptide = c.riptide;
    poseidon = c.poseidon;
    owner = c.owner;
    user = c.user;
    mock = c.mock;
    generic = c.generic
  });

  it("Poseidon is the owner of tidal and riptide", async() => {
    expect(await tidal.owner()).to.equal(poseidon.address);
    expect(await riptide.owner()).to.equal(poseidon.address);
  });

  it("Migration: Token ownership can be transferred to new address", async() => {
    expect(await tidal.owner()).to.equal(poseidon.address);
    await poseidon.transferTokenOwnership(tidal.address, user.alice.address);
    expect(await tidal.owner()).to.equal(user.alice.address);
  });

  it("Migration: Tidal can be fully replaced in phase", async() => {
    const d = {
      token: generic[0],
      pid: 1,
      lp: generic[1]
    }
    await poseidon.add(100, d.lp.address, 0, true);

    expect(await poseidon.tidal()).to.equal(tidal.address);
    expect(await poseidon.getPhase()).to.equal(tidal.address);

    await d.token.transferOwnership(poseidon.address);
    await poseidon.setNewTidalToken(d.token.address);
    expect(await poseidon.tidal()).to.equal(d.token.address);
    expect(await poseidon.getPhase()).to.equal(d.token.address);

    await d.lp.mint(user.alice.address, 100);
    await d.lp.connect(user.alice).approve(poseidon.address, 100);
    await poseidon.connect(user.alice).deposit(d.pid, 100);
    expect(await d.token.balanceOf(user.alice.address)).to.equal(0);
    expect(await riptide.balanceOf(user.alice.address)).to.equal(0);
    await blockTo(50);
    await poseidon.connect(user.alice).withdraw(d.pid, 0);
    expect(await d.token.balanceOf(user.alice.address)).to.be.gt(0);
    expect(await riptide.balanceOf(user.alice.address)).to.equal(0);
  });

  it("Migration: Tidal can be fully replaced out of phase", async() => {
    const d = {
      token: generic[0],
      pid: 1,
      lp: generic[1]
    }
    await poseidon.add(100, d.lp.address, 0, true);

    expect(await poseidon.tidal()).to.equal(tidal.address);
    await poseidon.transferTokenOwnership(tidal.address, owner.address);
    await tidal.mint(user.bob.address, await poseidon.TIDAL_CAP());
    await tidal.transferOwnership(poseidon.address);
    await poseidon.updatePool(0);
    expect(await poseidon.getPhase()).to.equal(riptide.address);

    await d.token.mint(user.bob.address, await tidal.totalSupply());
    await d.token.transferOwnership(poseidon.address);
    await poseidon.setNewTidalToken(d.token.address);
    expect(await poseidon.tidal()).to.equal(d.token.address);
    expect(await poseidon.getPhase()).to.equal(riptide.address);

    await d.lp.mint(user.alice.address, 100);
    await d.lp.connect(user.alice).approve(poseidon.address, 100);
    await poseidon.connect(user.alice).deposit(d.pid, 100);
    expect(await d.token.balanceOf(user.alice.address)).to.equal(0);
    expect(await riptide.balanceOf(user.alice.address)).to.equal(0);
    await blockTo(50);
    await poseidon.connect(user.alice).withdraw(d.pid, 0);
    expect(await poseidon.getPhase()).to.equal(riptide.address);
    expect(await d.token.balanceOf(user.alice.address)).to.equal(0);
    expect(await riptide.balanceOf(user.alice.address)).to.be.gt(0);
  
  });

  it("Migration: Riptide can be fully replaced in phase", async() => {
    const d = {
      token: generic[0],
      pid: 1,
      lp: generic[1]
    }
    await poseidon.add(100, d.lp.address, 0, true);

    await poseidon.transferTokenOwnership(tidal.address, owner.address);
    await tidal.mint(user.bob.address, await poseidon.TIDAL_CAP());
    await tidal.transferOwnership(poseidon.address);
    await poseidon.updatePool(0);
    expect(await poseidon.getPhase()).to.equal(riptide.address);

    await d.token.transferOwnership(poseidon.address);
    await poseidon.setNewRiptideToken(d.token.address);
    expect(await poseidon.riptide()).to.equal(d.token.address);
    expect(await poseidon.getPhase()).to.equal(d.token.address);

    await d.lp.mint(user.alice.address, 100);
    await d.lp.connect(user.alice).approve(poseidon.address, 100);
    await poseidon.connect(user.alice).deposit(d.pid, 100);
    expect(await d.token.balanceOf(user.alice.address)).to.equal(0);
    expect(await tidal.balanceOf(user.alice.address)).to.equal(0);
    await blockTo(50);
    await poseidon.connect(user.alice).withdraw(d.pid, 0);
    expect(await d.token.balanceOf(user.alice.address)).to.be.gt(0);
    expect(await tidal.balanceOf(user.alice.address)).to.equal(0);
  });

  it("Migration: Riptide can be fully replaced out of phase", async() => {
    const d = {
      token: generic[0],
      pid: 1,
      lp: generic[1]
    }
    await poseidon.add(100, d.lp.address, 0, true);

    expect(await poseidon.tidal()).to.equal(tidal.address);

    await d.token.transferOwnership(poseidon.address);
    await poseidon.setNewRiptideToken(d.token.address);
    expect(await poseidon.riptide()).to.equal(d.token.address);
    expect(await poseidon.getPhase()).to.equal(tidal.address);

    await d.lp.mint(user.alice.address, 100);
    await d.lp.connect(user.alice).approve(poseidon.address, 100);
    await poseidon.connect(user.alice).deposit(d.pid, 100);
    expect(await d.token.balanceOf(user.alice.address)).to.equal(0);
    expect(await tidal.balanceOf(user.alice.address)).to.equal(0);
    await blockTo(50);
    await poseidon.connect(user.alice).withdraw(d.pid, 0);
    expect(await poseidon.getPhase()).to.equal(tidal.address);
    expect(await d.token.balanceOf(user.alice.address)).to.equal(0);
    expect(await tidal.balanceOf(user.alice.address)).to.be.gt(0);
  });

})

describe("Config changes (onlyOwner)", () => {
  beforeEach(async () => {
    c = await loadFixture(main);
    parent = c.parent;
    tidal = c.tidal;
    riptide = c.riptide;
    poseidon = c.poseidon;
    owner = c.owner;
    user = c.user;
    mock = c.mock;
    generic = c.generic

  });

  it("Add pool", async () => {
    await expect(poseidon.connect(user.alice).add(0, generic[0].address, 0, false)).to.be.revertedWith("Ownable: caller is not the owner");
    await poseidon.add(0, generic[0].address, 0, false);
    const pool = await poseidon.poolInfo(1);
    expect(pool.lpToken).to.equal(generic[0].address);
  });

  it("Add restaking pool", async () => {
    // to pass validAdapter() modifier
    await mock.adapter.mock.rewardTokenAddress.returns(generic[0].address);
    await mock.adapter.mock.lpTokenAddress.returns(generic[1].address);

    await expect(poseidon.connect(user.alice).addWithRestaking(0, 0, false, mock.adapter.address)).to.be.revertedWith("Ownable: caller is not the owner");
    await poseidon.addWithRestaking(0, 0, false, mock.adapter.address);
    const pool = await poseidon.poolInfo(1);
    expect(pool.lpToken).to.equal(generic[1].address);
    expect(pool.adapter).to.equal(mock.adapter.address);
  });

  it("Set alloc point", async () => {
    await poseidon.add(1, generic[0].address, 0, false);
    const poolBefore = await poseidon.poolInfo(1);
    expect(poolBefore.allocPoint).to.equal(1);
    await expect(poseidon.connect(user.alice).set(1, 2, false)).to.be.revertedWith("Ownable: caller is not the owner");
    await poseidon.set(1, 2, false);
    const poolAfter = await poseidon.poolInfo(1);
    expect(poolAfter.allocPoint).to.equal(2);
  });

  it("Set non-restaking pool to restaking", async () => {
    await mock.adapter.mock.rewardTokenAddress.returns(generic[0].address);
    await mock.adapter.mock.lpTokenAddress.returns(generic[0].address);    
    await poseidon.add(1, generic[0].address, 0, false);
    const poolBefore = await poseidon.poolInfo(1);
    expect(await poseidon.isRestaking(1)).to.equal(false);
    expect(poolBefore.adapter).to.equal("0x0000000000000000000000000000000000000000");
    await expect(poseidon.connect(user.alice).setRestaking(1, mock.adapter.address, false)).to.be.revertedWith("Ownable: caller is not the owner");
    await poseidon.setRestaking(1, mock.adapter.address, false);
    const poolAfter = await poseidon.poolInfo(1);
    expect(await poseidon.isRestaking(1)).to.equal(true);
    expect(poolAfter.adapter).to.equal(mock.adapter.address);
  });

  it("Remove restaking", async () => {
    await mock.adapter.mock.rewardTokenAddress.returns(generic[0].address);
    await mock.adapter.mock.lpTokenAddress.returns(generic[1].address);
    await mock.adapter.mock.emergencyWithdraw.returns();
    await poseidon.addWithRestaking(0, 0, false, mock.adapter.address);
    await expect(poseidon.connect(user.alice).removeRestaking(1, false)).to.be.revertedWith("Ownable: caller is not the owner");
    const poolBefore = await poseidon.poolInfo(1);
    expect(await poseidon.isRestaking(1)).to.equal(true);
    expect(poolBefore.adapter).to.equal(mock.adapter.address);
    await poseidon.removeRestaking(1, false);
    const poolAfter = await poseidon.poolInfo(1);
    expect(await poseidon.isRestaking(1)).to.equal(false);
    expect(poolAfter.adapter).to.equal("0x0000000000000000000000000000000000000000");
  })

  it("Weather config", async () => {
    await expect(poseidon.connect(user.alice).setWeatherConfig(user.alice.address, 2)).to.be.revertedWith("Ownable: caller is not the owner");
    await poseidon.setWeatherConfig(user.alice.address, 2);
  });

  it("Rewards per block", async () => {
    const rewardBefore = await poseidon.baseRewardPerBlock();
    await expect(poseidon.connect(user.alice).setRewardPerBlock(10)).to.be.revertedWith("Ownable: caller is not the owner");
    await poseidon.setRewardPerBlock(10);
    expect (await poseidon.baseRewardPerBlock()).to.equal(10);
    expect (await poseidon.baseRewardPerBlock()).to.not.equal(rewardBefore);
  });

  it("Surf token and whirlpool addresses", async () => {
    const surfBefore = await poseidon.surf();
    const whirlpoolBefore = await poseidon.whirlpool();
    await expect(poseidon.connect(user.alice).setSurfConfig(generic[0].address, generic[1].address)).to.be.revertedWith("Ownable: caller is not the owner");
    await poseidon.setSurfConfig(generic[2].address, generic[3].address);
    expect(surfBefore).to.equal(generic[5].address);
    expect(whirlpoolBefore).to.equal("0x999b1e6EDCb412b59ECF0C5e14c20948Ce81F40b");
    expect(await poseidon.surf()).to.equal(generic[2].address);
    expect(await poseidon.whirlpool()).to.equal(generic[3].address);
  });

  it("Dev address", async () => {
    const devBefore = await poseidon.devaddr();
    await expect(poseidon.connect(user.alice).dev(generic[0].address)).to.be.revertedWith("Ownable: caller is not the owner");
    await poseidon.dev(generic[1].address);
    expect(await poseidon.devaddr()).to.equal(generic[1].address);
    expect(await poseidon.devaddr()).to.not.equal(devBefore);
  });

  it("Withdraw fee address", async () => {
    const feeBefore = await poseidon.feeaddr();
    await expect(poseidon.connect(user.alice).fee(generic[0].address)).to.be.revertedWith("Ownable: caller is not the owner");
    await poseidon.fee(generic[1].address);
    expect(await poseidon.feeaddr()).to.equal(generic[1].address);
    expect(await poseidon.feeaddr()).to.not.equal(feeBefore);
  });

});

describe("Weather", () => {
  beforeEach(async () => {
    c = await loadFixture(main);
    parent = c.parent;
    tidal = c.tidal;
    riptide = c.riptide;
    poseidon = c.poseidon;
    owner = c.owner;
    user = c.user;
    mock = c.mock;
    generic = c.generic
    //surf = c.surf;

  });

  it("Weather should not be stormy by default", async () => {
    expect(await poseidon.stormy()).to.equal(false);
  });

  

  it("Weather can only be changed by Zeus", async () => {
    await poseidon.setWeatherConfig(user.alice.address, 2);
    expect(await poseidon.stormy()).to.equal(false);
    await expect(poseidon.setWeather(true, false)).to.be.revertedWith("only zeus can call this method");
    await poseidon.connect(user.alice).setWeather(true, false);
    expect(await poseidon.stormy()).to.equal(true);
  });

  it("Stormy state divides native rewards per block by storm divisor", async () => {
    expect(await poseidon.getPhase()).to.equal(tidal.address);
    const baseReward = await poseidon.baseRewardPerBlock();
    expect(await poseidon.tokensPerBlock(tidal.address)).to.equal(baseReward);
    await poseidon.setWeatherConfig(user.alice.address, 2);
    await poseidon.connect(user.alice).setWeather(true, false);
    expect(await poseidon.tokensPerBlock(tidal.address)).to.equal(baseReward.div(await poseidon.stormDivisor()));
  });

});

describe("Withdraw", () => {
  beforeEach(async () => {
    c = await loadFixture(main);
    parent = c.parent;
    tidal = c.tidal;
    riptide = c.riptide;
    poseidon = c.poseidon;
    owner = c.owner;
    user = c.user;
    mock = c.mock;
    generic = c.generic;
    lp = c.lp;
    //surf = c.surf;

  });

  it("A pool with no withdraw fee does not have a fee levied", async () => {
    await generic[0].mint(owner.address, 100);
    await generic[0].approve(poseidon.address, 100);
    await poseidon.add(1, generic[0].address, 0, false);
    await poseidon.deposit(1, 100);
    blockTo(50);
    expect(await tidal.balanceOf(owner.address)).to.equal(0);
    await poseidon.withdraw(1, 100);
    expect(await tidal.balanceOf(owner.address)).to.be.above(0);
  });

  it("A pool with 10% withdraw fee has a 10% fee levied", async () => {
    await lp.initialize(generic[0].address, generic[1].address);
    await generic[0].mint(lp.address, 1000);
    await generic[1].mint(lp.address, 1000);
    
    await lp.mint(owner.address, 100);
    await lp.approve(poseidon.address, 100);
    await poseidon.add(1, lp.address, "100000000000000000", false); // fee of 0.1, 1e17
    await poseidon.deposit(1, 100);
    blockTo(50);
    await poseidon.withdraw(1, 100);
    expect(await lp.balanceOf(owner.address)).to.equal(90);
  });

  it("A pool containing surf has 10% withdraw fee sent to whirlpool", async () => {
    await lp.initialize(tidal.address, generic[5].address);
    await poseidon.transferTokenOwnership(tidal.address, owner.address);
    await tidal.mint(lp.address, 1000);
    await tidal.transferOwnership(poseidon.address);
    await generic[5].mint(lp.address, 1000);
    await generic[5].mint(poseidon.address, 100); // mint to simulate liquidity removal

    await lp.mint(owner.address, 100);
    await lp.approve(poseidon.address, 100);
    await poseidon.add(1, lp.address, "100000000000000000", false);
    await poseidon.deposit(1, 100);
    blockTo(50);
    expect(await generic[5].balanceOf(poseidon.address)).to.equal(100);
    expect(await generic[5].balanceOf("0x999b1e6EDCb412b59ECF0C5e14c20948Ce81F40b")).to.equal(0);
    await mock.router.mock.swapExactTokensForTokens.returns([0,0,0]);
    await mock.router.mock.removeLiquidity.returns(100, 100);
    await poseidon.withdraw(1, 100);
    expect(await generic[5].balanceOf(poseidon.address)).to.equal(0);
    expect(await generic[5].balanceOf("0x999b1e6EDCb412b59ECF0C5e14c20948Ce81F40b")).to.equal(100);
  });

  it("A pool not containing surf has 10% withdraw fee sent to feeaddr", async() => {
    await poseidon.fee(user.alice.address);

    await lp.initialize(generic[0].address, generic[1].address);
    await generic[0].mint(lp.address, 1000);
    await generic[1].mint(lp.address, 1000);
    await generic[0].mint(poseidon.address, 100); // to simulate liquidity removal
    await generic[1].mint(poseidon.address, 100); // to simulate liquidity removal

    await lp.mint(owner.address, 100);
    await lp.approve(poseidon.address, 100);
    await poseidon.add(1, lp.address, "100000000000000000", false);
    await poseidon.deposit(1, 100);
    blockTo(50);
    const feeAddr = await poseidon.feeaddr();
    expect(await generic[0].balanceOf(feeAddr)).to.equal(0);
    expect(await generic[1].balanceOf(feeAddr)).to.equal(0);
    await mock.router.mock.removeLiquidity.returns(100, 100);
    await poseidon.withdraw(1, 100);
    expect(feeAddr).to.equal(user.alice.address);
    expect(await generic[0].balanceOf(feeAddr)).to.equal(100);
    expect(await generic[1].balanceOf(feeAddr)).to.equal(100);
  })

});


describe("Airdrop farming simulation", () => {
  beforeEach(async () => {
    c = await loadFixture(main);
    parent = c.parent;
    tidal = c.tidal;
    riptide = c.riptide;
    boon = c.boon;
    poseidon = c.poseidon;
    owner = c.owner;
    user = c.user;
    mock = c.mock;
    generic = c.generic;
    lp = c.lp;
  });

  it("Farming Boon should yield 4.2 tidal during the first phase", async () => {
    await poseidon.transferTokenOwnership(tidal.address, owner.address);
    await tidal.mint(generic[0].address, "8400000000000000000") //4.2 sale + 4.2 TIDAL-SURF-LP
    await tidal.transferOwnership(poseidon.address);

    expect(await poseidon.phase()).to.equal(tidal.address);
    await poseidon.setRewardPerBlock(0);

    /*
      totalSupply - sale and lp
      69 - 8.4 = 60.6
      target emission is 4.2
      4.2 / 60.6 = 0.0693069306930693 // ~ 6.9% of emissions

      let totalAllocPoint = 1000;
      boon allocPoint = (4.2/60.6)*1000 = 69
      other allocPoint = 1000 - 69 = 931
    */
  
    await poseidon.add(931, generic[0].address, 0, false);
    await poseidon.set(0, 69, false);

    await boon.mint(owner.address, 100);
    await boon.approve(poseidon.address, 100);
    await poseidon.deposit(0, 100);

    await generic[0].mint(owner.address, 100);
    await generic[0].approve(poseidon.address, 100);
    await poseidon.deposit(1, 100);
  
    // high rewards to speed things up
    await poseidon.setRewardPerBlock("100000000000000000"); // 0.1
    const capHit = 60.6/0.1;
    const block = await ethers.provider.getBlockNumber();
    const target = capHit + block;
    await blockTo(target); // fast forward to the endtime
    await poseidon.massUpdatePools();
    const poolBefore = await poseidon.poolInfo(0);
    expect(poolBefore.allocPoint).to.equal(69);
    await poseidon.massUpdatePools(); // twice because the updatePhase() before minting
    //console.log("Tidal supply: %s", ethers.utils.formatEther(await tidal.totalSupply()));
    expect(await poseidon.phase()).to.equal(riptide.address);
    const poolAfter = await poseidon.poolInfo(0);
    expect(poolAfter.allocPoint).to.equal(0);
    const pending = await poseidon.pendingTokens(0, owner.address);
    //console.log("Pending rewards from pool 0: %s", ethers.utils.formatEther(pending[0]));
  });

});