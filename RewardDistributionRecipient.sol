pragma solidity 0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";

abstract contract RewardDistributionRecipient is Ownable {
    address public rewardDistribution;
    
    event RewardDistributuionChanged(address _address);

    constructor(address _rewardDistribution) public {
        require(_rewardDistribution != address(0), 'pool address cannot be zero');
        rewardDistribution = _rewardDistribution;
    }

    function notifyRewardAmount(uint256 reward) external virtual;

    modifier onlyRewardDistribution() {
        require(_msgSender() == rewardDistribution, "Caller is not reward distribution");
        _;
    }

    function setRewardDistribution(address _rewardDistribution) external onlyOwner {
        require(_rewardDistribution != address(0), 'pool address cannot be zero');
        rewardDistribution = _rewardDistribution;
        emit RewardDistributuionChanged(_rewardDistribution);
    }
}
