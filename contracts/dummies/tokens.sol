pragma solidity 0.6.12;
// SPDX-License-Identifier: UNLICENSED

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Farm is ERC20("harvest.finance", "FARM"), Ownable {
  function mint(address _to, uint256 _amount) public onlyOwner {
    _mint(_to, _amount);
  }
}

contract FarmLP is ERC20, Ownable {
  constructor() public ERC20("FARM-USDC LP", "FARM-USDC LP") {
    _mint(msg.sender, 10 ether);
  }
}

contract Pickle is ERC20("pickle.finance", "PICKLE"), Ownable {
  function mint(address _to, uint256 _amount) public onlyOwner {
    _mint(_to, _amount);
  }
}

contract PickleLP is ERC20, Ownable {
  constructor() public ERC20("PICKLE-ETH LP", "PICKLE-ETH LP") {
    _mint(msg.sender, 10 ether);
  }
}

contract Dracula is ERC20("dracula.sucks", "DRC"), Ownable {
  function mint(address _to, uint256 _amount) public onlyOwner {
    _mint(_to, _amount);
  }
}

contract DraculaLP is ERC20, Ownable {
  constructor() public ERC20("DRC-ETH LP", "DRC-ETH LP") {
    _mint(msg.sender, 10 ether);
  }
}

contract NiceLP is ERC20, Ownable {
  constructor() public ERC20("NICE-ETH LP", "NICE-ETH LP") {
    _mint(msg.sender, 10 ether);
  }
}

contract RottenLP is ERC20, Ownable {
  constructor() public ERC20("ROTTEN-ETH LP", "ROTTEN-ETH LP") {
    _mint(msg.sender, 10 ether);
  }
}

contract CropsToken is ERC20("Crops Token", "CROPS"), Ownable {
  function mint(address _to, uint256 _amount) public onlyOwner {
    _mint(_to, _amount);
  }
}