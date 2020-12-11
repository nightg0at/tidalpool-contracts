/*
  Sale interface

  @nightg0at
  SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

interface ISale {
  function details() external view returns (uint, uint, uint, uint);
}