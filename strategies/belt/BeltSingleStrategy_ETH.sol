//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "./BeltSingleStrategy.sol";

contract BeltSingleStrategy_ETH is BeltSingleStrategy {
    function initializeStrategy(address _storage, address _vault) public initializer {
        address underlying = address(0xAA20E8Cb61299df2357561C2AC2e1172bC68bc25);
        address belt = address(0xE0e514c71282b6f4e823703a39374Cf58dc3eA4f);
        address eth = address(0x250632378E573c6Be1AC2f97Fcdf00515d0Aa91B);
        address busd = address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
        address depositorHelp = address(0xAA20E8Cb61299df2357561C2AC2e1172bC68bc25);

        BeltSingleStrategy.initializeStrategy(
            _storage,
            underlying,
            _vault,
            address(0xD4BbC80b9B102b77B21A06cb77E954049605E6c1), // master chef contract
            belt, // reward token
            depositorHelp,
            5, // Pool id
            eth // vault token
        );

        pancake_BELT2TOKEN = [belt, busd, eth];
    }
}