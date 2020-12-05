/*
  surf tidalpool presale

  SPDX-License-Identifier: MIT
*/

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ds-math/math.sol";
import "./TidalToken.sol";

contract Sale is Ownable, ReentrancyGuard, DSMath {

  TidalToken public token;
  address payable public treasury;
  uint public amountForSale;
  uint public ETHRaise;
  uint public rate;
  uint public maxTokens;
  mapping(address => uint) public balance;


  /*
    0: not started
    1: started
    2: finished
    3: finalized

  */
  uint public stage = 0;
  uint public amountSold = 0;
  bool public presaleUnlocked = false;
  uint public startBlock = 1e8;
  uint public finishBlock = 1e8;

  event BuyTokens(address indexed buyer, uint amount);
  event Withdraw(address indexed buyer, uint amount);

  constructor(
    TidalToken _token,
    uint _amountForSale,
    uint _ETHRaise,
    uint _maxSpend
  ) public {
    token = _token;
    treasury = msg.sender;
    amountForSale = _amountForSale; // 4.2
    ETHRaise = _ETHRaise; // 12.6
    rate = wdiv(amountForSale, ETHRaise); // 0.333333333333333333333
    maxTokens = wmul(_maxSpend, rate); // 1 ETH worth
  }

  modifier onlyStage(uint _stage) {
    require(stage == _stage, "incorrect sale stage");
    _;
  }


  receive() external payable {
    buyTokens();
  }


  function startAt(uint _startBlock) public onlyOwner onlyStage(0) {
    //require(_startBlock > block.number + 6500); // minimum warning ~1 day
    startBlock = _startBlock;
  }

  function finishAt(uint _finishBlock) public onlyOwner {
    //require(_finishBlock > block.number + 6500); // minimum warning ~1 day
    finishBlock = _finishBlock;
  }

  function buyTokens() public nonReentrant payable {
    if (stage == 0 && startBlock <= block.number) {
      stage = 1;
    }
    _buyTokens();
  }

  function _buyTokens() private onlyStage(1) {
    if (finishBlock < block.number) {
      finish();
      return;
    }
  
    uint weiAmount = msg.value;
    uint tokenAmount = wmul(weiAmount, rate);

    // ensure there are enough tokens remaining
    if (sub(amountForSale, amountSold) < tokenAmount) {
      tokenAmount = sub(amountForSale, amountSold);
      weiAmount = refund(tokenAmount, weiAmount);
    }


    // ensure this wallet doesn't hit its spending limit
    uint newBoughtTokens = add(tokenAmount, balanceOf(msg.sender));
    if (newBoughtTokens > maxTokens) {
      tokenAmount = sub(newBoughtTokens, maxTokens);
      weiAmount = refund(tokenAmount, weiAmount);
    }

    // mint tokens and increment counter
    token.mint(address(this), tokenAmount);
    balance[msg.sender] = add(balance[msg.sender], tokenAmount);
    amountSold = add(amountSold, tokenAmount);

    if (amountSold >= amountForSale) {
      finish();
    }

    emit BuyTokens(msg.sender, tokenAmount);
  }

  function refund(uint _tokenAmount, uint _weiAmount) private returns (uint) {
    uint newWeiAmount = wdiv(_tokenAmount, rate);
    msg.sender.transfer(sub(_weiAmount, newWeiAmount));
    return newWeiAmount;
  }

  function finish() private {
    stage = 2;
    finishBlock = block.number;
  }

  // transfer funds to the treasury and bump the sale stage up to 3 (finalized)
  function finalize() public onlyOwner onlyStage(2) {
    treasury.transfer(address(this).balance);
    stage = 3;
  }

  // transfer token ownership.
  // ownership will eventually be to the farming contract
  function transferTokenOwnership(address _tokenOwner) public onlyOwner onlyStage(3) {
    require(_tokenOwner != address(0), "Invalid token owner");
    token.transferOwnership(_tokenOwner);
  }

  function setTreasury(address payable _treasury) public onlyOwner {
    require(_treasury != address(0), "Invalid treasury address");
    treasury = _treasury;
  }

  function balanceOf(address _buyer) public view returns (uint) {
    return balance[_buyer];
  }

  // convenience function for the front end
  function details() external view returns (uint, uint, uint, uint) {
    return (stage, rate, amountForSale, amountSold);
  }

  function withdraw(address _buyer) public {
    if (!presaleUnlocked) {
      if (token.totalSupply() >= 42e18) {
        presaleUnlocked = true;
      }
    }

    if (presaleUnlocked) {
      uint amount = balance[_buyer];
      balance[_buyer] = 0;
      token.transfer(_buyer, amount);
      emit Withdraw(_buyer, amount);
    } else {
      revert("tokens not unlocked");
    }
  }
}