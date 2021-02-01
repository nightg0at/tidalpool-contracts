const { expect } = require("chai");
const { waffle, ethers } = require("hardhat");
const { loadFixture } = waffle;
const provider = waffle.provider;
const { isCallTrace } = require("hardhat/internal/hardhat-network/stack-traces/message-trace");
const { Contract } = require("ethers");
const { deployContract, link, deployMockContract } = require("ethereum-waffle");

const zeroAddr = "0x0000000000000000000000000000000000000000";

async function blockTravel(blocks, verbose = false) {
  if (verbose) {
    let blockNumber = await ethers.provider.getBlockNumber();
    console.log("block:", blockNumber);
    console.log("travelling", blocks, "blocks");
  }
  Array.from({length: blocks}, async () => {
    await ethers.provider.send("evm_increaseTime", [60])   // add 60 seconds
    await ethers.provider.send("evm_mine")      // mine the next block
  });
  if (verbose) {
    blockNumber = await ethers.provider.getBlockNumber();
    console.log("block:", blockNumber);
  }
}

async function blockTo(endBlock, verbose = false) {
  if (verbose) console.log("block:", (await ethers.provider.getBlockNumber()));
  while ((await ethers.provider.getBlockNumber() < endBlock)) {
    await ethers.provider.send("evm_increaseTime", [60]);
    await ethers.provider.send("evm_mine");
  }
  if (verbose) console.log("block:", (await ethers.provider.getBlockNumber()));  
}

function nice(thing) {
  let name = Object.keys(thing)[0];
  let val = thing[name];
  console.log(`${name}: ${ethers.utils.formatEther(val)} (${val})`);
}


