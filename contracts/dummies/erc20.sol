pragma solidity 0.6.12;
// SPDX-License-Identifier: UNLICENSED

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

//import "hardhat/console.sol";

contract Surf is ERC20("surf.finance", "SURF"), Ownable {

  uint256 transferFee = 10;

  function mint(address _to, uint256 _amount) public onlyOwner {
    _mint(_to, _amount);
  }

  function _transfer(address sender, address recipient, uint256 amount) internal override {
    uint256 transferFeeAmount;
    uint256 tokensToTransfer;
    if (amount > 0) {
      transferFeeAmount = amount.mul(transferFee).div(1000);
      _burn(sender, transferFeeAmount);
      tokensToTransfer = amount.sub(transferFeeAmount);
      //console.log("surf::_transfer: amount[%s] - fee[%s] = tokens[%s]", amount, transferFeeAmount, tokensToTransfer);
      super._transfer(sender, recipient, tokensToTransfer);
    } else {
      super._transfer(sender, recipient, 0);
    }   
  }
}

contract Generic is ERC20, Ownable {
  function mint(address _to, uint256 _amount) public onlyOwner {
    _mint(_to, _amount);
  }

  constructor(string memory name) public ERC20(name, name) {}

}