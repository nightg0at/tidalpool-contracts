/*
  Airdrop token.
  Stake boon for tidal and riptide tokens on tide.finance during the first phase.

  @nightg0at
  SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BoonToken is ERC20("Seagod's Boon", "BOON"), Ownable {
  function mint(address _to, uint256 _amount) public onlyOwner {
    _mint(_to, _amount);
  }
}
