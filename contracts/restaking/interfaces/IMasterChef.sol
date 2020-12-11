/*
  The interface for any MasterChef contract
  MasterChef.sol originally by sushiswap.

  @nightg0at
  SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

interface IMasterChef {
  function withdraw(uint _pid, uint _amount) external;
  function emergencyWithdraw(uint _pid) external;
  function deposit(uint _pid, uint _amount) external;
  function pendingSushi(uint _pid, address _user) external view returns (uint);
  function userInfo(uint _pid, address _user) external view returns (uint, uint);
}