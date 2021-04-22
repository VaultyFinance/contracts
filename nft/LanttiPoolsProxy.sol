pragma solidity 0.6.12;

import "../upgradability/UpgradableProxy.sol";

contract LanttiPoolsProxy is UpgradableProxy {
  constructor(address _implementation) public UpgradableProxy(_implementation) {
  }
}
