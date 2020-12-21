pragma solidity 0.6.12;
// SPDX-License-Identifier: UNLICENSED
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract T20 is ERC20 {
  constructor() public ERC20("t20", "t20") {
    _mint(msg.sender, 1e18);
  }
}

contract T1155 is ERC1155, Ownable {
  constructor() public ERC1155("https://dummy.api/data.json") {
  }

  function mint(address _to, uint256 _index, uint256 _amount) public onlyOwner {
    _mint(_to, _index, _amount, "");
  }

}

