// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";

contract TokenSwap is Ownable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  IERC20Upgradeable public tokenFrom;
  IERC20Upgradeable public tokenTo;

  constructor(IERC20Upgradeable _tokenFrom, IERC20Upgradeable _tokenTo) public {
    tokenFrom = _tokenFrom;
    tokenTo = _tokenTo;
  }

  function swap(uint256 amount) public {
    tokenFrom.safeTransferFrom(msg.sender, address(this), amount);
    tokenTo.safeTransfer(msg.sender, amount);
  }

  function reclaimTokens() public onlyOwner {
    tokenTo.transfer(msg.sender, tokenTo.balanceOf(address(this)));
  }
}
