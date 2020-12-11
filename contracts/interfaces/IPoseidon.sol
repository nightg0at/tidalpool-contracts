/*
  Poseidon interface

  @nightg0at
  SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

interface IPoseidon {
  function getPhase() external view returns (address);
}