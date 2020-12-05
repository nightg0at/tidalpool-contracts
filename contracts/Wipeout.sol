/*
  Whitelist and methods for tidal's wipeout functionality

  @nightg0at
  SPDX-License-Identifier: MIT
*/


pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Wipeout is Ownable {

  struct TokenInfo {
    bool active;
    uint32 standard: // 0: ERC20, 1: ERC777, 2: ERC1155
    uint32 id; // part of IERC1155
    uint64 proportion; // proportion of incoming tokens used as burn amount (typically 1 or 0.5)
    uint64 floor; // the lowest the balance can be afterwards
  }


  struct AddressInfo {
    bool active;
    uint64 proportion;
    uint64 floor;
  }

  TokenInfo[] public protectors;

  uint64 public defaultProportion = 1e18;
  uint64 public defaultFloor = 0;

  constructor() public {
    addProtector(0x00, 2, , 5 * 1e17, 0); // surfboard
    addProtector(0x00, 2, , 1e18, 2496 * 1e14); // bronze trident 0.2496 floor
    addProtector(0x00, 2, , 1e18, 2496 * 1e14); // bronze trident 0.2496 floor
    addProtector(0x00, 2, , 1e18, 4200 * 1e14); // silver trident 0.42 floor
    addProtector(0x00, 2, , 1e18, 6900 * 1e14); // gold trident 0.69 floor
  }

  mapping (address => AddressInfo) public protected;
  mapping (address => TokenInfo) public protectorDetails;
  TokenInfo[] public protectors;

  function addProtector(address _token, uint64 _standard, uint64 _id, uint64 _proportion uint64 _floor) public onlyOwner {
    require(protectorDetails[_token] == false, "WIPEOUT::addProtector: Token already added");
    editProtector(_token, 1, _standard, _id, _proportion, _floor);
    protector.push(_token);
  }

  function editProtector(address _token, bool _active, uint64 _standard, uint64 _id, uint64 _proportion uint64 _floor) public onlyOwner {
    require(_token != address(0), "WIPEOUT::editProtector: zero address");
    require(_proportion < 2**64, "WIPEOUT::editProtector: _proportion too big");
    require(_floor < 2**64, "WIPEOUT::editProtector: _floor too big");
    protectorDetails[_token] = (_active, _standard, _id, _proportion, _floor);
  }

  function addProtected(address _contract, uint64 _proportion, uint64 _floor) public onlyOwner {
    require(protectorDetails[_token] == false, "WIPEOUT::addProtector: Token already added");
    protected[_contract] = (1, _proportion, _floor);
  }

  function editProtected(address _contract, bool _active, uint64 _proportion, uint64 _floor) public onlyOwner {
    require(_token != address(0), "WIPEOUT::editProtector: zero address");
    require(_proportion < 2**64, "WIPEOUT::editProtector: _proportion too big");
    require(_floor < 2**64, "WIPEOUT::editProtector: _floor too big");
    protected[_contract] = (_active, _proportion, _floor);
  }

  function getWipeoutAmount(address _recipient, uint256 _incomingAmount, address _existingToken) public returns (uint256) {
    // by default the burn amount = incoming token amount
    uint256 burnAmount;
    // check recipient against contracts
    if (protected[_recipient].active) {
      burnAmount = _reduce(
        _incomingAmount,
        protected[_recipient].proportion,
        protected[_recipient].floor,
        _existingToken
      );
    } else {

      uint256 proportion = defaultProportion;
      uint256 floor = defaultFloor;

      // check recipient for ownership of tokens
      for (uint i=0; i<protectors.length; i++) {
        bool has = false;
        if (protectors[i].standard == 1) {
          if (IERC1155(protectors[i].token).balanceOf(_recipient, protectors[i].id) > 0) {
            has = true;
          }
        } else {
          if (IERC20(protectors[i].token).balanceOf(_recipient) > 0) {
            has = true;
          }
        }
        if (has) {
          if (proportion > protectors[i].proportion) {
            proportion = protectors[i].proportion;
          }
          if (floor < protectors[i].floor) {
            floor = protectors[i].floor;
          }
        }
      }
    
      burnAmount = _reduce(
        _incomingAmount,
        proportion,
        floor,
        _existingToken
      );
    }

    return burnAmount;
  }

  function _reduce(uint256 _amount, uint256 _proportion, uint _floor, address _existingToken) internal returns (uint256) {
    uint256 burnAmount = wmul(_amount, _proportion); // eg 0.5 of incoming amount is burned from existing
    uint256 existingBalance = IERC20(_existingToken).balanceOf(_recipient);

    // if this puts the balance below zero:
    //  adjust burnAmount to match balance
    if (burnAmount > existingBalance) {
      burnAmount = existingBalance;
    }

    // if this would result in a balance lower than the floor:
    //  adjust burnAmount to match floor
    if (sub(existingBalance, burnAmount) < _floor) {
      burnAmount = _floor;
    }

    return burnAmount;
  }

}