async function fixture(provider) {

  const wallets = await ethers.getSigners();
  const owner = {
    tide: wallets[0],
    pickle: wallets[1],
    drc: wallets[2],
    farm: wallets[3],
    nice: wallets[4],
    rotten: wallets[5]
  };

  const user = {
    alice: wallets[6],
    bob: wallets[7],
    carol: wallets[8]
  }

  const mock = {
    poseidon: await deployMockContract(
      owner.tide,
      require("../artifacts/contracts/Poseidon.sol/Poseidon.json").abi
    ),
    registry: await deployMockContract(
      owner.tide,
      require("../artifacts/@openzeppelin/contracts/introspection/IERC1820Registry.sol/IERC1820Registry.json").abi
    ),
    router: await deployMockContract(
      owner.tide,
      require("../artifacts/@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol/IUniswapV2Router02.json").abi
    )
  }

  const Parent = await ethers.getContractFactory("contracts/TideParent.sol:TideParent");
  const parent = await Parent.deploy(mock.registry.address);

  const generic = [
    await (await ethers.getContractFactory("contracts/dummies/erc20.sol:Generic")).deploy("zero"),
    await (await ethers.getContractFactory("contracts/dummies/erc20.sol:Generic")).deploy("one"),
    await (await ethers.getContractFactory("contracts/dummies/erc20.sol:Generic")).deploy("two"),
    await (await ethers.getContractFactory("contracts/dummies/erc20.sol:Generic")).deploy("three"),
    await (await ethers.getContractFactory("contracts/dummies/erc20.sol:Generic")).deploy("four"),
    await (await ethers.getContractFactory("contracts/dummies/erc20.sol:Generic")).deploy("five"),
  ]

  const Token = await ethers.getContractFactory("contracts/TideToken.sol:TideToken");

  const token = {
    tidal: await Token.deploy("Tidal Token", "TIDAL", parent.address),
    riptide: await Token.deploy("Riptide Token", "RIPTIDE", parent.address),
    boon: await (await ethers.getContractFactory("contracts/BoonToken.sol:BoonToken")).deploy(),
    parent: parent,
    pickle: await (await ethers.getContractFactory("Pickle")).deploy(),
    drc: await (await ethers.getContractFactory("Dracula")).deploy(),
    farm: await (await ethers.getContractFactory("Farm")).deploy(),
    nice: await (await ethers.getContractFactory("NiceToken")).deploy(),
    rotten: null, // implemented elsewhere
    maggot: null, // implemented elsewhere
  }

  const lp = {
    poseidon: await (await ethers.getContractFactory("contracts/dummies/UniswapV2Pair.sol:UniswapV2Pair")).deploy(),
    pickle: await (await ethers.getContractFactory("PickleLP")).deploy(),
    drc: await (await ethers.getContractFactory("DraculaLP")).deploy(),
    farm: await (await ethers.getContractFactory("FarmLP")).deploy(),
    nice: await (await ethers.getContractFactory("NiceLP")).deploy(),
    rotten: await (await ethers.getContractFactory("RottenLP")).deploy()
  }

  const Poseidon = await ethers.getContractFactory("contracts/Poseidon.sol:Poseidon");
  const poseidon = await (Poseidon).deploy(
    mock.router.address,
    token.tidal.address,
    token.riptide.address,
    token.boon.address,
    generic[5].address, // mock surf
    "0x999b1e6EDCb412b59ECF0C5e14c20948Ce81F40b",
    owner.tide.address,
    1
  );

  await token.tidal.transferOwnership(poseidon.address);
  await token.riptide.transferOwnership(poseidon.address);

  await token.parent.setAddresses(token.tidal.address, token.riptide.address, poseidon.address);

  const PickleFarm = await ethers.getContractFactory("contracts/dummies/pickleFarm.sol:MasterChef");
  const pickleFarm = await (PickleFarm).connect(owner.pickle).deploy(
    token.pickle.address,
    owner.pickle.address,
    ethers.utils.parseEther("1"),
    1,
    2
  );

  // make pickleFarm the owner of pickleToken
  await token.pickle.transferOwnership(pickleFarm.address);
  // add the dummy PICKLE/ETH pool to pickleFarm
  await pickleFarm.connect(owner.pickle).add(1, lp.pickle.address, 1);


  const DraculaFarm = await ethers.getContractFactory("MasterVampire");
  const draculaFarm = await (DraculaFarm).connect(owner.drc).deploy(
    token.drc.address,
    zeroAddr,
    lp.drc.address
  );

  // make draculaFarm the owner of drc
  await token.drc.transferOwnership(draculaFarm.address);
  // add the dummy pid. Contract then uses lp.drc given in constructor
  await draculaFarm.connect(owner.drc).add(zeroAddr, 0, ethers.utils.parseEther("20"), 0, 0);

  const HarvestFarm = await ethers.getContractFactory("NoMintRewardPool");
  const harvestFarm = await (HarvestFarm).connect(owner.farm).deploy(
    token.farm.address,
    lp.farm.address,
    604800,
    owner.farm.address,
    owner.farm.address,
    //harvestStorage.address
  );


  await token.farm.mint(harvestFarm.address, ethers.utils.parseEther("100000"));
  await harvestFarm.connect(owner.farm).notifyRewardAmount(ethers.utils.parseEther("100000"));
  

  const PoliceChief = await ethers.getContractFactory("PoliceChief");
  const policeChief = await (PoliceChief).connect(owner.nice).deploy(
    token.nice.address,
    owner.nice.address,
    ethers.utils.parseEther("2"),
    1,
    2
  );

  await token.nice.transferOwnership(policeChief.address);
  await policeChief.connect(owner.nice).add(1, lp.nice.address, 1);


  token.maggot = await (await ethers.getContractFactory("MaggotToken")).deploy(owner.rotten.address);
  token.rotten = await (await ethers.getContractFactory("RottenToken")).deploy(token.maggot.address, 100);

  const ZombieChef = await ethers.getContractFactory("ZombieChef");
  const zombieChef = await (ZombieChef).connect(owner.rotten).deploy(
    token.rotten.address,
    ethers.utils.parseEther("1.5"),
    1,
    2
  );

  await token.rotten.transferOwnership(zombieChef.address);
  await token.maggot.transferOwnership(token.rotten.address);
  await zombieChef.connect(owner.rotten).add(1, lp.rotten.address, 1);

  const farm = {
    poseidon: poseidon,
    pickle: pickleFarm,
    drc: draculaFarm,
    harvest: harvestFarm,
    nice: policeChief,
    rotten: zombieChef
  };


  const PickleAdapter = await ethers.getContractFactory("PickleAdapter");
  const pickleAdapter = await (PickleAdapter).deploy(
    farm.pickle.address,
    lp.pickle.address,
    token.pickle.address,
    farm.poseidon.address,
    0
  );

  const DraculaAdapter = await ethers.getContractFactory("DraculaAdapter");
  const draculaAdapter = await (DraculaAdapter).deploy(
    farm.drc.address,
    lp.drc.address,
    token.drc.address,
    farm.poseidon.address,
    0
  );

  const HarvestAdapter = await ethers.getContractFactory("HarvestAdapter");
  const harvestAdapter = await (HarvestAdapter).deploy(
    farm.harvest.address,
    lp.farm.address,
    token.farm.address,
    farm.poseidon.address
  );


  const NiceAdapter = await ethers.getContractFactory("NiceAdapter");
  const niceAdapter = await (NiceAdapter).deploy(
    farm.nice.address,
    lp.nice.address,
    token.nice.address,
    farm.poseidon.address,
    0
  );

  const RottenAdapter = await ethers.getContractFactory("RottenAdapter");
  const rottenAdapter = await (RottenAdapter).deploy(
    farm.rotten.address,
    lp.rotten.address,
    token.rotten.address,
    farm.poseidon.address,
    0
  )

  const adapter = {
    pickle: pickleAdapter,
    drc: draculaAdapter,
    harvest: harvestAdapter,
    nice: niceAdapter,
    rotten: rottenAdapter
  };

  return {owner, user, token, lp, farm, adapter};
}

