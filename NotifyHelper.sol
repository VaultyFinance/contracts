pragma solidity 0.6.12;

import "./Controllable.sol";
import "./NoMintRewardPool.sol";

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";

interface IFeeRewardForwarder {
    function poolNotifyFixedTarget(address _token, uint256 _amount) external;
}

contract NotifyHelper is Controllable {
    using SafeMath for uint256;

    address public feeRewardForwarder;
    address public rewardToken;
    uint256 public profitShareIncentiveDaily;
    uint256 public lastProfitShareTimestamp;

    mapping(address => bool) public alreadyNotified;

    constructor(
        address _storage,
        address _feeRewardForwarder,
        address _rewardToken
    ) public Controllable(_storage) {
        feeRewardForwarder = _feeRewardForwarder;
        rewardToken = _rewardToken;
    }

    /**
     * Notifies all the pools, safe guarding the notification amount.
     */
    function notifyPools(
        uint256[] memory amounts,
        address[] memory pools
    ) public onlyGovernance {
        require(amounts.length == pools.length, "Amounts and pools lengths mismatch");
        for (uint256 i = 0; i < pools.length; i++) {
            alreadyNotified[pools[i]] = false;
        }

        uint256 check = 0;
        for (uint256 i = 0; i < pools.length; i++) {
            require(amounts[i] > 0, "Notify zero");
            require(!alreadyNotified[pools[i]], "Duplicate pool");
            
            NoMintRewardPool pool = NoMintRewardPool(pools[i]);
            IBEP20 token = IBEP20(pool.rewardToken());
            token.transferFrom(msg.sender, pools[i], amounts[i]);

            NoMintRewardPool(pools[i]).notifyRewardAmount(amounts[i]);
            check = check.add(amounts[i]);
            alreadyNotified[pools[i]] = true;
        }
    }

    /**
     * Notifies all the pools, safe guarding the notification amount.
     */
    function notifyPoolsIncludingProfitShare(
        uint256[] memory amounts,
        address[] memory pools,
        uint256 profitShareIncentiveForWeek,
        uint256 firstProfitShareTimestamp,
        uint256 sum
    ) public onlyGovernance {
        require(amounts.length == pools.length, "Amounts and pools lengths mismatch");

        profitShareIncentiveDaily = profitShareIncentiveForWeek.div(7);
        IBEP20(rewardToken).transferFrom(msg.sender, address(this), profitShareIncentiveForWeek);
        lastProfitShareTimestamp = 0;
        notifyProfitSharing();
        lastProfitShareTimestamp = firstProfitShareTimestamp;

        notifyPools(amounts, pools);
    }

    function notifyProfitSharing() public {
        require(
            IBEP20(rewardToken).balanceOf(address(this)) >= profitShareIncentiveDaily,
            "Balance too low"
        );
        require(!(lastProfitShareTimestamp.add(24 hours) > block.timestamp), "Called too early");
        lastProfitShareTimestamp = lastProfitShareTimestamp.add(24 hours);
        IBEP20(rewardToken).approve(feeRewardForwarder, profitShareIncentiveDaily);
        IFeeRewardForwarder(feeRewardForwarder).poolNotifyFixedTarget(
            rewardToken,
            profitShareIncentiveDaily
        );
    }

    function setFeeRewardForwarder(address newForwarder) public onlyGovernance {
        feeRewardForwarder = newForwarder;
    }
}
