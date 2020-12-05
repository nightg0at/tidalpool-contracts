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

contract TideToken is ERC20, Ownable {
  using SafeMath for uint256;

  ITideParent public parent;

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
  }

  modifier onlyMinter() {
    require(
      parent.sibling(msg.sender) == address(this) || msg.sender == owner(),
      "TIDE::onlyMinter: Must be owner or sibling to call mint"
    );
  }

  modifier onlyParent() {
    require(msg.sender == address(parent), "TIDE::onlyparent: Only current parent can change parent");
  }


  function setParent(address _newParent) public onlyParent {
    require(_newParent != address(0), "TIDE::setparent: zero address");
    parent = _newParent;
  }

  function transfer(address _recipient, uint256 _amount) public virtual override returns (bool) {
    uint256 newAmount = _transferBurn(msg.sender, _amount);
    ITide(parent.sibling(address(this))).wipeout(_recipient, newAmount, address(this));
    return super.transfer(_recipient, newAmount);
  }

  function transferFrom(address _sender, address _recipient, uint256 _amount) public virtual override returns (bool) {
    uint256 newAmount = _transferBurn(_sender, _amount);
    ITide(parent.sibling(address(this))).wipeout(_recipient, newAmount, address(this));
    return super.transferFrom(_sender, _recipient, _amount.sub(burnAmount));
  }

  function _transferBurn(address _sender, uint256 _amount) private returns (uint256) {
    uint256 burnAmount;
    if (_inPhase()) {
      // percentage transmuted into sibling token and sent to sender
      burnAmount = wmul(_amount, parent.transmuteRate());
      _burn(sender, transmuteAmount);
      ITide(parent.sibling(address(this))).mint(_sender, transmuteAmount);
    } else {
      // percentage burned
      burnAmount = wmul(_amount, parent.burnRate());
      _burn(_sender, burnAmount);
    }
    return burnAmount;
  }

  /*
  // do we need this?
  function burn(address account, uint256 amount) public onlyOwner {
    _burn(account, amount);
  }
  */

  function mint(address _to, uint256 _amount) public onlyMinter { 
    _mint(_to, _amount);
  }

  function wipeout(address _recipient, uint256 _amount, address _otherToken) public onlySibling {
    uint256 burnAmount = parent.wipeoutAmount(_recipient, _amount, _otherToken);
    _burn(_recipient, burnAmount);
  }

  function _inPhase() internal view {
    return IPoseidon(parent.poseidon()).getPhase() == address(this);
  }
}