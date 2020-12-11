/*
  The interface for any of our staking adapters

  @nightg0at
  SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

interface IStakingAdapter {
    function claim() external;
    function deposit(uint amount) external;
    function withdraw(uint amount) external;
    function emergencyWithdraw() external;
    function rewardTokenAddress() external view returns(address); // does this need to be type IERC20?
    function lpTokenAddress() external view returns(address);
    function pending() external view returns (uint256);
    function balance() external view returns (uint256);
}