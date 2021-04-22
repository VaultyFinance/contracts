pragma solidity 0.6.12;

import "../Governable.sol";

contract ProxyRegistry is Governable {
  mapping(address => address) public proxies;

  constructor(address _storage) public Governable(_storage) {}

  function addOperator(address _owner, address _operator) public onlyGovernance {
    proxies[_owner] = _operator;
  }

  function removeOperator(address _owner) public onlyGovernance {
    delete proxies[_owner];
  }
}
