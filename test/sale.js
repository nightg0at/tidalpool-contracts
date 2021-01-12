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
    poseidon: await deployMockContract(
      owner,
      require("../artifacts/contracts/Poseidon.sol/Poseidon.json").abi
    ),/*
    surf: await deployMockContract(
      owner,
      require("../artifacts/@openzeppelin/contracts/token/ERC20/ERC20.sol/ERC20.json").abi
    ),*/
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

  const Surf = await ethers.getContractFactory("contracts/dummies/erc20.sol:Surf");
  const surf = await Surf.deploy();

  const Parent = await ethers.getContractFactory("contracts/TideParent.sol:TideParent");
  const parent = await Parent.deploy(mock.registry.address);

  const Token = await ethers.getContractFactory("contracts/TideToken.sol:TideToken");
  const tidal = await Token.deploy("Tidal Token", "TIDAL", parent.address);
  const riptide = await Token.deploy("Riptide Token", "RIPTIDE", parent.address);

  await mock.poseidon.mock.getPhase.returns(tidal.address);

  await parent.setAddresses(tidal.address, riptide.address, mock.poseidon.address);

  //await mock.surf.mock.balanceOf.returns(0);
  await mock.surfEth.mock.balanceOf.returns(0);
  await mock.weth.mock.balanceOf.returns(0);

  // surf-eth uniswap pair balances 10k:1
  await mock.weth.mock.balanceOf.withArgs(mock.surfEth.address).returns(1000);
  await surf.mint(mock.surfEth.address, 10000000);
  //await mock.surf.mock.balanceOf.withArgs(mock.surfEth.address).returns(10000000);
  //await mock.surf.mock.transferFrom.returns(true);

  await mock.router.mock.WETH.returns(mock.weth.address);
  await mock.router.mock.factory.returns("0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f");
  await mock.router.mock.swapETHForExactTokens.returns([0,0,0]);
  await mock.router.mock.addLiquidity.returns(0,0,0);

  return {parent, tidal, riptide, surf, owner, user, mock}
}



