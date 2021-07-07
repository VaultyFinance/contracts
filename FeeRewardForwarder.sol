pragma solidity 0.6.12;

import "./Governable.sol";
import "./interfaces/IRewardPool.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "./interfaces/pancakeswap/IPancakeRouter02.sol";

contract FeeRewardForwarder is Governable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint256;

    // yield farming
    address public constant cake = address(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
    address public constant xvs = address(0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63);

    // wbnb
    address public constant wbnb = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    mapping(address => address[]) public pancakeswapRoutes;

    uint256 public hardworkSupportNumerator = 20; // 20% of profit sharing fee
    uint256 public hardworkSupportDenominator = 100;
    address payable public hardworkerAccount;

    // the targeted reward token to convert everything to
    address public targetToken;
    address public profitSharingPool;

    address public pancakeswapRouterV2; // 0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F

    event TokenPoolSet(address token, address pool);

    constructor(
        address _storage,
        address _targetToken,
        address _router,
        address payable _hardworkerAccount
    ) public Governable(_storage) {
        require(_hardworkerAccount != address(0), "pool address cannot be zero");
        targetToken = _targetToken;
        pancakeswapRouterV2 = _router;
        hardworkerAccount = _hardworkerAccount;

        pancakeswapRoutes[cake] = [cake, wbnb, _targetToken];
        pancakeswapRoutes[xvs] = [xvs, wbnb, _targetToken];
    }

    /*
     *   Set the pool that will receive the reward token
     *   based on the address of the reward Token
     */
    function setEOA(address _eoa) public onlyGovernance {
        require(_eoa != address(0), "address cannot be zero");
        profitSharingPool = _eoa;
        emit TokenPoolSet(targetToken, _eoa);
    }

    /**
     * Sets the path for swapping tokens to the to address
     * The to address is not validated to match the targetToken,
     * so that we could first update the paths, and then,
     * set the new target
     */
    function setConversionPath(address from, address[] memory _pancakeswapRoute)
        public
        onlyGovernance
    {
        require(
            from == _pancakeswapRoute[0],
            "The first token of the Pancakeswap route must be the from token"
        );
        require(
            targetToken == _pancakeswapRoute[_pancakeswapRoute.length - 1],
            "The last token of the Pancakeswap route must be the reward token"
        );

        pancakeswapRoutes[from] = _pancakeswapRoute;
    }

    // Transfers the funds from the msg.sender to the pool
    // under normal circumstances, msg.sender is the strategy
    function poolNotifyFixedTarget(address _token, uint256 _amount) external {
        // it is only used to check that the rewardPool is set.
        if (targetToken == address(0)) {
            return; // a No-op if target pool is not set yet
        }

        uint256 hardworkSupportAmount = _amount.mul(hardworkSupportNumerator).div(
            hardworkSupportDenominator
        );
        uint256 remainingAmount = _amount.sub(hardworkSupportAmount);

        liquidateToBNB(_token, hardworkSupportAmount);
        sendBnbToHardworkAccount();

        if (_token == targetToken) {
            IBEP20(_token).safeTransferFrom(msg.sender, profitSharingPool, remainingAmount);
            IRewardPool(profitSharingPool).notifyRewardAmount(remainingAmount);

        } else {
            require(
                pancakeswapRoutes[_token].length > 1,
                "FeeRewardForwarder: liquidation path doesn't exist"
            );

            // we need to convert _token to FARM
            IBEP20(_token).safeTransferFrom(msg.sender, address(this), remainingAmount);
            uint256 balanceToSwap = IBEP20(_token).balanceOf(address(this));
            liquidate(_token, balanceToSwap);

            // now we can send this token forward
            uint256 convertedRewardAmount = IBEP20(targetToken).balanceOf(address(this));

            IBEP20(targetToken).safeTransfer(profitSharingPool, convertedRewardAmount);
            IRewardPool(profitSharingPool).notifyRewardAmount(convertedRewardAmount);
            // send the token to the cross-chain converter address
        }
    }

    function liquidate(address _from, uint256 balanceToSwap) internal {
        if (balanceToSwap > 0) {
            address router = pancakeswapRouterV2;
            IBEP20(_from).safeApprove(router, 0);
            IBEP20(_from).safeApprove(router, balanceToSwap);

            IPancakeRouter02(router).swapExactTokensForTokens(
                balanceToSwap,
                0,
                pancakeswapRoutes[_from],
                address(this),
                block.timestamp
            );
        }
    }

    function sendBnbToHardworkAccount() internal {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            hardworkerAccount.transfer(balance);
        }
    }

    function liquidateToBNB(address _from, uint256 balanceToSwap) internal {
        address[] memory route = new address[](2);
        route[0] = _from;
        route[1] = wbnb;
        
        if (balanceToSwap > 0) {
            IBEP20(_from).safeTransferFrom(msg.sender, address(this), balanceToSwap);
            address router = pancakeswapRouterV2;
            IBEP20(_from).safeApprove(router, 0);
            IBEP20(_from).safeApprove(router, balanceToSwap);

            IPancakeRouter02(router).swapExactTokensForETH(
                balanceToSwap,
                0,
                route,
                address(this),
                block.timestamp
            );
        }
    }

    function setHardworkerAccount(address payable _worker) public onlyGovernance {
        require(_worker != address(0), "pool address cannot be zero");
        hardworkerAccount = _worker;
    }

    function setHardworkSupportNumerator(uint256 _amount) public onlyGovernance {
        hardworkSupportNumerator = _amount;
    }
}
