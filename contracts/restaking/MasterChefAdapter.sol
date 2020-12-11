/*
  The base contract for any of our MasterChef-like staking adapters

  pending() will likely need to be overridden due to it having a sushi specific name

  @nightg0at
  SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

import "./BaseAdapter.sol";
import "./interfaces/IStakingAdapter.sol";
import "./interfaces/IMasterChef.sol";

abstract contract MasterChefAdapter is BaseAdapter {

  IMasterChef public target;
  uint public pid;


  constructor(
    IMasterChef _target,
    IERC20 _lpToken,
    IERC20 _rewardToken,
    address _home,
    uint _pid
  ) public BaseAdapter(_lpToken, _rewardToken, _home) {
    target = _target;
    pid = _pid;
  }

  function claim() public virtual override onlyHome {
    target.withdraw(pid, 0);
    transferReward();
  }

  function deposit(uint _amount) public virtual override {
    lpToken.safeApprove(address(target), 0);
    lpToken.safeApprove(address(target), _amount);
    target.deposit(pid, _amount);
    transferReward();
  }

  function withdraw(uint _amount) public virtual override onlyHome {
    target.withdraw(pid, _amount);
    transferLP();
    transferReward();
  }

  function emergencyWithdraw() public virtual override onlyHome {
    target.emergencyWithdraw(pid);
    transferLP();
  }


  function balance() public virtual override view returns (uint) {
    (uint amount, ) = target.userInfo(pid, address(this));
    return amount;
  }

}