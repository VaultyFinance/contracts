pragma solidity 0.6.12;

import "./INftHub.sol";

contract NftHubMock is INftHub {
  uint256 public boosterValue;

  constructor(
    uint256 _boosterValue
  ) public {
    boosterValue = _boosterValue;
  }

  function getBoosterForUser(address _user, uint256 _pid) external override view returns (uint256) {
    return boosterValue;
  }
}
