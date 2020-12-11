/*
  The interface for any StakingRewards-like contract.
  StakingRewards.sol originally by Synthetix.

  @nightg0at
  SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

interface IStakingRewards {
  function getReward() external;
  function stake(uint _amount) external;
  function withdraw(uint _amount) external;
  function earned(address _account) external view returns (uint);
  function balanceOf(address _account) external view returns (uint);
}