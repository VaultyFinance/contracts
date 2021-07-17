//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "./AlpacaBaseStrategy.sol";

contract AlpacaBTCBStrategy is AlpacaBaseStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c);
    address wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address alpaca = address(0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F);
    address ibToken = address(0x08FC9Ba2cAc74742177e0afC3dC8Aed6961c24e7); // underlying and depositor help contract at once
    AlpacaBaseStrategy.initialize(
      _storage,
      underlying,
      _vault,
      ibToken,
      ibToken,
      18
    );
    pancake_route = [alpaca, wbnb, underlying];
  }
}
