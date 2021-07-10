//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "./AlpacaBaseStrategy.sol";

contract AlpacaBUSDStrategy is AlpacaBaseStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    address wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address alpaca = address(0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F);
    address ibToken = address(0x7C9e73d4C71dae564d41F78d56439bB4ba87592f); // underlying and depositor help contract at once
    AlpacaBaseStrategy.initialize(
      _storage,
      ibToken,
      _vault,
      ibToken,
      underlying,
      3
    );
    pancake_route = [alpaca, wbnb, underlying];
  }
}
