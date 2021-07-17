//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "./AlpacaBaseStrategy.sol";

contract AlpacaETHStrategy is AlpacaBaseStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
    address wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address alpaca = address(0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F);
    address ibToken = address(0xbfF4a34A4644a113E8200D7F1D79b3555f723AfE); // underlying and depositor help contract at once
    AlpacaBaseStrategy.initialize(
      _storage,
      underlying,
      _vault,
      ibToken,
      ibToken,
      9
    );
    pancake_route = [alpaca, wbnb, underlying];
  }
}
