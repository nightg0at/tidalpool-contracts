/*
  Exemption whitelists and convenience methods for Tidal's punitive mechanisms

  @nightg0at
  SPDX-License-Identifier: MIT
*/


pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";
import "@uniswap/v2-core/build/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Whitelist is Ownable {

  // protectors can be ERC20, ERC777 or ERC1155 tokens
  // ERC115 tokens have a different balanceOf() method, so we use the ERC1820 registry to identify the ERC1155 interface
  IERC1820Registry private constant ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
  bytes4 private constant ERC1155_INTERFACE_ID = 0xd9b67a26;

  // used to identify if an address is likely to be a uniswap pair
  address private constant UNISWAP_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;


  // tokens that offer the holder some kind of protection
  struct TokenDetails {
    bool active;
    uint32 id; // for IERC1155 tokens only
    uint64 proportion; // proportion of incoming tokens used as burn amount (typically 1 or 0.5)
    uint64 floor; // the lowest the balance can be after a wipeout event
  }

  // addresses that have some kind of protection as if they are holding protective tokens
  struct AddressDetails {
    bool active;
    uint64 proportion;
    uint64 floor;
  }

  // addresses that do not incur punitive burns or wipeouts as senders or receivers
  struct WhitelistDetails {
    bool active;
    bool sendBurn;
    bool receiveBurn;
    bool sendWipeout;
    bool receiveWipeout;
  }

  uint64 public defaultProportion = 1e18;
  uint64 public defaultFloor = 0;

  constructor() public {
    /*
    addProtector(0x00, 2, , 5 * 1e17, 0); // surfboard
    addProtector(0x00, 2, , 1e18, 2496 * 1e14); // bronze trident 0.2496 floor
    addProtector(0x00, 2, , 1e18, 2496 * 1e14); // bronze trident 0.2496 floor
    addProtector(0x00, 2, , 1e18, 4200 * 1e14); // silver trident 0.42 floor
    addProtector(0x00, 2, , 1e18, 6900 * 1e14); // gold trident 0.69 floor
    */
  }

  mapping (address => AddressDetails) public protectedAddress;
  address[] public protectors;
  mapping (address => TokenDetails) public protectorDetails;
  mapping (address => WhitelistDetails) public whitelist;
  


  function addProtector(address _token, uint64 _standard, uint64 _id, uint64 _proportion, uint64 _floor) public onlyOwner {
    require(protectorDetails[_token] == false, "WIPEOUT::addProtector: Token already added");
    editProtector(_token, 1, _standard, _id, _proportion, _floor);
    protectors.push(_token);
  }

  function editProtector(address _token, bool _active, uint64 _standard, uint64 _id, uint64 _proportion, uint64 _floor) public onlyOwner {
    require(_token != address(0), "WIPEOUT::editProtector: zero address");
    require(_proportion < 2**64, "WIPEOUT::editProtector: _proportion too big");
    require(_floor < 2**64, "WIPEOUT::editProtector: _floor too big");
    protectorDetails[_token] = (_active, _standard, _id, _proportion, _floor);
  }

  function getProtectorDetails(address _addr) external view returns (bool, uint32, uint32, uint64, uint64) {
    return (
      protectorDetails[_addr].active,
      protectorDetails[_addr].standard,
      protectorDetails[_addr].id,
      protectorDetails[_addr].proportion,
      protectorDetails[_addr].floor
    );
  }

  function getProtectors() external view returns (address[]) { // can i return arrays yet?
    return protectors;
  }

  function hasProtector(address _addr, address _protector) external view returns (bool) {
    bool has = false;
    if (ERC1820_REGISTRY.implementsERC165Interface(_protector, ERC1155_INTERFACE_ID))
      if (IERC1155(_protector).balanceOf(_addr, protectors[_protector].id) > 0) {
        has = true;
      }
    } else {
      if (IERC20(_protector).balanceOf(_addr) > 0) {
        has = true;
      }
    }
    return has;
  }

  function cumulativeProtectionOf(address _addr) external view returns (uint64, uint64) {
    uint64 proportion = defaultProportion;
    uint64 floor = defaultFloor;
    for (uint i=0; i<protectors.length; i++) {
      if (hasProtector(_addr)) {
        if (proportion > protectors[i].proportion) {
          proportion = protectors[i].proportion;
        }
        if (floor < protectors[i].floor) {
          floor = protectors[i].floor;
        }
      }
    }
    return (proportion, floor);
  }


  function addProtectedAddress(address _addr, uint64 _proportion, uint64 _floor) public onlyOwner {
    require(protectedAddress[_addr] == false, "WIPEOUT::addProtector: Token already added");
    editProtectedAddress(_addr, 1, _proportion, _floor);
  }


  function editProtectedAddress(address _addr, bool _active, uint64 _proportion, uint64 _floor) public onlyOwner {
    require(_token != address(0), "WIPEOUT::editProtector: zero address");
    require(_proportion < 2**64, "WIPEOUT::editProtector: _proportion too big");
    require(_floor < 2**64, "WIPEOUT::editProtector: _floor too big");
    protectedAddress[_addr] = (_active, _proportion, _floor);
  }


  function getProtectedAddress(address _addr) external view returns (bool, uint64, uint64) {
    return (
      protectedAddress[_addr].active,
      protectedAddress[_addr].proportion,
      protectedAddress[_addr].floor
    );
  }


  function addWhitelist(
    address _whitelisted,
    bool _sendBurn,
    bool _receiveBurn,
    bool _sendWipeout,
    bool _receiveWipeout
  ) public onlyOwner {
    require(whitelist[_whitelisted].active == false, "WIPEOUT::addNoBurn: Address already added and active");
    editWhitelist(_whitelisted, true, _sendBurn, _receiveBurn, _sendWipeout, _receiveWipeout);
  }


  function editWhitelist(
    address _whitelisted,
    bool _active,
    bool _sendBurn,
    bool _receiveBurn,
    bool _sendWipeout,
    bool _receiveWipeout
  ) public onlyOwner {
    require(_whitelisted != address(0), "WIPEOUT::editWhitelist: zero address");
    whitelist[_whitelisted] = WhitelistDetails(_active, _sendBurn, _receiveBurn, _sendWipeout, _receiveWipeout);
  }


  function getWhitelist(address _addr) external view returns (bool, bool, bool, bool, bool) {
    return (
      whitelist[_addr].active,
      whitelist[_addr].sendBurn,
      whitelist[_addr].receiveBurn,
      whitelist[_addr].sendWipeout,
      whitelist[_addr].receiveWipeout,
    );
  }

  function _isUniswapTokenPair(address _addr) internal returns (bool) {
    try IUniswapV2Pair(_addr).factory() returns (bool outcome) {
      return outcome;
    } catch {
      return false;
    }
  }


  function willBurn(address _sender, address _recipient) public returns (bool) {
    // returns true if everything is false
    return !(whitelist[_sender].sendBurn || whitelist[_recipient].receiveBurn);
  }


  function willWipeout(address _sender, address _recipient) public returns (bool) {
    bool whitelisted = whitelist[_sender].sendWipeout || _isUniswapTokenPair(_sender);
    whitelisted = whitelisted || whitelist[_recipient].receiveWipeout);
    // returns true if everything is false
    return !whitelisted;
  }

}