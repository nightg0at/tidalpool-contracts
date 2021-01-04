/*
  Exemption whitelists and convenience methods for Tidal's punitive mechanisms

  @nightg0at
  SPDX-License-Identifier: MIT
*/


pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Whitelist is Ownable {

  // protectors can be ERC20, ERC777 or ERC1155 tokens
  // ERC115 tokens have a different balanceOf() method, so we use the ERC1820 registry to identify the ERC1155 interface
  //IERC1820Registry private constant ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
  IERC1820Registry private erc1820Registry; // 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24
  bytes4 private constant ERC1155_INTERFACE_ID = 0xd9b67a26;

  // used to identify if an address is likely to be a uniswap pair
  address private constant UNISWAP_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

  // tokens that offer the holder some kind of protection
  struct TokenAttributes {
    bool active;
    //uint256 id; // for IERC1155 tokens only
    uint256 proportion; // proportion of incoming tokens used as burn amount (typically 1 or 0.5)
    uint256 floor; // the lowest the balance can be after a wipeout event
  }

  struct TokenID {
    address addr;
    uint256 id; // for IERC1155 tokens else 0
  }

  // addresses that have some kind of protection as if they are holding protective tokens
  struct AddressAttributes {
    bool active;
    uint256 proportion;
    uint256 floor;
  }

  // addresses that do not incur punitive burns or wipeouts as senders or receivers
  struct WhitelistAttributes {
    bool active;
    bool sendBurn;
    bool receiveBurn;
    bool sendWipeout;
    bool receiveWipeout;
  }

  uint256 public defaultProportion = 1e18;
  uint256 public defaultFloor = 0;

  constructor(
    IERC1820Registry _erc1820Registry
  ) public {
    erc1820Registry = _erc1820Registry;
    /*
    addProtector(0x00, 0, , 5e17, 0); // surfboard
    addProtector(0x00, 123, , 1e18, 2496e14); // bronze trident 0.2496 floor
    addProtector(0x00, 456, , 1e18, 42e16); // silver trident 0.42 floor
    addProtector(0x00, 789, , 1e18, 69e16); // gold trident 0.69 floor
    */
  }

  mapping (address => AddressAttributes) public protectedAddress;
  TokenID[] public protectors;
  mapping (address => mapping (uint256 => TokenAttributes)) public protectorAttributes;
  mapping (address => WhitelistAttributes) public whitelist;
  

  function addProtector(address _token, uint256 _id, uint256 _proportion, uint256 _floor) public onlyOwner {
    uint256 id = isERC1155(_token) ? _id : 0;
    require(protectorAttributes[_token][id].active == false, "WIPEOUT::addProtector: Token already active");
    editProtector(_token, true, id, _proportion, _floor);
    protectors.push(TokenID(_token, id));
  }

  function editProtector(address _token, bool _active, uint256 _id, uint256 _proportion, uint256 _floor) public onlyOwner {
    protectorAttributes[_token][_id] = TokenAttributes(_active, _proportion, _floor);
  }

  function protectorLength() external view returns (uint256) {
    return protectors.length;
  }

  function getProtectorAttributes(address _addr, uint256 _id) external view returns (bool, uint256, uint256) {
    return (
      protectorAttributes[_addr][_id].active,
      protectorAttributes[_addr][_id].proportion,
      protectorAttributes[_addr][_id].floor
    );
  }


  function isERC1155(address _token) private view returns (bool) {
    return erc1820Registry.implementsERC165Interface(_token, ERC1155_INTERFACE_ID);
  }

  function hasProtector(address _addr, address _protector, uint256 _id) public view returns (bool) {
    bool has = false;
    if (isERC1155(_protector)) {
      if (IERC1155(_protector).balanceOf(_addr, _id) > 0) {
        has = true;
      }
    } else {
      if (IERC20(_protector).balanceOf(_addr) > 0) {
        has = true;
      }
    }
    return has;
  }

  function cumulativeProtectionOf(address _addr) external view returns (uint256, uint256) {
    uint256 proportion = defaultProportion;
    uint256 floor = defaultFloor;
    for (uint256 i=0; i<protectors.length; i++) {
      address protector = protectors[i].addr;
      uint256 id = protectors[i].id;
      if (hasProtector(_addr, protector, id)) {
        if (proportion > protectorAttributes[protector][id].proportion) {
          proportion = protectorAttributes[protector][id].proportion;
        }
        if (floor < protectorAttributes[protector][id].floor) {
          floor = protectorAttributes[protector][id].floor;
        }
      }
    }
    return (proportion, floor);
  }

  function setProtectedAddress(address _addr, bool _active, uint256 _proportion, uint256 _floor) public onlyOwner {
    require(_addr != address(0), "WIPEOUT::editProtector: zero address");
    protectedAddress[_addr] = AddressAttributes(_active, _proportion, _floor);
  }

  function getProtectedAddress(address _addr) external view returns (bool, uint256, uint256) {
    return (
      protectedAddress[_addr].active,
      protectedAddress[_addr].proportion,
      protectedAddress[_addr].floor
    );
  }

  function setWhitelist(
    address _whitelisted,
    bool _active,
    bool _sendBurn,
    bool _receiveBurn,
    bool _sendWipeout,
    bool _receiveWipeout
  ) public onlyOwner {
    require(_whitelisted != address(0), "WIPEOUT::editWhitelist: zero address");
    whitelist[_whitelisted] = WhitelistAttributes(_active, _sendBurn, _receiveBurn, _sendWipeout, _receiveWipeout);
  }

  function getWhitelist(address _addr) external view returns (bool, bool, bool, bool, bool) {
    return (
      whitelist[_addr].active,
      whitelist[_addr].sendBurn,
      whitelist[_addr].receiveBurn,
      whitelist[_addr].sendWipeout,
      whitelist[_addr].receiveWipeout
    );
  }

  // checks if the address is a deployed contract and if so,
  // checks if the factory() method is present.
  // returns true if it is.
  // This is easy to spoof but the gains are low enough for this to be ok.
  function isUniswapTokenPair(address _addr) public view returns (bool) {
    uint32 size;
    assembly {
      size := extcodesize(_addr)
    }
    if (size == 0) {
      return false;
    } else {
      try IUniswapV2Pair(_addr).factory() returns (address _factory) {
        return _factory == UNISWAP_FACTORY ? true : false;
      } catch {
        return false;
      }
    }
  }


  function willBurn(address _sender, address _recipient) public view returns (bool) {
    // returns true if everything is false
    return !(whitelist[_sender].sendBurn || whitelist[_recipient].receiveBurn);
  }


  function willWipeout(address _sender, address _recipient) public view returns (bool) {
    bool whitelisted = whitelist[_sender].sendWipeout || isUniswapTokenPair(_sender);
    whitelisted = whitelisted || whitelist[_recipient].receiveWipeout;
    // returns true if everything is false
    return !whitelisted;
  }

}