describe("Sale: Before start", () => {
  beforeEach(async () => {
    c = await loadFixture(main);
    parent = c.parent;
    tidal = c.tidal;
    riptide = c.riptide;
    owner = c.owner;
    user = c.user;
    mock = c.mock;
    surf = c.surf;

    const Sale = await ethers.getContractFactory("contracts/Sale.sol:Sale");    
    sale = await Sale.deploy(
      tidal.address,
      riptide.address,
      surf.address, //mock.surf.address,
      mock.router.address,
      mock.surfEth.address,
      10,
      100,
      500
    );

    await tidal.transferOwnership(sale.address);
    await riptide.transferOwnership(sale.address);
  });

  it("Initial details view", async () => {
    const details = await sale.details();
    expect(details[0]).to.equal(0);   // stage
    expect(details[1]).to.equal(await sale.rate());   // rate
    expect(details[2]).to.equal(await sale.amountForSale());   // amount for sale
    expect(details[3]).to.equal(0);   // token 0 sold
    expect(details[4]).to.equal(0);   // token 1 sold
  });

  it("Sale at stage 0", async () => {
    expect(await sale.stage()).to.equal(0);
  });

  it("Tide tokens supply is 0", async () => {
    expect(await tidal.totalSupply()).to.equal(0);
    expect(await riptide.totalSupply()).to.equal(0);
  });

  it("Tidal is token 0", async () => {
    const tokenDetails = await sale.t(0);
    expect(tokenDetails.token).to.equal(tidal.address);
  });

  it("Riptide is token 1", async () => {
    const tokenDetails = await sale.t(1);
    expect(tokenDetails.token).to.equal(riptide.address);
  });

  it("Sale contract is the owner of the tokens", async () => {
    expect(await tidal.owner()).to.equal(sale.address);
    expect(await riptide.owner()).to.equal(sale.address);
  });

  it("Can change sale's start and finish blocks", async () => {
    expect(await sale.startBlock()).to.equal(100);
    await sale.startAt(200);
    expect(await sale.startBlock()).to.equal(200);

    expect(await sale.finishBlock()).to.equal(500);
    await sale.finishAt(750);
    expect(await sale.finishBlock()).to.equal(750);

  });

  it("Start and finish changes blocked for non-owner", async () => {
    await expect(sale.connect(user.alice).startAt(500)).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(sale.connect(user.alice).finishAt(500)).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("Start and finish changes must happen before T - delayWarning blocks", async () => {
    const delay = parseInt(await sale.delayWarning());

    const startBlockOriginal = parseInt(await sale.startBlock());
    await blockTo(startBlockOriginal - 1);
    const startBlockNew = startBlockOriginal + delay;
    await expect(sale.startAt(startBlockNew)).to.be.revertedWith("SALE::startAt: Not enough warning");
    await sale.startAt(startBlockNew + 2); // we have moved on 1 block so bump 2 to test boundary

    const finishBlockOriginal = parseInt(await sale.finishBlock());
    await blockTo(finishBlockOriginal - 1);
    const finishBlockNew = finishBlockOriginal + delay;
    await expect(sale.finishAt(finishBlockNew)).to.be.revertedWith("SALE::finishAt: Not enough warning");
    await sale.finishAt(finishBlockNew + 2); // we have moved on 1 block so bump 2 to test boundary
  });

  it("Cannot buy tokens yet", async () => {
    await expect(owner.sendTransaction({to: sale.address, value: 1})).to.be.revertedWith("SALE::onlyStage: Incorrect stage for this method");
    await expect(sale.buyTokensWithEth(0, {value: 1})).to.be.revertedWith("SALE::onlyStage: Incorrect stage for this method");
    //await mock.surf.mock.balanceOf.withArgs(owner.address).returns(1000);
    await surf.mint(owner.address, 1000);
    await expect(sale.buyTokens(500, 0)).to.be.revertedWith("SALE::onlyStage: Incorrect stage for this method");
  });

  it("Cannot finalize sale", async () => {
    await expect(sale.finalize()).to.be.revertedWith("SALE::onlyStage: Incorrect stage for this method");
  });

  it("Cannot transfer token ownerships", async () => {
    await expect(sale.transferTokenOwnerships(user.alice.address)).to.be.revertedWith("SALE::onlyStage: Incorrect stage for this method");
  });

  it("Cannot withdraw tokens", async () => {
    await expect(sale.withdraw(user.alice.address, 0)).to.be.revertedWith("SALE::onlyStage: Incorrect stage for this method");
    await expect(sale.withdraw(user.alice.address, 1)).to.be.revertedWith("SALE::onlyStage: Incorrect stage for this method");
  });
});

describe("Sale: Started", () => {
  beforeEach(async () => {
    c = await loadFixture(main);
    parent = c.parent;
    tidal = c.tidal;
    riptide = c.riptide;
    owner = c.owner;
    user = c.user;
    mock = c.mock;
    surf = c.surf;

    sale = await (await ethers.getContractFactory("contracts/Sale.sol:Sale")).deploy(
      tidal.address,
      riptide.address,
      surf.address, //mock.surf.address,
      mock.router.address,
      mock.surfEth.address,
      10,
      1, // start instantly for this test
      500
    );

    await tidal.transferOwnership(sale.address);
    await riptide.transferOwnership(sale.address);
  });

  it("Sale stage moved from 0 to 1 when someone buys after startBlock", async () => {
    expect(await sale.stage()).to.equal(0);
    //await mock.surf.mock.balanceOf.withArgs(owner.address).returns(1000);
    await surf.mint(owner.address, 1000);
    await sale.buyTokens(500, 0);
    expect(await sale.stage()).to.equal(1);
  });

  it("Buy tidal with surf", async () => {
    await surf.mint(owner.address, "5000000000000000000");
    await surf.approve(sale.address, "5000000000000000000");
    await sale.buyTokens("5000000000000000000", 0); // buy tidal with 5 surf
    const bal = await sale.balanceOf(owner.address, 0); // owed tidal
    // 5-(5*0.01)*0.00042
    const expected = "2079000000000000";
    expect(expected).to.equal(bal);
  });

  it("Buy tidal with ETH (via receive)", async () => {
    // 1 eth in, 500 surf out (*10**18)
    await mock.router.mock.swapETHForExactTokens.returns(
      [
        "1000000000000000000", // amount used in the sale
        "1000000000000000000", // intermediary balances if any (at least weth)
        "495000000000000000000" // tokens bought minus fee
      ]
    );
    await owner.sendTransaction({to: sale.address, value: ethers.BigNumber.from("1000000000000000000")});
    // 500-(500*0.01)*0.00042 = 0.2079
    const expected = "207900000000000000";
    const bal = await sale.balanceOf(owner.address, 0);
    expect(expected).to.equal(bal);
  });

  it("Partial refund because tidal cap has been hit", async () => {
    const surfAmount = "7000000000000000000000";
    await surf.mint(owner.address, surfAmount); // 7000 is close to max purchase per person (~7215 surf)
    await surf.approve(sale.address, surfAmount);
    await surf.mint(user.alice.address, surfAmount);
    await surf.connect(user.alice).approve(sale.address, surfAmount);
    await sale.connect(user.alice).buyTokens(surfAmount, 0);
    expect(await surf.balanceOf(user.alice.address)).to.equal(0);
    await sale.buyTokens(surfAmount, 0);
    const amountForSale = await sale.amountForSale();
    const tidalDetails = await sale.t(0);
    expect(await tidalDetails.sold).to.equal(amountForSale);
    const ownerOwed = await sale.balanceOf(owner.address, 0);
    const aliceOwed = await sale.balanceOf(user.alice.address, 0);
    expect(ownerOwed.add(aliceOwed)).to.equal(tidalDetails.sold);
    expect(await surf.balanceOf(owner.address)).to.equal("3898989898989898989899")
  });

  it("Buy riptide with surf (via method)", async () => {
    await surf.mint(owner.address, "5000000000000000000");
    await surf.approve(sale.address, "5000000000000000000");
    await sale.buyTokens("5000000000000000000", 1);
    const bal = await sale.balanceOf(owner.address, 1);
    // 5-(5*0.01)*0.00042
    const expected = "2079000000000000";
    expect(expected).to.equal(bal);
  });

  it("Buy riptide with ETH", async () => {
    // 1 eth in, 500 surf out (*10**18)
    await mock.router.mock.swapETHForExactTokens.returns(
      [
        "1000000000000000000", // amount used in the sale
        "1000000000000000000", // intermediary balances if any (at least weth)
        "495000000000000000000" // tokens bought minus fee
      ]
    );
    // buy the other way this time
    await sale.buyTokensWithEth(1, {value: ethers.BigNumber.from("1000000000000000000")});
    // 500-(500*0.01)*0.00042 = 0.2079
    const expected = "207900000000000000";
    const bal = await sale.balanceOf(owner.address, 1);
    expect(expected).to.equal(bal);
  });


  it("Partial refund because riptide cap has been hit", async () => {
    const surfAmount = "7000000000000000000000";
    await surf.mint(owner.address, surfAmount); // 7000 is close to max purchase per person (~7215 surf)
    await surf.approve(sale.address, surfAmount);
    await surf.mint(user.alice.address, surfAmount);
    await surf.connect(user.alice).approve(sale.address, surfAmount);
    await sale.connect(user.alice).buyTokens(surfAmount, 1);
    expect(await surf.balanceOf(user.alice.address)).to.equal(0);
    await sale.buyTokens(surfAmount, 1);
    const amountForSale = await sale.amountForSale();
    const riptideDetails = await sale.t(1);
    expect(await riptideDetails.sold).to.equal(amountForSale);
    const ownerOwed = await sale.balanceOf(owner.address, 1);
    const aliceOwed = await sale.balanceOf(user.alice.address, 1);
    expect(ownerOwed.add(aliceOwed)).to.equal(riptideDetails.sold);
    expect(await surf.balanceOf(owner.address)).to.equal("3898989898989898989899");
  });

  it("Maximum per user token limit enforced", async () => {
    const surfAmount = "10000000000000000000000";
    await surf.mint(owner.address, surfAmount);
    await surf.approve(sale.address, surfAmount);
    await sale.buyTokens(surfAmount, 0);
    expect(await sale.maxTokensPerUser()).to.equal(await sale.balanceOf(owner.address, 0));
    const surfBal = await surf.balanceOf(owner.address);
    await surf.mint(owner.address, surfAmount);
    await surf.approve(sale.address, surfAmount);
    await expect(sale.buyTokens(surfAmount, 0)).to.be.revertedWith("Purchase limit hit for this token for this user");
    expect(await surf.balanceOf(owner.address)).to.equal(surfBal.add(surfAmount));
  });

  it("Sale stage moved from 1 to 2 when both caps have been hit", async () => {
    const surfAmount = "10000000000000000000000";
    
    await surf.mint(owner.address, surfAmount);
    await surf.approve(sale.address, surfAmount);
    await sale.buyTokens(surfAmount, 0);
    await surf.mint(user.alice.address, surfAmount);
    await surf.connect(user.alice).approve(sale.address, surfAmount);
    await sale.connect(user.alice).buyTokens(surfAmount, 0);
    const tidalDetails = await sale.t(0);
    expect(tidalDetails.sold).to.equal(await sale.amountForSale());

    expect(await sale.stage()).to.equal(1);

    await surf.mint(owner.address, surfAmount);
    await surf.approve(sale.address, surfAmount);
    await sale.buyTokens(surfAmount, 1);
    await surf.mint(user.alice.address, surfAmount);
    await surf.connect(user.alice).approve(sale.address, surfAmount);
    await sale.connect(user.alice).buyTokens(surfAmount, 1);
    const riptideDetails = await sale.t(1);
    expect(riptideDetails.sold).to.equal(await sale.amountForSale());

    expect(await sale.stage()).to.equal(2);

  });


});

describe("Sale: Finished", () => {
  beforeEach(async () => {
    c = await loadFixture(main);
    parent = c.parent;
    tidal = c.tidal;
    riptide = c.riptide;
    owner = c.owner;
    user = c.user;
    mock = c.mock;
    surf = c.surf;

    sale = await (await ethers.getContractFactory("contracts/Sale.sol:Sale")).deploy(
      tidal.address,
      riptide.address,
      surf.address, //mock.surf.address,
      mock.router.address,
      mock.surfEth.address,
      10,
      1, // start instantly for this test
      2, // finish instantly for this test
    );

    await tidal.transferOwnership(sale.address);
    await riptide.transferOwnership(sale.address);
  });

  it("Sale stage moved from 1 to 2 when finishBlock has passed", async () => {
    await sale.buyTokens(0, 0);
    expect(await sale.stage()).to.equal(2);
    expect(parseInt(await ethers.provider.getBlockNumber())).to.be.at.least(await sale.finishBlock());
  });

  it("Sale can only be finalized at stage 2", async () => {
    await expect(sale.finalize()).to.be.revertedWith("SALE::onlyStage: Incorrect stage for this method");
    await sale.buyTokens(0, 0);
    expect(await sale.stage()).to.equal(2);
    await sale.finalize();
  });
});



describe("Sale: finalized", () => {
  beforeEach(async () => {
    c = await loadFixture(main);
    parent = c.parent;
    tidal = c.tidal;
    riptide = c.riptide;
    owner = c.owner;
    user = c.user;
    mock = c.mock;
    surf = c.surf;

    sale = await (await ethers.getContractFactory("contracts/Sale.sol:Sale")).deploy(
      tidal.address,
      riptide.address,
      surf.address, //mock.surf.address,
      mock.router.address,
      mock.surfEth.address,
      10,
      1, // start instantly for this test
      10, // finish quickly for this test
    );

    await tidal.transferOwnership(sale.address);
    await riptide.transferOwnership(sale.address);
  });

  it("Sale stage moved to 3 when finalized()", async () => {
    blockTo(10);
    await sale.buyTokens(0, 0);
    await sale.finalize();
    expect(await sale.stage()).to.equal(3);
  });

  it("Tokens can only be withdrawn in stage 3", async () => {
    blockTo(10);
    await expect(sale.withdraw(owner.address, 0)).to.be.revertedWith("SALE::onlyStage: Incorrect stage for this method");
    await expect(sale.withdraw(owner.address, 1)).to.be.revertedWith("SALE::onlyStage: Incorrect stage for this method");
    await sale.buyTokens(0, 0);
    await sale.finalize();
    await sale.withdraw(owner.address, 0);
    await sale.withdraw(owner.address, 1);
  });

  it("Tokens can only be withdrawn once", async () => {

    // whitelist sale address for this test?

    const surfAmount = "10000000000000000000000";
    await surf.mint(owner.address, surfAmount);
    await surf.approve(sale.address, surfAmount);
    await sale.buyTokens(surfAmount, 0);
    blockTo(10);
    await sale.buyTokens(0, 0);
    await sale.finalize();
    expect(await tidal.balanceOf(owner.address)).to.equal(0);
    const expected = await sale.balanceOf(owner.address);
    await sale.withdraw(owner.address, 0);
    expect(await tidal.balanceOf(owner.address)).to.equal(expected); // or minus fee? sale should be whitelisted
    await sale.withdraw(owner.address, 0);
    expect(await tidal.balanceOf(owner.address)).to.equal(expected);
  });

  it("Token ownerships can only be transferred in stage 3", async () => {
    blockTo(10);
    await expect(sale.transferTokenOwnerships(user.alice.address)).to.be.revertedWith("SALE::onlyStage: Incorrect stage for this method");
    await sale.buyTokens(0, 0);
    await sale.finalize();
    expect(await sale.stage()).to.equal(3);
    await sale.transferTokenOwnerships(user.alice.address);
  });


})

