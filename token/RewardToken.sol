pragma solidity 0.6.12;

import "./BEP20.sol";
import "../Governable.sol";
import "../lib/MinterRole.sol";

contract RewardToken is MinterRole, BEP20, Governable {
    uint256 public constant HARD_CAP = 1500000 * (10**18);

    constructor(address _storage) public BEP20("Holvi Reward Token", "HOLVI") Governable(_storage) {
        renounceOwnership();

        address gov = governance();
        if (!isMinter(gov)) {
            _addMinter(gov);
        }
    }

    function cap() public view returns (uint256) {
        return HARD_CAP;
    }

    function mint(address account, uint256 amount) public onlyMinter returns (bool) {
        require(totalSupply().add(amount) <= HARD_CAP, "cap exceeded");
        _mint(account, amount);
        return true;
    }
}
