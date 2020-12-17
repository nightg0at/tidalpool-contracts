/*
  Tide tokens TIDAL and RIPTIDE

  @nightg0at
  SPDX-License-Identifier: MIT
*/


pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ds-math/math.sol";
import "./interfaces/ITide.sol";
import "./interfaces/ITideParent.sol";
import "./interfaces/IPoseidon.sol";

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
    require(parent.sibling() == address(this), "TIDE::onlySibling: Must be sibling");
    _;
  }

  modifier onlyMinter() {
    require(
      parent.sibling() == address(this) || msg.sender == owner(),
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
    sibling = ITide(_newSibling);
  }
  */

  function transfer(address _recipient, uint256 _amount) public virtual override returns (bool) {
    uint256 amount = _amount;
    if (parent.willBurn(msg.sender, _recipient)) {
      amount = _transferBurn(msg.sender, amount);
    }
    if (parent.willWipeout(msg.sender, _recipient)) {
      ITide sibling = ITide(parent.sibling());
      sibling.wipeout(_recipient, amount, address(this));
    }
    return super.transfer(_recipient, amount);
  }

  function transferFrom(address _sender, address _recipient, uint256 _amount) public virtual override returns (bool) {
    uint256 amount = _amount;
    if (parent.willBurn(_sender, _recipient)) {
      amount = _transferBurn(_sender, amount);
    }
    if (parent.willWipeout(_sender, _recipient)) {
      ITide sibling = ITide(parent.sibling());
      sibling.wipeout(_recipient, amount, address(this));
    }
    return super.transferFrom(_sender, _recipient, amount);
  }

  function _transferBurn(address _sender, uint256 _amount) private returns (uint256) {
    uint256 burnAmount;
    if (_inPhase()) {
      // percentage transmuted into sibling token and sent to sender
      burnAmount = wmul(_amount, parent.transmuteRate());
      _burn(_sender, burnAmount);
      ITide sibling = ITide(parent.sibling());
      sibling.mint(_sender, burnAmount);
    } else {
      // percentage burned
      burnAmount = wmul(_amount, parent.burnRate());
      _burn(_sender, burnAmount);
    }
    // return the new amount after burning
    return sub(_amount, burnAmount);
  }

  /*
  // do we need this?
  //   only if poseidon burns some tokens for some reason
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
      // apply double wipeout if uniswap pair
      proportion = proportion*2;
    } else if (!active) {
      // check if recipient has one or more protector tokens
      (proportion, floor) = parent.cumulativeProtectionOf(_recipient);
    }
    burnAmount = _reduce(_recipient, _amount, proportion, floor);
    _burn(_recipient, burnAmount);
  }


  function _reduce(address _recipient, uint256 _amount, uint256 _proportion, uint256 _floor) internal view returns (uint256) {
    uint256 burnAmount = wmul(_amount, _proportion);
    ITide sibling = ITide(parent.sibling());
    uint256 otherBalance = sibling.balanceOf(_recipient);
    // if resultant balance lower than zero adjust to zero
    if (burnAmount > otherBalance) {
      burnAmount = otherBalance;
    }
    //if resultant balance lower than floor adjust to floor
    if (sub(otherBalance, burnAmount) < _floor) {
      burnAmount = _floor;
    }
    return burnAmount;
  }


  function _inPhase() internal view returns (bool) {
    return IPoseidon(parent.poseidon()).getPhase() == address(this);
  }

}