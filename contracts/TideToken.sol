/*
  Tide tokens TIDAL and RIPTIDE

  @nightg0at
  SPDX-License-Identifier: MIT
*/


pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ds-math/math.sol";
import "./interfaces/ITideToken.sol";
import "./interfaces/ITideParent.sol";
import "./interfaces/IPoseidon.sol";

//import "hardhat/console.sol";

contract TideToken is ERC20Burnable, Ownable, DSMath {
  ITideParent public parent;

  constructor(
    string memory name,
    string memory symbol,
    ITideParent _parent
  ) public ERC20(name, symbol)
  {  
    parent = _parent;
  }

  modifier onlySibling() {
    require(parent.sibling(msg.sender) == address(this), "TIDE::onlySibling: Must be sibling");
    _;
  }

  modifier onlyMinter() {
    require(
      parent.sibling(msg.sender) == address(this) || msg.sender == owner(),
      "TIDE::onlyMinter: Must be owner or sibling to call mint"
    );
    _;
  }

  modifier onlyParent() {
    require(msg.sender == address(parent), "TIDE::onlyParent: Only current parent can change parent");
    _;
  }


  function setParent(address _newParent) public onlyParent {
    require(_newParent != address(0), "TIDE::setParent: zero address");
    parent = ITideParent(_newParent);
  }
  
  /*
  function setSibling(address _newSibling) public onlyParent {
    require(_newSibling != address(0), "TIDE::setSibling: zero address");
    sibling = ITideToken(_newSibling);
  }
  */

  function transfer(address _recipient, uint256 _amount) public virtual override returns (bool) {
    uint256 amount = _amount;
    if (parent.willBurn(msg.sender, _recipient)) {
      amount = _transferBurn(msg.sender, amount);
    }
    if (parent.willWipeout(msg.sender, _recipient)) {
      ITideToken sibling = ITideToken(parent.sibling(address(this)));
      sibling.wipeout(_recipient, amount);
      if (parent.isUniswapTokenPair(_recipient)) {
        _burn(msg.sender, amount);
        amount = 0;
      }
    }
    return super.transfer(_recipient, amount);
  }

  function transferFrom(address _sender, address _recipient, uint256 _amount) public virtual override returns (bool) {
    uint256 amount = _amount;
    if (parent.willBurn(_sender, _recipient)) {
      amount = _transferBurn(_sender, amount);
    }
    if (parent.willWipeout(_sender, _recipient)) {
      ITideToken sibling = ITideToken(parent.sibling(address(this)));
      sibling.wipeout(_recipient, amount);
      if (parent.isUniswapTokenPair(_recipient)) {
        _burn(_sender, amount);
        amount = 0;
      }
    }
    return super.transferFrom(_sender, _recipient, amount);
  }


  function _transferBurn(address _sender, uint256 _amount) private returns (uint256) {
    uint256 burnAmount;
    if (_inPhase()) {
      // percentage transmuted into sibling token and sent to sender
      burnAmount = wmul(_amount, parent.transmuteRate());
      ITideToken sibling = ITideToken(parent.sibling(address(this)));
      sibling.mint(_sender, burnAmount);
    } else {
      // percentage burned
      burnAmount = wmul(_amount, parent.burnRate());
    }
    _burn(_sender, burnAmount);
    // return the new amount after burning
    return sub(_amount, burnAmount);
  }

  /*
  // do we need this?
  //   only if poseidon burns some tokens for some reason
  //   perhaps have a burn own balance function?
  function burn(address account, uint256 amount) public onlyOwner {
    _burn(account, amount);
  }
  */

  function mint(address _to, uint256 _amount) public onlyMinter { 
    _mint(_to, _amount);
  }

  function wipeout(address _recipient, uint256 _amount) public onlySibling {
    uint256 burnAmount;
    (bool active, uint256 proportion, uint256 floor) = parent.getProtectedAddress(_recipient);
    if (parent.isUniswapTokenPair(_recipient)) {
      // simulate golden trident protection
      proportion = 5e17;
      floor = 69e16;
    } else if (!active) {
      // check if recipient has one or more protective tokens
      (proportion, floor) = parent.cumulativeProtectionOf(_recipient);
    }
    burnAmount = _reduce(_recipient, _amount, proportion, floor);
    _burn(_recipient, burnAmount);
  }


  function _reduce(address _recipient, uint256 _amount, uint256 _proportion, uint256 _floor) internal view returns (uint256) {
    uint256 balance = balanceOf(_recipient);
    uint256 burnAmount;
    if (balance > _floor) {
      burnAmount = wmul(_amount, _proportion);
      // if resultant balance lower than zero burn everything
      if (burnAmount > balance) {
        burnAmount = balance;
      }
      //if resultant balance lower than floor leave floor remaining
      if (sub(balance, burnAmount) < _floor) {
        burnAmount = sub(balance, _floor);
      }
    }
    return burnAmount;
  }


  function _inPhase() internal view returns (bool) {
    return IPoseidon(parent.poseidon()).getPhase() == address(this);
  }

}