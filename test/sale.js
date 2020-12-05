const { expect } = require("chai");
const { waffle, ethers } = require("hardhat");
const { loadFixture } = waffle;
const provider = waffle.provider;
const { isCallTrace } = require("hardhat/internal/hardhat-network/stack-traces/message-trace");

describe("Sale", () => {
  async function fixture(provider) {
    const Token = await ethers.getContractFactory("contracts/TidalToken.sol:TidalToken");
    const token = await Token.deploy();

    const params = {
      tokenAddress: token.address,
      amountForSale: ethers.utils.parseEther("4.2"),
      ETHRaise: ethers.utils.parseEther("12.6"),
      maxSpend: ethers.utils.parseEther("1")
    };

    const Sale = await ethers.getContractFactory("contracts/Sale.sol:Sale");    
    const sale = await Sale.deploy(
      params.tokenAddress,
      params.amountForSale,
      params.ETHRaise,
      params.maxSpend
    );


    const accounts = await ethers.getSigners();

    /*
    for (const account of accounts) {
      console.log(account.address);
    }*/

    return {token, sale, params, accounts}
  }
  
  it("Token total supply of 0", async function() {
    const {token} = await loadFixture(fixture);
    expect(await token.totalSupply()).to.equal(0);
  });

  it("Sale at stage 0", async function() {
    const {sale} = await loadFixture(fixture);
    expect(await sale.stage()).to.equal(0);
  });

  it("Sale contract is the owner of the token", async function() {
    const {token, sale, params} = await loadFixture(fixture);
    await token.transferOwnership(sale.address);
    expect(await token.owner()).to.equal(sale.address);
  });

  it("Cannot buy tokens yet", async function() {
    const {sale, accounts} = await loadFixture(fixture);
    //console.log(await sale.finishBlock());
    //console.log(await sale.buyTokens())
    await expect(sale.buyTokens({value: 100000000})).to.be.revertedWith('incorrect sale stage');
  })


});
