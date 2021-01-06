const { expect } = require("chai");
const { waffle, ethers } = require("hardhat");
const { loadFixture } = waffle;
const provider = waffle.provider;
const { isCallTrace } = require("hardhat/internal/hardhat-network/stack-traces/message-trace");
const { deployMockContract } = require("ethereum-waffle");

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
    )
   }

  const Parent = await ethers.getContractFactory("contracts/TideParent.sol:TideParent");
  const parent = await Parent.deploy(mock.registry.address);

  const Token = await ethers.getContractFactory("contracts/TideToken.sol:TideToken");
  const tidal = await Token.deploy("Tidal Token", "TIDAL", parent.address);
  const riptide = await Token.deploy("Riptide Token", "RIPTIDE", parent.address);

  await mock.poseidon.mock.getPhase.returns(tidal.address);

  await parent.setAddresses(tidal.address, riptide.address, mock.poseidon.address);

  await mock.router.mock.WETH.returns(mock.weth.address);
  await mock.router.mock.factory.returns("0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f");
  await mock.router.mock.swapETHForExactTokens.returns([0,0,0]); // return not used


  const Sale = await ethers.getContractFactory("contracts/Sale.sol:Sale");    
  const sale = await Sale.deploy(
    tidal.address,
    riptide.address,
    mock.surf.address,
    mock.router.address,
    mock.surfEth.address,
    10
  );

  await tidal.transferOwnership(sale.address);
  await riptide.transferOwnership(sale.address);

  return {parent, tidal, riptide, sale, owner, user, mock}
}

describe("Sale: Before start", () => {
  beforeEach(async () => {
    c = await loadFixture(main);
    parent = c.parent;
    tidal = c.tidal;
    riptide = c.riptide;
    sale = c.sale;
    owner = c.owner;
    user = c.user;
    mock = c.mock;
  });
  
  it("Sale at stage 0", async function() {
    expect(await sale.stage()).to.equal(0);
  });

  it("Tide tokens supply is 0", async function() {
    expect(await tidal.totalSupply()).to.equal(0);
    expect(await riptide.totalSupply()).to.equal(0);
  });

  it("Sale contract is the owner of the tokens", async function() {
    expect(await tidal.owner()).to.equal(sale.address);
    expect(await riptide.owner()).to.equal(sale.address);
  });

  it("Cannot buy tokens yet", async function() {
    await expect(sale.buyTokensWithEth(0, {value: 1})).to.be.revertedWith('incorrect sale stage');
  });

});