let owner, user, token, lp, farm, adapter;


describe("Preliminary MasterChef checks", () => {

  beforeEach(async () => {
    c = await loadFixture(fixture);
    owner = c.owner;
    user = c.user;
    token = c.token;
    lp = c.lp;
    farm = c.farm;
    adapter = c.adapter;
  });   

  it("Tidal token initial supply is 0", async () => {
    expect(await token.tidal.totalSupply()).to.equal(0);
  });

  it("MasterChef is Tidal owner", async () => {
    expect(await token.tidal.owner()).to.equal(farm.poseidon.address);
  });

  it("Riptide token initial supply is 0", async () => {
    expect(await token.riptide.totalSupply()).to.equal(0);
  });

  it("MasterChef is Riptide owner", async () => {
    expect(await token.riptide.owner()).to.equal(farm.poseidon.address);
  });
});


const adapterTypes = [
  {
    style: "MasterChef",
    name: "pickle.finance",
    token: "pickle",
    farm: "pickle"
  },
  {
    style: "MasterChef",
    name: "dracula.sucks",
    token: "drc",
    farm: "drc"
  },
  {
    style: "StakingRewards",
    name: "harvest.finance",
    token: "farm",
    farm: "harvest",
    removePrecision: 10000000 // precision errors present in StakingRewards-like contracts
  },
  {
    style: "MasterChef",
    name: "niceee",
    token: "nice",
    farm: "nice",
    removePrecision: 10000000000 // there's a burn fee that we will skirt around
  },
  {
    style: "MasterChef",
    name: "rottenswap",
    token: "rotten",
    farm: "rotten",
    removePrecision: 10000000000 // there's a burn fee that we will skirt around
  }
];


for (const a of adapterTypes) {
  //console.log(a);
  adapterTest(a);
}

