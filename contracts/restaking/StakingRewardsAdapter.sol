/*
  The base contract for any of our Synthetix-like staking adapters

  @nightg0at
  SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

import "./BaseAdapter.sol";
import "./interfaces/IStakingAdapter.sol";
import "./interfaces/IStakingRewards.sol";

contract StakingRewardsAdapter is IStakingAdapter, BaseAdapter {

  IStakingRewards public target;

  constructor(
    IStakingRewards _target,
    IERC20 _lpToken,
    IERC20 _rewardToken,
    address _home
  ) public BaseAdapter(_lpToken, _rewardToken, _home) {
    target = _target;
  }

  function claim() public virtual override onlyHome {
    target.getReward();
    transferReward();
  }

  function deposit(uint _amount) public virtual override {
    lpToken.safeApprove(address(target), 0);
    lpToken.safeApprove(address(target), _amount);
    target.stake(_amount);
  }

  function withdraw(uint _amount) public virtual override onlyHome {
    target.withdraw(_amount);
    transferLP();
    claim();
  }

  function emergencyWithdraw() public virtual override onlyHome {
    target.withdraw(target.balanceOf(address(this)));
    transferLP();
  }

  function pending() public virtual override view returns (uint) {
    return target.earned(address(this));
  }

  function balance() public virtual override view returns (uint) {
    return target.balanceOf(address(this));
  }

}