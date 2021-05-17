//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "./BeltSingleStrategy.sol";

contract BeltSingleStrategy_BTCB is BeltSingleStrategy {
    function initializeStrategy(address _storage, address _vault) public initializer {
        address underlying = address(0x51bd63F240fB13870550423D208452cA87c44444);
        address belt = address(0xE0e514c71282b6f4e823703a39374Cf58dc3eA4f);
        address btcb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
        address busd = address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
        address depositorHelp = address(0x51bd63F240fB13870550423D208452cA87c44444);

        BeltSingleStrategy.initializeStrategy(
            _storage,
            underlying,
            _vault,
            address(0xD4BbC80b9B102b77B21A06cb77E954049605E6c1), // master chef contract
            belt, // reward token
            depositorHelp,
            7, // Pool id
            btcb // vault token
        );

        pancake_BELT2TOKEN = [belt, busd, btcb];
    }
}