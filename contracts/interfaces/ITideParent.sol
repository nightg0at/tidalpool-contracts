/*
  TideParent interface

  @nightg0at
  SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

interface ITideTokenParent {
  function poseidon() external view returns (address);
  function burnRate() external view returns (uint256);
  function transmuteRate() external view returns (uint256);
  function sibling() external view returns (address);
  function cumulativeProtectionOf(address _addr) external view returns (uint256, uint256);
  function getProtectedAddress(address _addr) external view returns (bool, uint256, uint256);
  function isUniswapTokenPair(address _addr) external returns (bool);
  function willBurn(address _sender, address _recipient) external returns (bool);
  function willWipeout(address _sender, address _recipient) external returns (bool);
}