/*
  Dummy contract for token testing
  Has a settable phase

  @nightg0at
  SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

contract Poseidon {

  address public phase;
  address public tidal;
  address public riptide;

  constructor(
    address _tidal,
    address _riptide
  ) public {
    tidal = _tidal;
    riptide = _riptide;
    phase = tidal;
  }

  // return the active reward token (the phase; either tide or riptide)
  function getPhase() public view returns (address) {
    return phase;
  }

  function togglePhase() public {
    phase = phase == tidal ? riptide : tidal;
  }


}