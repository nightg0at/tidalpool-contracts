/*
  The shared configuration for tidal and riptide sibling tokens

  @nightg0at
  SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

import "./Whitelist.sol";
import "./interfaces/ITideToken.sol";


contract TideParent is Whitelist {

  address private _poseidon;
  address[2] public siblings;

  uint256 private _burnRate = 69 * 1e17; //6.9%
  uint256 private _transmuteRate = 42 * 1e16; //0.42%

  function setPoseidon(address _newPoseidon) public onlyOwner {
    if (whitelist[_poseidon].active) {
      setWhitelist(_poseidon, false, false, false, false, false);
    }
    if (protectedAddress[_poseidon].active) {
      setProtectedAddress(_poseidon, false, 0, 0);
    }
    setProtectedAddress(_newPoseidon, true, 5e17, 69e16); // check
    setWhitelist(_newPoseidon, true, true, false, true, false);
    _poseidon = _newPoseidon;
  }

  function setSibling(uint256 _index, address _token) public onlyOwner {
    require(_token != address(0), "TIDECONFIG::setToken: zero address");
    siblings[_index] = _token;
  }

  function setAddresses(address _siblingA, address _siblingB, address _newPoseidon) external onlyOwner {
    setSibling(0, _siblingA);
    setSibling(1, _siblingB);
    setPoseidon(_newPoseidon);
  }

  function setBurnRate(uint256 _newBurnRate) external onlyOwner {
    require(_newBurnRate <= 2 * 1e17, "TIDECONFIG:setBurnRate: 20% max");
    _burnRate = _newBurnRate;
  }

  function setTransmuteRate(uint256 _newTransmuteRate) external onlyOwner {
    require(_newTransmuteRate <= 1e17, "TIDECONFIG:setTransmuteRate: 10% max");
    _transmuteRate = _newTransmuteRate;
  }

  function setNewParent(address _newConfig) external onlyOwner {
    ITideToken(siblings[0]).setParent(_newConfig);
    ITideToken(siblings[1]).setParent(_newConfig);
  }

  function poseidon() public view returns (address) {
    return _poseidon;
  }

  function burnRate() public view returns (uint256) {
    return _burnRate;
  }

  function transmuteRate() public view returns (uint256) {
    return _transmuteRate;
  }

  function sibling() public view returns (address) {
    require(msg.sender == siblings[0] || msg.sender == siblings[1], "TideConfig::sibling: No sibling");
    return msg.sender == siblings[0] ? siblings[1] : siblings[0];
  }

}