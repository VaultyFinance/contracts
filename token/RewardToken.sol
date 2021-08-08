// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./BEP20.sol";
import "../lib/MinterRole.sol";
import "./UsingLiquidityProtectionService.sol";

contract RewardToken is
    BEP20,
    MinterRole,
    UsingLiquidityProtectionService(0xBA2bF7693E0903B373077ace7b002Bd925913df2)
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

    function token_transfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal override {
        _transfer(_from, _to, _amount); // Expose low-level token transfer function.
    }

    function token_balanceOf(address _holder) internal view override returns (uint256) {
        return balanceOf(_holder); // Expose balance check function.
    }

    function protectionAdminCheck() internal view override onlyOwner {} // Must revert to deny access.

    function uniswapVariety() internal pure override returns (bytes32) {
        return PANCAKESWAP;
    }

    function uniswapFactory() internal pure override returns (address) {
        return 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal override {
        LiquidityProtection_beforeTokenTransfer(_from, _to, _amount);
    }

    // How the protection gets disabled.
    function protectionChecker() internal view override virtual returns (bool) {
        return ProtectionSwitch_timestamp(1630367999); // Switch off protection on Monday, August 30, 2021 11:59:59 PM GMT.
        // return ProtectionSwitch_block(13000000); // Switch off protection on block 13000000.
        //        return ProtectionSwitch_manual(); // Switch off protection by calling disableProtection(); from owner. Default.
    }

    // This token will be pooled in pair with:
    function counterToken() internal pure override returns (address) {
        return 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // WBNB
    }
}
