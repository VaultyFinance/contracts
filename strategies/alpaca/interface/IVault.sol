// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IVault {

  /// @dev Return the total ERC20 entitled to the token holders. Be careful of unaccrued interests.
  function totalToken() external view returns (uint256);

  function totalSupply() external view returns (uint256);

  /// @dev Add more ERC20 to the bank. Hope to get some good returns.
  function deposit(uint256 amountToken) external payable;

  /// @dev Withdraw ERC20 from the bank by burning the share tokens.
  function withdraw(uint256 share) external;

  /// @dev Request funds from user through Vault
  function requestFunds(address targetedToken, uint amount) external;

  function debtShareToVal(uint256 debtShare) external view returns (uint256);

  function debtValToShare(uint256 debtVal) external view returns (uint256);

}
