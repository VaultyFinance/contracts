//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "./AlpacaBaseStrategy.sol";

contract AlpacaTUSDStrategy is AlpacaBaseStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x14016E85a25aeb13065688cAFB43044C2ef86784);
    address wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address alpaca = address(0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F);
    address ibToken = address(0x3282d2a151ca00BfE7ed17Aa16E42880248CD3Cd); // underlying and depositor help contract at once
    AlpacaBaseStrategy.initialize(
      _storage,
      underlying,
      _vault,
      ibToken,
      ibToken,
      20
    );
    pancake_route = [alpaca, wbnb, underlying];
  }
}
