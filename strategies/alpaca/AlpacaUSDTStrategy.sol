//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "./AlpacaBaseStrategy.sol";

contract AlpacaUSDTStrategy is AlpacaBaseStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x55d398326f99059fF775485246999027B3197955);
    address wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address alpaca = address(0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F);
    address ibToken = address(0x158Da805682BdC8ee32d52833aD41E74bb951E59); // underlying and depositor help contract at once
    AlpacaBaseStrategy.initialize(
      _storage,
      underlying,
      _vault,
      ibToken,
      ibToken,
      16
    );
    pancake_route = [alpaca, wbnb, underlying];
  }
}
