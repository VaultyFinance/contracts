//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "./BeltMultiStrategy.sol";

contract BeltMultiStrategy_4Belt is BeltMultiStrategy {
    constructor() public {}

    function initializeStrategy(address _storage, address _vault) public initializer {
        address underlying = address(0x9cb73F20164e399958261c289Eb5F9846f4D1404); // 4Belt BLP token
        address belt = address(0xE0e514c71282b6f4e823703a39374Cf58dc3eA4f);
        address wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
        address depositHelp = address(0xF6e65B33370Ee6A49eB0dbCaA9f43839C1AC04d5); // Viper contract where stablecoins are deposited
        address busd = address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
        
        BeltMultiStrategy.initializeStrategy(
            _storage,
            underlying,
            _vault,
            address(0xD4BbC80b9B102b77B21A06cb77E954049605E6c1), // Masterchef contract staking pool
            belt, // reward
            depositHelp,
            3 // Pool id for 4Belt
        );
        
        pancake_BELT2BUSD = [belt, wbnb, busd];
    }
}