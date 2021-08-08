// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Governable.sol";
import "./NoMintRewardPool.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";

contract GovernaceStaking is Governable {
  using SafeBEP20 for IBEP20;

  uint256 public lockPeriod;
  uint256 public depositTimestamp;
  uint256 public tokensLocked;
  uint256 public tokensStaked;
  NoMintRewardPool public activePool;
  IBEP20 public token;

  constructor(address _storage, IBEP20 _token, uint256 _lockPeriod) Governable(_storage) public {
    require(_token != IBEP20(address(0)));
    lockPeriod = _lockPeriod;
    token = _token;
  }

  function depositTokens(uint256 amount) public onlyGovernance {
    depositTimestamp = block.timestamp;
    tokensLocked += amount;
    token.safeTransferFrom(msg.sender, address(this), amount);
  }

  function withdrawTokens() public onlyGovernance {
    require(block.timestamp - depositTimestamp > lockPeriod, "too early");

    uint256 unavailableTokens = tokensStaked;
    uint256 availableTokens = tokensLocked - unavailableTokens;
    tokensLocked = unavailableTokens;
    token.safeTransfer(msg.sender, availableTokens);
  }

  function stake(NoMintRewardPool pool, uint256 amount) public onlyGovernance {
    require(amount >= tokensLocked - tokensStaked, "not enough tokens");

    tokensStaked += amount;

    token.safeApprove(address(pool), amount);
    pool.stake(amount);

    activePool = pool;
  }

  function unstake() public onlyGovernance {
    activePool.exit(); // unstake all tokens at once

    tokensStaked = 0;
  }
}
