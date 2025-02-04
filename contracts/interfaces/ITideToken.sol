/*
  TideToken interface

  @nightg0at
  SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITideToken is IERC20 {
  function owner() external view returns (address);
  function mint(address _to, uint256 _amount) external;
  function setParent(address _newConfig) external;
  function wipeout(address _recipient, uint256 _amount) external;
}