/*
  harvest.finance adapter

  @nightg0at
  SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

import "./StakingRewardsAdapter.sol";

contract HarvestAdapter is StakingRewardsAdapter {

  constructor(
    IStakingRewards _target,
    IERC20 _lpToken,
    IERC20 _rewardToken,
    address _home
  ) public StakingRewardsAdapter(_target, _lpToken, _rewardToken, _home) {}
  
}