/*
  The shared configuration for tidal and riptide sibling tokens

  @nightg0at
  SPDX-License-Identifier: MIT
*/

pragma solidity 0.6.12;

import "./interfaces/ITide.sol";
//import "./interfaces/ISale.sol"; // unused now?


contract TideParent is Wipeout {

  address private _poseidon;
  address[2] public siblings;

  uint256 private _burnRate = 69 * 1e17; //6.9%
  uint256 private _transmuteRate = 42 * 1e16; //0.42%

  function setPoseidon(address _newPoseidon) public onlyOwner {
    if (protected[_poseidon].active) {
      protected[_poseidon] = AddressInfo(0, 0, 0);
    }
    _poseidon = _newPoseidon;
    protected[_poseidon] = AddressInfo(1, 5 * 1e17, 69 * 1e16);
  }

  function setToken(uint256 _index, address _token) public onlyOwner {
    require(_token != address(0), "TIDECONFIG::setToken: zero address");
    address[_index] = _token;
  }

  function setAddresses(address _tokenA, address _tokenB, address _newPoseidon) external onlyOwner {
    setToken(0, _tokenA);
    setToken(1, _tokenB);
    setPoseidon(_newPoseidon);
  }

  function setBurnRate(uint256 _newBurnRate) external onlyOwner {
    require(_newBurnRate <= 2 * 1e17, "TIDECONFIG:setBurnRate: 20% max");
    _burnRate = _newBurnRate;
  }

  function setTransmuteRate(uint256 _newTransmuteRate) external onlyOwner {
    require(_newTransmuteRate <= 1e17, "TIDECONFIG:setBurnRate: 10% max");
    _transmuteRate = _newTransmuteRate;
  }

  function setNewParent(address _newConfig) external onlyOwner {
    ITide(_tokenA).setParent(_newConfig);
    ITide(_tokenB).setParent(_newConfig);
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