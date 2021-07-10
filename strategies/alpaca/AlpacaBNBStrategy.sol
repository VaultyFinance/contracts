//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "./AlpacaBaseStrategy.sol";

contract AlpacaBNBStrategy is AlpacaBaseStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address alpaca = address(0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F);
    address ibToken = address(0xd7D069493685A581d27824Fc46EdA46B7EfC0063); // underlying and depositor help contract at once
    AlpacaBaseStrategy.initialize(
      _storage,
      ibToken,
      _vault,
      ibToken,
      underlying,
      3
    );
    pancake_route = [alpaca, underlying];
  }
}
