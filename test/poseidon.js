const { expect } = require("chai");
const { waffle, ethers } = require("hardhat");
const { loadFixture } = waffle;
const provider = waffle.provider;
const { isCallTrace } = require("hardhat/internal/hardhat-network/stack-traces/message-trace");
const { deployMockContract } = require("ethereum-waffle");


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

  const Poseidon = await ethers.getContractFactory("contracts/Poseidon.sol:Poseidon");
  const poseidon = await Poseidon.deploy(
    mock.router.address,
    tidal.address,
    riptide.address,
    mock.surfEth.address,
    mock.surf.address,
    "0x0000000000000000000000000000000000000001",
    owner.address,
    1
  );

  const generic = [
    await (await ethers.getContractFactory("contracts/dummies/erc20.sol:Generic")).deploy("one"),
    await (await ethers.getContractFactory("contracts/dummies/erc20.sol:Generic")).deploy("two"),
    await (await ethers.getContractFactory("contracts/dummies/erc20.sol:Generic")).deploy("three"),
    await (await ethers.getContractFactory("contracts/dummies/erc20.sol:Generic")).deploy("four"),
    await (await ethers.getContractFactory("contracts/dummies/erc20.sol:Generic")).deploy("five"),
  ]

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

  return {parent, tidal, riptide, poseidon, owner, user, mock, generic}
}


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

  it("Weather config can only be set by owner", async () => {
    await expect(poseidon.connect(user.alice).setWeatherConfig(user.alice.address, 2)).to.be.revertedWith("Ownable: caller is not the owner");
    await poseidon.setWeatherConfig(user.alice.address, 2);
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

describe("Withdraw fee", () => {
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

  it("A pool with no withdraw fee does not have a fee levied", async () => {
    await generic[0].mint(owner.address, 100);
    await generic[0].approve(poseidon.address, 100);
    await poseidon.add(1, generic[0].address, 0, false);
    await poseidon.deposit(0, 100);
    blockTo(50);
    expect(await tidal.balanceOf(owner.address)).to.equal(0);;
    await poseidon.withdraw(0, 100);
    expect(await tidal.balanceOf(owner.address)).to.be.above(0);
  })

});
