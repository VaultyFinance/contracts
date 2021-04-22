pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

contract BaseProxyStorage is Initializable {
  bytes32 internal constant _NEXT_IMPLEMENTATION_SLOT = 0xd2e419928330bff46341e233ce76acced45e2a4d72eca0da439ceaad8a810424;
  bytes32 internal constant _NEXT_IMPLEMENTATION_TIMESTAMP_SLOT = 0xcc513a9d9a86885d0dcbd3c0ba0e09e91c988d066a2c3099cb0f0f4104ea0797;
  bytes32 internal constant _NEXT_IMPLEMENTATION_DELAY_SLOT = 0xc30f2f65a1117bd1d1a12244675384902c0891a5bfbe53e738e28acfb09c8cb0;


  constructor() public {
    assert(_NEXT_IMPLEMENTATION_SLOT == keccak256("eip1967.proxyStorage.nextImplementation"));
    assert(_NEXT_IMPLEMENTATION_TIMESTAMP_SLOT == keccak256("eip1967.proxyStorage.nextImplementationTimestamp"));
    assert(_NEXT_IMPLEMENTATION_DELAY_SLOT == keccak256("eip1967.proxyStorage.nextImplementationDelay"));
  }

  function _setNextImplementation(address _address) internal {
    setAddress(_NEXT_IMPLEMENTATION_SLOT, _address);
  }

  function nextImplementation() public view returns (address) {
    return getAddress(_NEXT_IMPLEMENTATION_SLOT);
  }

  function _setNextImplementationTimestamp(uint256 _value) internal {
    setUint256(_NEXT_IMPLEMENTATION_TIMESTAMP_SLOT, _value);
  }

  function nextImplementationTimestamp() public view returns (uint256) {
    return getUint256(_NEXT_IMPLEMENTATION_TIMESTAMP_SLOT);
  }

  function _setNextImplementationDelay(uint256 _value) internal {
    setUint256(_NEXT_IMPLEMENTATION_DELAY_SLOT, _value);
  }

  function nextImplementationDelay() public view returns (uint256) {
    return getUint256(_NEXT_IMPLEMENTATION_DELAY_SLOT);
  }

  function setBoolean(bytes32 slot, bool _value) internal {
    setUint256(slot, _value ? 1 : 0);
  }

  function getBoolean(bytes32 slot) internal view returns (bool) {
    return (getUint256(slot) == 1);
  }

  function setAddress(bytes32 slot, address _address) internal {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      sstore(slot, _address)
    }
  }

  function setUint256(bytes32 slot, uint256 _value) internal {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      sstore(slot, _value)
    }
  }

  function getAddress(bytes32 slot) internal view returns (address str) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      str := sload(slot)
    }
  }

  function getUint256(bytes32 slot) internal view returns (uint256 str) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      str := sload(slot)
    }
  }

  uint256[100] private ______gap;
}
