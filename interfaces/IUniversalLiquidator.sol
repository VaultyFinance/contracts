
pragma solidity 0.6.12;

interface IUniversalLiquidator {
  event Swap(
    address indexed buyToken,
    address indexed sellToken,
    address indexed target,
    address initiator,
    uint256 amountIn,
    uint256 slippage
  );

  function swapTokenOnMultipleDEXes(
    uint256 amountIn,
    uint256 amountOutMin,
    address target,
    bytes32[] calldata dexes,
    address[] calldata path
  ) external returns (uint256);

  function swapTokenOnDEX(
    uint256 amountIn,
    uint256 amountOutMin,
    address target,
    bytes32 dexName,
    address[] calldata path
  ) external;

  function getAllDexes() external view returns (bytes32[] memory);
}
