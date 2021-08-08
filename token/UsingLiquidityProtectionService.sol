// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IPLPS {
    function LiquidityProtection_beforeTokenTransfer(
        address _pool, address _from, address _to, uint _amount) external;
    function isBlocked(address _pool, address _who) external view returns(bool);
    function unblock(address _pool, address _who) external;
}

abstract contract UsingLiquidityProtectionService {
    bool private unProtected = false;
    IPLPS private plps;
    bytes32 internal constant PANCAKESWAP =
        0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5;


    modifier onlyProtectionAdmin() {
        protectionAdminCheck();
        _;
    }

    constructor(address _plps) public {
        plps = IPLPS(_plps);
    }

    function LiquidityProtection_setLiquidityProtectionService(IPLPS _plps)
        external
        onlyProtectionAdmin
    {
        plps = _plps;
    }

    function token_transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual;

    function protectionAdminCheck() internal view virtual;

    function token_balanceOf(address holder) internal view virtual returns (uint256);

    function uniswapVariety() internal pure virtual returns (bytes32);

    function uniswapFactory() internal pure virtual returns (address);

    function counterToken() internal pure virtual returns (address);

    function protectionChecker() internal view virtual returns (bool) {
        return ProtectionSwitch_manual();
    }

    function lps() private view returns (IPLPS) {
        return plps;
    }

    function LiquidityProtection_beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal virtual {
        if (protectionChecker()) {
            if (unProtected) {
                return;
            }
            lps().LiquidityProtection_beforeTokenTransfer(getLiquidityPool(), _from, _to, _amount);
        }
    }

    function revokeBlocked(address[] calldata _holders, address _revokeTo)
        external
        onlyProtectionAdmin
    {
        require(protectionChecker(), "UsingLiquidityProtectionService: protection removed");
        unProtected = true;
        address pool = getLiquidityPool();
        for (uint256 i = 0; i < _holders.length; i++) {
            address holder = _holders[i];
            if (lps().isBlocked(pool, holder)) {
                token_transfer(holder, _revokeTo, token_balanceOf(holder));
            }
        }
        unProtected = false;
    }

    function LiquidityProtection_unblock(address[] calldata _holders) external onlyProtectionAdmin {
        require(protectionChecker(), "UsingLiquidityProtectionService: protection removed");
        address pool = getLiquidityPool();
        for (uint256 i = 0; i < _holders.length; i++) {
            lps().unblock(pool, _holders[i]);
        }
    }

    function disableProtection() external onlyProtectionAdmin {
        unProtected = true;
    }

    function isProtected() public view returns (bool) {
        return not(unProtected);
    }

    function ProtectionSwitch_manual() internal view returns (bool) {
        return isProtected();
    }

    function ProtectionSwitch_timestamp(uint256 _timestamp) internal view returns (bool) {
        return not(passed(_timestamp));
    }

    function ProtectionSwitch_block(uint256 _block) internal view returns (bool) {
        return not(blockPassed(_block));
    }

    function blockPassed(uint256 _block) internal view returns (bool) {
        return _block < block.number;
    }

    function passed(uint256 _timestamp) internal view returns (bool) {
        return _timestamp < block.timestamp;
    }

    function not(bool _condition) internal pure returns (bool) {
        return !_condition;
    }

    function sortTokens(address tokenA, address tokenB)
        internal
        pure
        returns (address token0, address token1)
    {
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(
        bytes32 initCodeHash,
        address factory,
        address tokenA,
        address tokenB
    ) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex"ff",
                        factory,
                        keccak256(abi.encodePacked(token0, token1)),
                        initCodeHash // init code hash
                    )
                )
            )
        );
    }

    function getLiquidityPool() public view returns (address) {
        return pairFor(uniswapVariety(), uniswapFactory(), address(this), counterToken());
    }
}
