pragma solidity 0.6.12;

interface IFeeRewardForwarderV6 {
    function poolNotifyFixedTarget(address _token, uint256 _amount) external;

    function notifyFeeAndBuybackAmounts(uint256 _feeAmount, address _pool, uint256 _buybackAmount) external;
    function notifyFeeAndBuybackAmounts(address _token, uint256 _feeAmount, address _pool, uint256 _buybackAmount) external;
    function profitSharingPool() external view returns (address);
}
