/*
  The base contract for any adapters

  @nightg0at
  SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./interfaces/IStakingAdapter.sol";


abstract contract BaseAdapter is IStakingAdapter {
  using SafeERC20 for IERC20;

  IERC20 public lpToken;
  IERC20 public rewardToken;
  address public home;

  constructor(
    IERC20 _lpToken,
    IERC20 _rewardToken,
    address _home
  ) public {
    require(address(_lpToken) != address(0), "missing staking token");
    require(address(_rewardToken) != address(0), "missing reward token");
    require(address(_home) != address(0), "missing home contract");
    lpToken = _lpToken;
    rewardToken = _rewardToken;
    home = _home;
  }

  modifier onlyHome() {
    require(msg.sender == home, "only home can call this function");
    _;
  }

  function rewardTokenAddress() public view virtual override returns (address) {
    return address(rewardToken);
  }

  function lpTokenAddress() public view virtual override returns (address) {
    return address(lpToken);
  }

  function transferLP() internal {
    lpToken.safeTransfer(home, lpToken.balanceOf(address(this)));
  }

  function transferReward() internal {
    rewardToken.safeTransfer(home, rewardToken.balanceOf(address(this)));
  }

}