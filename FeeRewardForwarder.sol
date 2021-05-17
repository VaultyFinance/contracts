

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
  address constant public cake = address(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
  address constant public xvs = address(0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63);

  // wbnb
  address constant public wbnb = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

  mapping (address => address[]) public pancakeswapRoutes;

  // the targeted reward token to convert everything to
  address public targetToken;
  address public profitSharingPool;

  address public pancakeswapRouterV2; // 0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F

  event TokenPoolSet(address token, address pool);

  constructor(
    address _storage, 
    address _targetToken,
    address _router
  ) public Governable(_storage) {
    targetToken = _targetToken;
    pancakeswapRouterV2 = _router;

    pancakeswapRoutes[cake] = [cake, wbnb, _targetToken];
    pancakeswapRoutes[xvs] = [xvs, wbnb, _targetToken];
  }

  /*
  *   Set the pool that will receive the reward token
  *   based on the address of the reward Token
  */
  function setEOA(address _eoa) public onlyGovernance {
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
    uint256 remainingAmount = _amount;
    address _targetToken = targetToken;
    // it is only used to check that the rewardPool is set.
    if (_targetToken == address(0)) {
      return; // a No-op if target pool is not set yet
    }

    if (_token == _targetToken) {
      // this is already the right token
      // Note: Under current structure, this would be FARM.
      // This would pass on the grain buy back as it would be the special case
      // designed for NotifyHelper calls
      // This is assuming that NO strategy would notify profits in FARM

      IBEP20(_token).safeTransferFrom(msg.sender, profitSharingPool, _amount);
      IRewardPool(profitSharingPool).notifyRewardAmount(_amount);

      // send the _amount of wbnb to the cross-chain converter
    } else {

      // we need to convert _token to FARM
      if (pancakeswapRoutes[_token].length > 1) {
        IBEP20(_token).safeTransferFrom(msg.sender, address(this), remainingAmount);
        uint256 balanceToSwap = IBEP20(_token).balanceOf(address(this));
        liquidate(_token, balanceToSwap);

        // now we can send this token forward
        uint256 convertedRewardAmount = IBEP20(_targetToken).balanceOf(address(this));

        IBEP20(_targetToken).safeTransfer(profitSharingPool, convertedRewardAmount);
        IRewardPool(profitSharingPool).notifyRewardAmount(convertedRewardAmount);

        // send the token to the cross-chain converter address
      } else {
        // else the route does not exist for this token
        // do not take any fees and revert.
        // It's better to set the liquidation path then perform it again,
        // rather then leaving the funds in controller
        revert("FeeRewardForwarder: liquidation path doesn't exist");
      }
    }
  }

  function liquidate(address _from, uint256 balanceToSwap) internal {
    if(balanceToSwap > 0){
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
}
