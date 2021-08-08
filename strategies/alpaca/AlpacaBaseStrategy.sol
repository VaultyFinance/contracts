//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "./interface/IFairLaunch.sol";
import "./interface/IVault.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";

import "@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";

import "../../upgradability/BaseUpgradeableStrategy.sol";
import "../../interfaces/pancakeswap/IPancakeRouter02.sol";

contract AlpacaBaseStrategy is BaseUpgradeableStrategy {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    address public constant pancakeswapRouterV2 =
        address(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
    bytes32 internal constant _POOLID_SLOT =
        0x3fd729bfa2e28b7806b03a6e014729f59477b530f995be4d51defc9dad94810b;
    bytes32 internal constant _DEPOSITOR_SLOT =
        0x7e51443ed339b944018a93b758544b6d25c6c65ccaf25ffca5127da0103d7ddf;
    bytes32 internal constant _DEPOSITOR_UNDERLYING_SLOT =
        0xfffae5dac57e2313ef5a16a03f71dacc1da392f7ae9ca598779f29a0ada318c2;

    address[] public pancake_route;

    constructor() public BaseUpgradeableStrategy() {
        assert(_POOLID_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.poolId")) - 1));
        assert(
            _DEPOSITOR_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.depositor")) - 1)
        );
        assert(
            _DEPOSITOR_UNDERLYING_SLOT ==
                bytes32(uint256(keccak256("eip1967.strategyStorage.depositorUnderlying")) - 1)
        );
    }

    function initialize(
        address _storage,
        address _underlying, // main underlying like BNB, ETH, USDT
        address _vault,
        address _depositHelp, // lend contract where to put BNB, ETH, USDT
        address _depositorUnderlying, // ibToken which should be staked to get rewards (usually the same as _depositorHelp)
        uint256 _poolID
    ) public initializer {
        BaseUpgradeableStrategy.initialize(
            _storage,
            _underlying,
            _vault,
            address(0xA625AB01B08ce023B2a342Dbb12a16f2C8489A8F), // _rewardPool ALPACA FairLaunch contract (staking contract)
            address(0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F), // _rewardToken ALPACA token
            100, // profit sharing numerator
            1000, // profit sharing denominator
            true, // sell
            1e16, // sell floor
            12 hours // implementation change delay
        );

        address _lpt;
        (_lpt, , , ) = IFairLaunch(rewardPool()).poolInfo(_poolID);
        require(_lpt == _depositorUnderlying, "Pool Info does not match underlying");
        _setPoolId(_poolID);
        _setDepositor(_depositHelp);
        _setDepositorUnderlying(_depositorUnderlying);
    }

    function depositArbCheck() public pure returns (bool) {
        return true;
    }

    function rewardPoolBalance() internal view returns (uint256 bal) {
        (bal, , , ) = IFairLaunch(rewardPool()).userInfo(poolId(), address(this));
    }

    function unsalvagableTokens(address token) public view returns (bool) {
        return (token == rewardToken() || token == underlying());
    }

    /*
     *   In case there are some issues discovered about the pool or underlying asset
     *   Governance can exit the pool properly
     *   The function is only used for emergency to exit the pool
     */
    function emergencyExit() public onlyGovernance {
        IFairLaunch(rewardPool()).emergencyWithdraw(poolId());
        _setPausedInvesting(true);
    }

    /*
     *   Resumes the ability to invest into the underlying reward pools
     */
    function continueInvesting() public onlyGovernance {
        _setPausedInvesting(false);
    }

    function setLiquidationPath(address[] memory _route) public onlyGovernance {
        require(_route[0] == rewardToken(), "Path should start with rewardToken");
        pancake_route = _route;
    }

    // We assume that all the tradings can be done on Pancakeswap
    function _liquidateReward() internal {
        if (underlying() != rewardToken()) {
            uint256 rewardBalance = IBEP20(rewardToken()).balanceOf(address(this));
            if (!sell() || rewardBalance < sellFloor()) {
                // Profits can be disabled for possible simplified and rapid exit
                emit ProfitsNotCollected(sell(), rewardBalance < sellFloor());
                return;
            }
            notifyProfitInRewardToken(rewardBalance);
            uint256 remainingRewardBalance = IBEP20(rewardToken()).balanceOf(address(this));
            if (remainingRewardBalance == 0) {
                return;
            }

            // allow Pancakeswap to sell our reward
            IBEP20(rewardToken()).safeApprove(pancakeswapRouterV2, 0);
            IBEP20(rewardToken()).safeApprove(pancakeswapRouterV2, remainingRewardBalance);

            // we can accept 1 as minimum because this is called only by a trusted role
            uint256 amountOutMin = 1;

            IPancakeRouter02(pancakeswapRouterV2).swapExactTokensForTokens(
                remainingRewardBalance,
                amountOutMin,
                pancake_route,
                address(this),
                block.timestamp
            );
        }
    }

    function claimAndLiquidateReward() internal {
        IFairLaunch(rewardPool()).harvest(poolId());
        _liquidateReward();
    }

    function getUnderlyingFromDepositor() internal {
        uint256 ibBalance = IBEP20(depositorUnderlying()).balanceOf(address(this));
        if (ibBalance > 0) {
            IVault(depositor()).withdraw(ibBalance);
        }
    }

    /*
     *   Lend everything the strategy holds and then stake into the reward pool
     */
    function investAllUnderlying() internal onlyNotPausedInvesting {
        uint256 underlyingBalance = IBEP20(underlying()).balanceOf(address(this));
        if (underlyingBalance > 0) {
            IBEP20(underlying()).safeApprove(depositor(), 0);
            IBEP20(underlying()).safeApprove(depositor(), underlyingBalance);
            IVault(depositor()).deposit(underlyingBalance);
        }

        uint256 ibTokenBalance = IBEP20(depositorUnderlying()).balanceOf(address(this));

        if (ibTokenBalance > 0) {
            IBEP20(depositorUnderlying()).safeApprove(rewardPool(), 0);
            IBEP20(depositorUnderlying()).safeApprove(rewardPool(), ibTokenBalance);
            IFairLaunch(rewardPool()).deposit(address(this), poolId(), ibTokenBalance);
        }
    }

    /*
     *   Withdraws all the asset to the vault
     */
    function withdrawAllToVault() public restricted {
        if (address(rewardPool()) != address(0)) {
            uint256 bal = rewardPoolBalance();
            if (bal != 0) {
                claimAndLiquidateReward();
                IFairLaunch(rewardPool()).withdraw(address(this), poolId(), bal);
            }
        }
        getUnderlyingFromDepositor();
        IBEP20(underlying()).safeTransfer(vault(), IBEP20(underlying()).balanceOf(address(this)));
    }

    /*
     *   Withdraws all the asset to the vault
     */
    function withdrawToVault(uint256 amount) public restricted {
        // Typically there wouldn't be any amount here
        // however, it is possible because of the emergencyExit
        uint256 entireBalance = IBEP20(underlying()).balanceOf(address(this));

        if (amount > entireBalance) {
            // While we have the check above, we still using SafeMath below
            // for the peace of mind (in case something gets changed in between)
            uint256 needToWithdraw = amount.sub(entireBalance);
            uint256 toWithdraw = MathUpgradeable.min(rewardPoolBalance(), needToWithdraw);
            IFairLaunch(rewardPool()).withdraw(address(this), poolId(), toWithdraw);
            IVault(depositor()).withdraw(toWithdraw);
        }
        IBEP20(underlying()).safeTransfer(vault(), amount);
    }

    /*
     *   Note that we currently do not have a mechanism here to include the
     *   amount of reward that is accrued.
     */
    function investedUnderlyingBalance() external view returns (uint256) {
        if (rewardPool() == address(0)) {
            return IBEP20(underlying()).balanceOf(address(this));
        }
        // Adding the amount locked in the reward pool and the amount that is somehow in this contract
        // both are in the units of "underlying"
        // The second part is needed because there is the emergency exit mechanism
        // which would break the assumption that all the funds are always inside of the reward pool
        return rewardPoolBalance().add(IBEP20(underlying()).balanceOf(address(this)));
    }

    /*
     *   Governance or Controller can claim coins that are somehow transferred into the contract
     *   Note that they cannot come in take away coins that are used and defined in the strategy itself
     */
    function salvage(
        address recipient,
        address token,
        uint256 amount
    ) external onlyControllerOrGovernance {
        // To make sure that governance cannot come in and take away the coins
        require(!unsalvagableTokens(token), "token is defined as not salvagable");
        IBEP20(token).safeTransfer(recipient, amount);
    }

    /*
     *   Get the reward, sell it in exchange for underlying, invest what you got.
     *   It's not much, but it's honest work.
     *
     *   Note that although `onlyNotPausedInvesting` is not added here,
     *   calling `investAllUnderlying()` affectively blocks the usage of `doHardWork`
     *   when the investing is being paused by governance.
     */
    function doHardWork() external onlyNotPausedInvesting restricted {
        uint256 bal = rewardPoolBalance();
        if (bal != 0) {
            claimAndLiquidateReward();
        }
        investAllUnderlying();
    }

    /**
     * Can completely disable claiming rewards and selling. Good for emergency withdraw in the
     * simplest possible way.
     */
    function setSell(bool s) public onlyGovernance {
        _setSell(s);
    }

    /**
     * Sets the minimum amount needed to trigger a sale.
     */
    function setSellFloor(uint256 floor) public onlyGovernance {
        _setSellFloor(floor);
    }

    // rewards pool ID
    function _setPoolId(uint256 _value) internal {
        setUint256(_POOLID_SLOT, _value);
    }

    function poolId() public view returns (uint256) {
        return getUint256(_POOLID_SLOT);
    }

    function _setDepositor(address _address) internal {
        setAddress(_DEPOSITOR_SLOT, _address);
    }

    function depositor() public view virtual returns (address) {
        return getAddress(_DEPOSITOR_SLOT);
    }

    function _setDepositorUnderlying(address _address) internal {
        setAddress(_DEPOSITOR_UNDERLYING_SLOT, _address);
    }

    function depositorUnderlying() public view virtual returns (address) {
        return getAddress(_DEPOSITOR_UNDERLYING_SLOT);
    }

    function finalizeUpgrade() external onlyGovernance {
        _finalizeUpgrade();
    }
}
