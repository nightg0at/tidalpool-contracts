pragma solidity 0.6.12;
// SPDX-License-Identifier: UNLICENSED

import "./erc20.sol";

contract UniswapV2Pair is Generic("lp") {

  address public token0;
  address public token1;

  function initialize(address _token0, address _token1) public {
    token0 = _token0;
    token1 = _token1;
  }

}