pragma solidity 0.6.12;

import "../upgradability/UpgradableProxy.sol";

contract NftHubProxy is UpgradableProxy {
  constructor(address _implementation) public UpgradableProxy(_implementation) {
  }
}
