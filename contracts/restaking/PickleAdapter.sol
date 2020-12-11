/*
  Pickle.finance adapter

  @nightg0at
  SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

import "./interfaces/IMasterChef.sol";
import "./MasterChefAdapter.sol";

interface IPickle is IMasterChef {
  function pendingPickle(uint _pid, address _user) external view returns (uint);
}

contract PickleAdapter is MasterChefAdapter {

  constructor(
    IMasterChef _target,
    IERC20 _lpToken,
    IERC20 _rewardToken,
    address _home,
    uint _pid
  ) public MasterChefAdapter(_target, _lpToken, _rewardToken, _home, _pid) {}

  function pending() public virtual override view returns (uint) {
    return IPickle(address(target)).pendingPickle(pid, address(this));
  }
}