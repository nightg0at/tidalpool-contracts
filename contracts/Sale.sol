/*
  Tidalpool presale

  @nightg0at
  SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./libraries/UniswapV2Library.sol";
import "./ds-math/math.sol";
import "./TideToken.sol";

import "hardhat/console.sol";

contract Sale is Ownable, ReentrancyGuard, DSMath {

  struct TokenInfo {
    TideToken token;
    uint sold;
    mapping(address => uint) balance;
  }

  IERC20 public surf;
  address public surfEth; // uniswap pair
  IUniswapV2Router02 public router;
  TokenInfo[2] public t;

  uint public delayWarning;
  uint public startBlock;
  uint public finishBlock;

  uint public amountForSale = 42e17; // 4.2 of tidal and riptide each
  uint public SurfRaise = 1e22; // 10k surf in total
  uint public rate = wdiv(amountForSale, SurfRaise);
  uint public maxTokensPerUser =  3e18; // 3 for dev, but TBC
  uint public constant INVERSE_SURF_FEE_PERCENT = 99e16; // the inverse of the 1% surf transfer fee

  /*
    0: not started
    1: started
    2: finished
    3: finalized

  */
  uint public stage = 0;


  event BuyTokens(address indexed buyer, address indexed token, uint amount);
  event Withdraw(address indexed buyer, address indexed token, uint amount);

  constructor(
    TideToken _tidal,
    TideToken _riptide,
    IERC20 _surf,
    IUniswapV2Router02 _router,
    address _surfETH,
    uint _delayWarning, // 6500 is 1 day
    uint _startBlock,
    uint _finishBlock
  ) public {
    t[0] = TokenInfo(_tidal, 0);
    t[1] = TokenInfo(_riptide, 0);
    surf = _surf;
    router = _router;
    surfEth = _surfETH; //UniswapV2Library.pairFor(router.factory(), router.WETH(), address(surf));
    delayWarning = _delayWarning;
    startBlock = _startBlock;
    finishBlock = _finishBlock;
  }

  modifier onlyStage(uint _stage) {
    require(stage == _stage, "SALE::onlyStage: Incorrect stage for this method");
    _;
  }

  modifier lessThanStage(uint _stage) {
    require(stage < _stage, "SALE::lessThanStage: Stage too high for this method");
    _;
  }

  receive() external payable {
    // ignore the router, it might be refunding some change
    if (msg.sender != address(router)) {
      // buy the most available token if ETH is sent with no data
      // defaults to tidal if equally available
      t[1].sold < t[0].sold ? buyTokensWithEth(1) : buyTokensWithEth(0);
    }
  }


  function startAt(uint _startBlock) public onlyOwner onlyStage(0) {
    require(_startBlock > block.number + delayWarning, "SALE::startAt: Not enough warning"); // minimum warning ~1 day
    startBlock = _startBlock;
  }


  function finishAt(uint _finishBlock) public onlyOwner lessThanStage(2) {
    require(_finishBlock > block.number + delayWarning, "SALE::finishAt: Not enough warning"); // minimum warning ~1 day
    finishBlock = _finishBlock;
  }


  function startFinishAt(uint _startBlock, uint _finishBlock) public {
    startAt(_startBlock);
    finishAt(_finishBlock);
  }


  function buyTokensWithEth(uint _tid) public nonReentrant payable lessThanStage(2) {
    if (finishBlock <= block.number) {
      _finish();
      return;
    }

    if (stage == 0 && startBlock <= block.number) {
      stage = 1;
    }

    require(stage == 1, "SALE:buyTokensWithEth: Sale not started");

    address[] memory surfPath = new address[](2);
    surfPath[0] = router.WETH();
    surfPath[1] = address(surf);
    
    uint outputEstimate = UniswapV2Library.getAmountOut(
      msg.value,
      IERC20(router.WETH()).balanceOf(surfEth),
      surf.balanceOf(surfEth)
    );
    //console.log("surf::buyTokensWithEth:outputEstimate: %s", outputEstimate);
    uint surfDesired = _buyPrep(outputEstimate, _tid);
    //console.log("surf::buyTokensWithEth:surfDesired: %s", surfDesired);

    uint[] memory amounts = router.swapETHForExactTokens{value: msg.value}(
      surfDesired,
      surfPath,
      address(this),
      block.timestamp
    );

    // refund dust
    //console.log("sale::buyTokensWithEth:msg.value: %s", msg.value);
    //console.log("sale::buyTokensWithEth:amounts[0]: %s", amounts[0]);
    if (msg.value > amounts[0]) msg.sender.transfer(sub(msg.value, amounts[0]));

    uint surfAmount = amounts[amounts.length - 1];
    //console.log("sale::buyTokensWithEth:surfAmount: %s (to be sent to _buyTokens())", surfAmount);
    _buyTokens(surfAmount, _tid);
  }


  function buyTokens(uint _surfAmount, uint _tid) public nonReentrant lessThanStage(2) {
    if (finishBlock <= block.number) {
      _finish();
      return;
    }
    
    if (stage == 0 && startBlock <= block.number) {
      stage = 1;
    }

    require(stage == 1, "SALE:buyTokens: Sale not started");

  
    uint surfAmount = _buyPrep(_surfAmount, _tid);
    //console.log("buyTokens: surfAmount: %s", surfAmount);
    uint surfBalBefore = surf.balanceOf(address(this));
    //console.log("buyTokens: balanceOf(msg.sender): %s", surf.balanceOf(msg.sender));
    surf.transferFrom(msg.sender, address(this), surfAmount);
    uint surfBalAfter = surf.balanceOf(address(this));
    surfAmount = sub(surfBalAfter, surfBalBefore);
    _buyTokens(surfAmount, _tid);
  }


  function _buyPrep(uint _surfAmount, uint _tid) internal view returns (uint) {
    //console.log("161 _buyPrep: _surfAmount: %s", _surfAmount);
    uint surfAmount = _minusTransferFee(_surfAmount);
    //console.log("163 _buyPrep: surfAmount: %s", surfAmount);
    //console.log("164 _buyPrep: rate: %s", rate);
    uint tokenAmount = wmul(surfAmount, rate);
    //console.log("166 _buyPrep: tokenAmount: %s", tokenAmount);
    // remaining tokens ceiling
    if (sub(amountForSale, t[_tid].sold) < tokenAmount) {
      tokenAmount = sub(amountForSale, t[_tid].sold);
    }
    //console.log("171 _buyPrep: tokenAmount: %s", tokenAmount);
    // spending limit ceiling
    uint tokenBalanceAfterBuy = add(tokenAmount, balanceOf(msg.sender, _tid));
    //console.log("174 _buyPrep: tokenBalanceAfterBuy: %s", tokenBalanceAfterBuy);
    if (tokenBalanceAfterBuy > maxTokensPerUser) {
      tokenAmount = sub(maxTokensPerUser, balanceOf(msg.sender, _tid));
      require(tokenAmount > 0, "Purchase limit hit for this token for this user");
    }
    //console.log("178 _buyPrep: tokenAmount: %s", tokenAmount);
    // update surf amount and undo the fee
    surfAmount = wdiv(tokenAmount, rate);
    //console.log("181 _buyPrep: surfAmount: %s", surfAmount);
    surfAmount = _undoTransferFee(surfAmount);
    //console.log("183 _buyPrep: surfAmount: %s", surfAmount);
    // just in case, but shouldn't happen
    if (surfAmount > _surfAmount) {
      surfAmount = _surfAmount;
    }
    //console.log("188 _buyPrep: surfAmount: %s", surfAmount);
    return surfAmount;
  }


  function _buyTokens(uint _surfAmount, uint _tid) internal {
    uint tokenAmount = wmul(_surfAmount, rate);

    // mint tokens and increment counter
    t[_tid].token.mint(address(this), tokenAmount);
    t[_tid].balance[msg.sender] = add(t[_tid].balance[msg.sender], tokenAmount);
    t[_tid].sold = add(t[_tid].sold, tokenAmount);

    // if both have sold out then finish
    if (t[0].sold >= amountForSale && t[1].sold >= amountForSale) {
      _finish();
    }

    emit BuyTokens(msg.sender, address(t[_tid].token), tokenAmount);
  }


  function _finish() private {
    stage = 2;
    finishBlock = block.number;
  }


  // add and lock liquidity
  // unlock presale tokens for withdraw
  // bump the sale stage up to 3 (finalized)
  // this can be called by anyone during stage 2 (finished)
  function finalize() public onlyStage(2) {
    surf.approve(address(router), surf.balanceOf(address(this)));

    // mint and supply tidal + half surf liquidity
    t[0].token.mint(address(this), mul(t[0].sold, 2)); // double because half belongs to buyers
    t[0].token.approve(address(router), t[0].sold);
    uint surfLiquidity = surf.balanceOf(address(this)) / 2;
    router.addLiquidity(
      address(surf),
      address(t[0].token),
      surfLiquidity,
      t[0].sold,
      surfLiquidity,
      t[0].sold,
      address(0),
      block.timestamp
    );

    // mint and supply tidal + half surf liquidity
    t[1].token.mint(address(this), mul(t[1].sold, 2)); // double because half belongs to buyers
    t[1].token.approve(address(router), t[1].sold);
    surfLiquidity = surf.balanceOf(address(this));
    router.addLiquidity(
      address(surf),
      address(t[1].token),
      surfLiquidity,
      t[1].sold,
      surfLiquidity,
      t[1].sold,
      address(0),
      block.timestamp
    );

    stage = 3;
  }

  // transfer token ownership.
  // ownership will eventually be to the farming contract
  // but can be transferred to an intermediary for further config
  function transferTokenOwnerships(address _newTokenOwner) public onlyOwner onlyStage(3) {
    require(_newTokenOwner != address(0), "Invalid token owner");
    t[0].token.transferOwnership(_newTokenOwner);
    t[1].token.transferOwnership(_newTokenOwner);
  }

  function withdraw(address _buyer, uint _tid) external onlyStage(3) {
    uint amount = t[_tid].balance[_buyer];
    //console.log("sale::withdraw:amount: %s", amount);
    t[_tid].balance[_buyer] = 0;
    t[_tid].token.transfer(_buyer, amount);
    emit Withdraw(_buyer, address(t[_tid].token), amount);
  }

  function balanceOf(address _buyer, uint _tid) public view returns (uint) {
    return t[_tid].balance[_buyer];
  }

  // convenience function for the front end
  function details() external view returns (uint, uint, uint, uint, uint) {
    return (stage, rate, amountForSale, t[0].sold, t[1].sold);
  }

  function _undoTransferFee(uint _inputAmount) internal pure returns (uint) {
    return wdiv(_inputAmount, INVERSE_SURF_FEE_PERCENT);
  }


  function _minusTransferFee(uint _inputAmount) internal pure returns (uint) {
    return wmul(_inputAmount, INVERSE_SURF_FEE_PERCENT);
  }

}