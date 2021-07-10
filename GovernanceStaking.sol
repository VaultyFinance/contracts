// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Governable.sol";
import "./NoMintRewardPool.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";

contract GovernaceStaking is Governable {
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
    token.transferFrom(msg.sender, address(this), amount);
    tokensLocked += amount;
  }

  function withdrawTokens() public onlyGovernance {
    require(block.timestamp - depositTimestamp > lockPeriod, "too early");

    uint256 unavailableTokens = tokensStaked;
    uint256 availableTokens = tokensLocked - unavailableTokens;
    token.transfer(msg.sender, availableTokens);

    tokensLocked = unavailableTokens;
  }

  function stake(NoMintRewardPool pool, uint256 amount) public onlyGovernance {
    require(amount >= tokensLocked - tokensStaked, "not enough tokens");

    tokensStaked += amount;

    token.approve(address(pool), amount);
    pool.stake(amount);

    activePool = pool;
  }

  function unstake() public onlyGovernance {
    activePool.exit(); // unstake all tokens at once

    tokensStaked = 0;
  }
}
