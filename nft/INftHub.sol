pragma solidity 0.6.12;

interface INftHub {
  function getBoosterForUser(address _user, uint256 _pid) external view returns (uint256);
}
