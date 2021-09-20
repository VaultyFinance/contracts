// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./BEP20.sol";
import "../lib/MinterRole.sol";

contract RewardToken is
    BEP20,
    MinterRole
{
    uint256 public constant HARD_CAP = 15000000 * (10**18);

    constructor(address gov) public BEP20("Vaulty Token", "VLTY") {
        if (!isMinter(gov)) {
            _addMinter(gov);
        }
    }

    function mint(address account, uint256 amount) public onlyMinter returns (bool) {
        require(totalSupply().add(amount) <= HARD_CAP, "cap exceeded");
        _mint(account, amount);
        return true;
    }
}