function adapterTest(a) {
  describe(`${a.style} style adapter (${a.name})`, () => {
    let startBlock;
    beforeEach(async () => {
      c = await loadFixture(fixture);
      owner = c.owner;
      user = c.user;
      token = c.token;
      lp = c.lp;
      farm = c.farm;
      adapter = c.adapter;
    });

    it("Init", async () => {
      startBlock = await ethers.provider.getBlockNumber();
      //console.log("starting block: ", startBlock);
    });
 
    it("Adapter attribute check", async () => {
      expect(await adapter[a.farm].lpTokenAddress()).to.equal(lp[a.token].address);
      expect(await adapter[a.farm].rewardTokenAddress()).to.equal(token[a.token].address);
      expect(await adapter[a.farm].home()).to.equal(farm.poseidon.address);
      expect(await adapter[a.farm].target()).to.equal(farm[a.farm].address);
    });
  
    it("New restaking pool: Adapter added to MasterChef", async () => {
      expect(await farm.poseidon.poolLength()).to.equal(1);
      await farm.poseidon.addWithRestaking(1, 0, true, adapter[a.farm].address);
      expect(await farm.poseidon.poolLength()).to.equal(2);
  
      const pool = await farm.poseidon.poolInfo(1);
      expect(pool.lpToken).to.equal(lp[a.token].address);
      expect(pool.adapter).to.equal(adapter[a.farm].address);
      expect(pool.otherToken).to.equal(token[a.token].address);
    });
  
    it("New normal pool: Changed to restaking pool", async () => {
      await farm.poseidon.add(1, lp[a.token].address, 0, true);
      const poolBefore = await farm.poseidon.poolInfo(1);
      expect(poolBefore.lpToken).to.equal(lp[a.token].address);
      expect(poolBefore.adapter).to.equal(zeroAddr);
      expect(poolBefore.otherToken).to.equal(zeroAddr);
  
      await farm.poseidon.setRestaking(1, adapter[a.farm].address, true);
  
      const poolAfter = await farm.poseidon.poolInfo(1);
      expect(poolAfter.lpToken).to.equal(lp[a.token].address);
      expect(poolAfter.adapter).to.equal(adapter[a.farm].address);
      expect(poolAfter.otherToken).to.equal(token[a.token].address);
  
    });

    it("Restaking pool: Changed to normal with correct rewards", async () => {
      await farm.poseidon.addWithRestaking(1, 0, true, adapter[a.farm].address);

      await lp[a.token].transfer(user.alice.address, 1000);
      await lp[a.token].connect(user.alice).approve(farm.poseidon.address, 1000);
      await farm.poseidon.connect(user.alice).deposit(1, 1000);

      expect(await token.tidal.balanceOf(user.alice.address)).to.equal(0);
      expect(await token[a.token].balanceOf(user.alice.address)).to.equal(0);
      
      await blockTravel(5);
      await farm.poseidon.removeRestaking(1, true);
      await farm.poseidon.connect(user.alice).withdraw(1, 0);

      const tidalBal = await token.tidal.balanceOf(user.alice.address);
      const otherBal = await token[a.token].balanceOf(user.alice.address);
      await blockTravel(5);
      await farm.poseidon.connect(user.alice).withdraw(1, 1000);
      const tidalNewBal = await token.tidal.balanceOf(user.alice.address);
      const otherNewBal = await token[a.token].balanceOf(user.alice.address);

      expect(tidalBal).to.lt(tidalNewBal);
      expect(otherBal).to.equal(otherNewBal);
      expect(otherBal).to.gt(0);

    });

    it("Restaking pool: Changed to new restaking pool with correct rewards", async () => {
      await farm.poseidon.addWithRestaking(1, 0, true, adapter[a.farm].address);

      await lp[a.token].transfer(user.alice.address, 1000);
      await lp[a.token].connect(user.alice).approve(farm.poseidon.address, 1000);
      await farm.poseidon.connect(user.alice).deposit(1, 1000);

      expect(await token.tidal.balanceOf(user.alice.address)).to.equal(0);
      expect(await token[a.token].balanceOf(user.alice.address)).to.equal(0);
      
      await blockTravel(5);
      await farm.poseidon.setRestaking(1, adapter[a.farm].address, true);
      await farm.poseidon.connect(user.alice).withdraw(1, 0);

      const tidalBal = await token.tidal.balanceOf(user.alice.address);
      const otherBal = await token[a.token].balanceOf(user.alice.address);
      await blockTravel(5);
      await farm.poseidon.connect(user.alice).withdraw(1, 0);
      const tidalNewBal = await token.tidal.balanceOf(user.alice.address);
      const otherNewBal = await token[a.token].balanceOf(user.alice.address);
      
      expect(tidalBal).to.lt(tidalNewBal);
      expect(otherBal).to.lt(otherNewBal);

    });
  
    it("Restake deposit & withdraw: Correct LP token locations", async () => {
      await farm.poseidon.addWithRestaking(1, 0, true, adapter[a.farm].address);
      await lp[a.token].transfer(user.alice.address, 1000);
  
      expect(await lp[a.token].balanceOf(user.alice.address)).to.equal(1000);
      expect(await lp[a.token].balanceOf(adapter[a.farm].address)).to.equal(0);
      expect(await lp[a.token].balanceOf(farm[a.farm].address)).to.equal(0);
      expect(await lp[a.token].balanceOf(farm.poseidon.address)).to.equal(0);
  
      await lp[a.token].connect(user.alice).approve(farm.poseidon.address, 1000);
      await farm.poseidon.connect(user.alice).deposit(1, 1000);
  
      expect(await lp[a.token].balanceOf(user.alice.address)).to.equal(0);
      expect(await lp[a.token].balanceOf(adapter[a.farm].address)).to.equal(0);
      expect(await lp[a.token].balanceOf(farm[a.farm].address)).to.equal(1000);
      expect(await lp[a.token].balanceOf(farm.poseidon.address)).to.equal(0);
  
      await farm.poseidon.connect(user.alice).withdraw(1, 1000);
  
      expect(await lp[a.token].balanceOf(user.alice.address)).to.equal(1000);
      expect(await lp[a.token].balanceOf(adapter[a.farm].address)).to.equal(0);
      expect(await lp[a.token].balanceOf(farm[a.farm].address)).to.equal(0);
      expect(await lp[a.token].balanceOf(farm.poseidon.address)).to.equal(0);
    });
  
    it("Restake deposit: Withdraw all", async () => {
      await farm.poseidon.addWithRestaking(1, 0, true, adapter[a.farm].address);
  
      await lp[a.token].transfer(user.alice.address, 1000);
      expect(await lp[a.token].balanceOf(user.alice.address)).to.equal(1000);
  
      const userInfoBeforeDeposit = await farm.poseidon.userInfo(1, user.alice.address);
      expect(userInfoBeforeDeposit.amount).to.equal(0);
  
      await lp[a.token].connect(user.alice).approve(farm.poseidon.address, 1000);
      await farm.poseidon.connect(user.alice).deposit(1, 1000);
      const userInfoAtDeposit = await farm.poseidon.userInfo(1, user.alice.address);
      expect(userInfoAtDeposit.amount).to.equal(1000);
      expect(await lp[a.token].balanceOf(user.alice.address)).to.equal(0);
  
      await farm.poseidon.connect(user.alice).withdraw(1, 1000);
      const userInfoAfterWithdraw = await farm.poseidon.userInfo(1, user.alice.address);
      expect(userInfoAfterWithdraw.amount).to.equal(0);
      expect(await lp[a.token].balanceOf(user.alice.address)).to.equal(1000);
    });
  
    it("Restake deposit: Withdraw some", async () => {
      await farm.poseidon.addWithRestaking(1, 0, true, adapter[a.farm].address);
  
      await lp[a.token].transfer(user.alice.address, 1000);
      expect(await lp[a.token].balanceOf(user.alice.address)).to.equal(1000);
  
      const userInfoBeforeDeposit = await farm.poseidon.userInfo(1, user.alice.address);
      expect(userInfoBeforeDeposit.amount).to.equal(0);
  
      await lp[a.token].connect(user.alice).approve(farm.poseidon.address, 1000);
      await farm.poseidon.connect(user.alice).deposit(1, 1000);
      const userInfoAtDeposit = await farm.poseidon.userInfo(1, user.alice.address);
      expect(userInfoAtDeposit.amount).to.equal(1000);
      expect(await lp[a.token].balanceOf(user.alice.address)).to.equal(0);
  
      await farm.poseidon.connect(user.alice).withdraw(1, 500);
      const userInfoAfterWithdraw = await farm.poseidon.userInfo(1, user.alice.address);
      expect(userInfoAfterWithdraw.amount).to.equal(500);
      expect(await lp[a.token].balanceOf(user.alice.address)).to.equal(500);
    });

    it("Restake deposit: Cannot withdraw more than deposit", async () => {
      await farm.poseidon.addWithRestaking(1, 0, true, adapter[a.farm].address);
  
      await lp[a.token].transfer(user.alice.address, 1000);
      expect(await lp[a.token].balanceOf(user.alice.address)).to.equal(1000);
  
      const userInfoBeforeDeposit = await farm.poseidon.userInfo(1, user.alice.address);
      expect(userInfoBeforeDeposit.amount).to.equal(0);
  
      await lp[a.token].connect(user.alice).approve(farm.poseidon.address, 1000);
      await farm.poseidon.connect(user.alice).deposit(1, 1000);
      
      const userInfoAtDeposit = await farm.poseidon.userInfo(1, user.alice.address);
      expect(userInfoAtDeposit.amount).to.equal(1000);
      expect(await lp[a.token].balanceOf(user.alice.address)).to.equal(0);
  
      await expect(farm.poseidon.connect(user.alice).withdraw(1, 1001)).to.be.revertedWith("withdraw: not good");
      const userInfoAfterWithdraw = await farm.poseidon.userInfo(1, user.alice.address);
      expect(userInfoAfterWithdraw.amount).to.equal(1000);
      expect(await lp[a.token].balanceOf(user.alice.address)).to.equal(0);
  
    });

    it(`Pending ${a.token} reward passthrough from target`, async () => {
      await farm.poseidon.addWithRestaking(1, 0, true, adapter[a.farm].address);
  
      await lp[a.token].transfer(user.alice.address, 1000);
      expect(await lp[a.token].balanceOf(user.alice.address)).to.equal(1000);
  
      await lp[a.token].connect(user.alice).approve(farm.poseidon.address, 1000)
      await farm.poseidon.connect(user.alice).deposit(1, 1000);
      const userInfoAtDeposit = await farm.poseidon.userInfo(1, user.alice.address);
      expect(userInfoAtDeposit.amount).to.equal(1000);
      expect(await farm.poseidon.pendingOther(1, user.alice.address)).to.equal(0);

      const depositBlock = await ethers.provider.getBlockNumber();
      const blockSpan = 10;
      await blockTo(depositBlock + blockSpan);
      const currentBlock = await ethers.provider.getBlockNumber();
      expect(depositBlock + blockSpan).to.equal(currentBlock);

      const targetRewards = await adapter[a.farm].pending();
      // should hold because we're the only staker
      //console.log(await farm.poseidon.pendingOther(0, user.alice.address));
      expect(targetRewards).to.gt(ethers.BigNumber.from("0"));
      expect(await farm.poseidon.pendingOther(1, user.alice.address)).to.equal(targetRewards);
    });

    it(`Stakers receive tidal and ${a.token} in equal proportions`, async () => {
      await farm.poseidon.addWithRestaking(1, 0, true, adapter[a.farm].address);

      // alice: 50%, bob: 30% carol: 20%
      await lp[a.token].transfer(user.alice.address, 500);
      await lp[a.token].transfer(user.bob.address, 300);
      await lp[a.token].transfer(user.carol.address, 200);
      await lp[a.token].connect(user.alice).approve(farm.poseidon.address, 500);
      await lp[a.token].connect(user.bob).approve(farm.poseidon.address, 300);
      await lp[a.token].connect(user.carol).approve(farm.poseidon.address, 200);
  
      await blockTo(startBlock + 50);
      await farm.poseidon.connect(user.alice).deposit(1, 500);
      await blockTo(startBlock + 100);
      await farm.poseidon.connect(user.bob).deposit(1, 300);
      await blockTo(startBlock + 150);
      await farm.poseidon.connect(user.carol).deposit(1, 200);


      // alice claims and withdraws
      await blockTo(startBlock + 1199);
      //await farm.poseidon.updatePool(0);
      await farm.poseidon.connect(user.alice).withdraw(1, 500);
      let poolInfo = await farm.poseidon.poolInfo(1);
      //console.log(poolInfo);
      let tidalBal = await token.tidal.balanceOf(user.alice.address);
      let otherBal = await token[a.token].balanceOf(user.alice.address);
      let tidalFraction = poolInfo.accTidalPerShare.div(tidalBal);
      let otherFraction = poolInfo.accOtherPerShare.div(otherBal);
      
      /*
      console.log("tidal bal:", tidalBal, ethers.utils.formatEther(tidalBal));
      console.log("accTidalPerShare:", poolInfo.accTidalPerShare, ethers.utils.formatEther(poolInfo.accTidalPerShare));
      console.log("tidal fraction:", tidalFraction, ethers.utils.formatEther(tidalFraction));
      console.log("other bal:", otherBal, ethers.utils.formatEther(otherBal));
      console.log("accOtherPerShare:", poolInfo.accOtherPerShare, ethers.utils.formatEther(poolInfo.accOtherPerShare));
      console.log("other fraction", otherFraction, ethers.utils.formatEther(otherFraction));
      */

      a.style == "StakingRewards" || a.farm == "nice" || a.farm == "rotten"
        ? expect(parseInt(tidalFraction)).to.be.closeTo(parseInt(otherFraction), a.removePrecision)
        : expect(tidalFraction).to.equal(otherFraction);
      

      // bob claims
      await blockTo(startBlock + 1399);
      await farm.poseidon.updatePool(1);
      poolInfo = await farm.poseidon.poolInfo(1);
      await farm.poseidon.connect(user.bob).withdraw(1, 0);
      tidalBal = await token.tidal.balanceOf(user.bob.address);
      otherBal = await token[a.token].balanceOf(user.bob.address);
      tidalFraction = poolInfo.accTidalPerShare.div(tidalBal);
      otherFraction = poolInfo.accOtherPerShare.div(otherBal);

      a.style == "StakingRewards" || a.farm == "nice" || a.farm == "rotten"
        ? expect(parseInt(tidalFraction)).to.be.closeTo(parseInt(otherFraction), a.removePrecision)
        : expect(tidalFraction).to.equal(otherFraction);


      // carol claims and withdraws
      await blockTo(startBlock + 1699);
      await farm.poseidon.updatePool(1);
      poolInfo = await farm.poseidon.poolInfo(1);
      await farm.poseidon.connect(user.carol).withdraw(1, 200);
      tidalBal = await token.tidal.balanceOf(user.carol.address);
      otherBal = await token[a.token].balanceOf(user.carol.address);
      tidalFraction = poolInfo.accTidalPerShare.div(tidalBal);
      otherFraction = poolInfo.accOtherPerShare.div(otherBal);

      a.style == "StakingRewards" || a.farm == "nice" || a.farm == "rotten"
        ? expect(parseInt(tidalFraction)).to.be.closeTo(parseInt(otherFraction), a.removePrecision)
        : expect(tidalFraction).to.equal(otherFraction);

    });

    it("Restake deposit & emergency withdraw", async () => {
      await farm.poseidon.addWithRestaking(1, 0, true, adapter[a.farm].address);

      await lp[a.token].transfer(user.alice.address, 1000);
      expect(await lp[a.token].balanceOf(user.alice.address)).to.equal(1000);

      await lp[a.token].connect(user.alice).approve(farm.poseidon.address, 1000)
      await farm.poseidon.connect(user.alice).deposit(1, 1000);

      await blockTravel(5);

      expect(await farm.poseidon.pendingOther(1, user.alice.address)).to.gt(ethers.BigNumber.from("0"));
      expect(await token[a.token].balanceOf(user.alice.address)).to.equal(0);
      expect(await lp[a.token].balanceOf(user.alice.address)).to.equal(0);

      await farm.poseidon.connect(user.alice).emergencyWithdraw(1);

      expect(await farm.poseidon.pendingOther(1, user.alice.address)).to.equal(0);
      expect(await token[a.token].balanceOf(user.alice.address)).to.equal(0);
      expect(await lp[a.token].balanceOf(user.alice.address)).to.equal(1000);
    });


  });
}
