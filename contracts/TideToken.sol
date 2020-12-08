/*
  Tide tokens TIDAL and RIPTIDE

  @nightg0at
  SPDX-License-Identifier: MIT
*/


pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ds-math/math.sol";

interface IPoseidon {
  function getPhase() external view returns (address);
}

interface ITideParent {
  function poseidon() external view returns (address);
  function burnRate() external view returns (uint256);
  function transmuteRate() external view returns (uint256);
  function sibling() external view returns (address);
}

interface ITide is IERC20 {
  function mint(address _to, uint256 _amount) external;
  function wipeout(address _recipient, uint256 _amount, address _otherToken) external;
}

contract TideToken is ERC20, Ownable, DSMath {
  using SafeMath for uint256;

  ITideParent public parent;
  ITide public sibling;

  constructor(
    string memory name,
    string memory symbol,
    ITideParent _parent
  ) public {
    ERC20(name, symbol);
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
    parent = _newParent;
  }

  function setSibling(address _newSibling) public onlyParent {
    require(_newSibling != address(0), "TIDE::setSibling: zero address");
    sibling = _newSibling;
  }

  function transfer(address _recipient, uint256 _amount) public virtual override returns (bool) {
    uint256 amount = _amount;
    if (parent.willBurn(msg.sender, _recipient)) {
      amount = _transferBurn(msg.sender, amount);
    }
    if (parent.willWipeout(msg.sender, _recipient)) {
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
      sibling.wipeout(_recipient, newAmount, address(this));
    }
    return super.transferFrom(_sender, _recipient, amount);
  }

  function _transferBurn(address _sender, uint256 _amount) private returns (uint256) {
    uint256 burnAmount;
    if (_inPhase()) {
      // percentage transmuted into sibling token and sent to sender
      burnAmount = wmul(_amount, parent.transmuteRate());
      _burn(_sender, burnAmount);
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
    (bool active, uint64 proportion, uint64 floor) = parent.getProtectedAddress(_recipient);
    if (parent.isUniswapTokenPair(_recipient)) {
      // check if recipient is a uniswap pair

    } else if (active) {
      // check if recipient is a protected address
      burnAmount = _reduce(
        _incomingAmount,
        proportion,
        floor
      );
    } else {
      // check if recipient has one or more protector tokens
      (proportion, floor) = parent.getBestProtection(_recipient);
      burnAmount = _reduce(
        _incomingAmount,
        proportion,
        floor
      );
    }
    _burn(_recipient, burnAmount);
  }


  function _reduce(uint256 _amount, uint256 _proportion, uint _floor) internal returns (uint256) {
    uint256 burnAmount = wmul(_amount, _proportion);
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

  function _inPhase() internal view {
    return IPoseidon(parent.poseidon()).getPhase() == address(this);
  }

}