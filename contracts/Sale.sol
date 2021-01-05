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


contract Sale is Ownable, ReentrancyGuard, DSMath {

  struct TokenInfo {
    TideToken token;
    uint sold;
    mapping(address => uint) balance;
    bool unlocked;
  }

  IERC20 public surf;
  IUniswapV2Router02 public router;
  TokenInfo[2] public t;

  uint public delayWarning;

  uint public amountForSale = 42e17; // 4.2 of tidal and riptide each
  uint public SurfRaise = 1e22; // 10k surf in total
  uint public rate = wdiv(amountForSale, SurfRaise);
  uint public maxTokens =  3e18; // 3k surf?
  uint public constant INVERSE_SURF_FEE_PERCENT = 99e16; // the inverse of the 1% surf transfer fee
  uint public startBlock = 1;
  uint public finishBlock = 2;
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
    uint _delayWarning // 6500 is 1 day
  ) public {
    t[0] = TokenInfo(_tidal, 0, false);
    t[1] = TokenInfo(_riptide, 0, false);
    surf = _surf;
    router = _router;
    delayWarning = _delayWarning;
  }

  modifier onlyStage(uint _stage) {
    require(stage == _stage, "SALE::onlyStage: Incorrect stage for this method");
    _;
  }

  receive() external payable {
    // ignore the router, it might be refunding some change
    if (msg.sender != address(router)) {
      // buy the most available token if ETH is sent with no data
      t[0].sold < t[1].sold ? buyTokensWithEth(0) : buyTokensWithEth(1);
    }
  }


  function startAt(uint _startBlock) public onlyOwner onlyStage(0) {
    require(_startBlock > block.number + delayWarning); // minimum warning ~1 day
    startBlock = _startBlock;
  }


  function finishAt(uint _finishBlock) public onlyOwner {
    require(_finishBlock > block.number + delayWarning); // minimum warning ~1 day
    finishBlock = _finishBlock;
  }


  function startFinishAt(uint _startBlock, uint _finishBlock) public {
    startAt(_startBlock);
    finishAt(_finishBlock);
  }


  function buyTokensWithEth(uint _tid) public nonReentrant payable {
    if (stage == 0 && startBlock <= block.number) {
      stage = 1;
    }

    address[] memory surfPath = new address[](2);
    surfPath[0] = router.WETH();
    surfPath[1] = address(surf);

    // get how many surf we need from uniswap
    uint[] memory outputEstimate = UniswapV2Library.getAmountsOut(
      router.factory(),
      msg.value,
      surfPath
    );
    uint surfAmount = _buyPrep(outputEstimate[1], _tid);
    uint surfBalBefore = surf.balanceOf(address(this));
    uint ethBalBefore = sub(address(this).balance, msg.value);
    router.swapETHForExactTokens{value: msg.value}(
      surfAmount,
      surfPath,
      address(this),
      block.timestamp
    );
    
    if (address(this).balance > ethBalBefore) {
      msg.sender.transfer(sub(address(this).balance, ethBalBefore));
    }

    uint surfBalAfter = surf.balanceOf(address(this));
    surfAmount = sub(surfBalAfter, surfBalBefore);
    _buyTokens(surfAmount, _tid);
  }


  function buyTokens(uint _surfAmount, uint _tid) public nonReentrant {
    if (stage == 0 && startBlock <= block.number) {
      stage = 1;
    }

    uint surfAmount = _buyPrep(_surfAmount, _tid);
    uint surfBalBefore = surf.balanceOf(address(this));
    surf.transferFrom(msg.sender, address(this), surfAmount);
    uint surfBalAfter = surf.balanceOf(address(this));
    surfAmount = sub(surfBalAfter, surfBalBefore);
    _buyTokens(surfAmount, _tid);
  }


  function _buyPrep(uint _surfAmount, uint _tid) internal view onlyStage(1) returns (uint) {
    uint surfAmount = _minusTransferFee(_surfAmount);
    uint tokenAmount = wmul(_surfAmount, rate);  
    // remaining tokens ceiling
    if (sub(amountForSale, t[_tid].sold) < tokenAmount) {
      tokenAmount = sub(amountForSale, t[_tid].sold);
    }
    // spending limit ceiling
    uint tokenBalanceAfterBuy = add(tokenAmount, balanceOf(msg.sender, _tid));
    if (tokenBalanceAfterBuy > maxTokens) {
      tokenAmount = sub(tokenBalanceAfterBuy, maxTokens);
    }
    // update surf amount and reverse the fee
    surfAmount = wdiv(tokenAmount, rate);
    surfAmount = _reverseTransferFee(surfAmount);
    // just in case, but shouldn't happen
    if (surfAmount > _surfAmount) {
      surfAmount = _surfAmount;
    }
    return surfAmount;
  }


  function _buyTokens(uint _surfAmount, uint _tid) internal onlyStage(1) {
    if (finishBlock < block.number) {
      finish();
      return;
    }

    uint tokenAmount = wmul(_surfAmount, rate);

    // mint tokens and increment counter
    t[_tid].token.mint(address(this), tokenAmount);
    t[_tid].balance[msg.sender] = add(t[_tid].balance[msg.sender], tokenAmount);
    t[_tid].sold = add(t[_tid].sold, tokenAmount);

    // if both have sold out then finish
    if (t[0].sold >= amountForSale && t[1].sold >= amountForSale) {
      finish();
    }

    emit BuyTokens(msg.sender, address(t[_tid].token), tokenAmount);
  }


  function finish() private {
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
    t[0].token.mint(address(this), t[0].sold);
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
    t[1].token.mint(address(this), t[1].sold);
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

    // enable buyers to withdraw
    t[0].unlocked = true;
    t[1].unlocked = true;

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

  function withdraw(address _buyer, uint _tid) external {
    if (t[_tid].unlocked) {
      uint amount = t[_tid].balance[_buyer];
      t[_tid].balance[_buyer] = 0;
      t[_tid].token.transfer(_buyer, amount);
      emit Withdraw(_buyer, address(t[_tid].token), amount);
    } else {
      revert("SALE::withdraw: Tokens not unlocked");
    }
  }

  function balanceOf(address _buyer, uint _tid) public view returns (uint) {
    return t[_tid].balance[_buyer];
  }

  // convenience function for the front end
  function details() external view returns (uint, uint, uint, uint, uint) {
    return (stage, rate, amountForSale, t[0].sold, t[1].sold);
  }

  function _reverseTransferFee(uint _inputAmount) internal pure returns (uint) {
    return mul(wdiv(_inputAmount, INVERSE_SURF_FEE_PERCENT), 100);
  }


  function _minusTransferFee(uint _inputAmount) internal pure returns (uint) {
    return wmul(_inputAmount, INVERSE_SURF_FEE_PERCENT);
  }

}