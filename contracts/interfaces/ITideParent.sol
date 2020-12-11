/*
  TideParent interface

  @nightg0at
  SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

interface ITideParent {
  function poseidon() external view returns (address);
  function burnRate() external view returns (uint256);
  function transmuteRate() external view returns (uint256);
  function sibling() external view returns (address);
}