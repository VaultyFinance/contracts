pragma solidity 0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";

contract LPTokenWrapper {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    uint256 public constant FEE_PRECISION = 10 ** 4;

    IBEP20 public lpToken;
    mapping(address => uint256) public stakeTimestamp;
    uint256 public withdrawDelay;
    uint256 public withdrawFee;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function setWithdrawalDelay(uint256 delay) public virtual {
        withdrawDelay = delay;
    }

    function setWithdrawalFee(uint256 fee) public virtual {
        require(fee <= FEE_PRECISION);
        withdrawFee = fee;
    }

    function stakeTokens(uint256 amount) internal {
        require(amount > 0, "Cannot stake 0");
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        lpToken.safeTransferFrom(msg.sender, address(this), amount);

        stakeTimestamp[msg.sender] = block.timestamp;
    }

    function withdrawTokens(uint256 amount) internal returns(uint256) {
        require(amount > 0, "Cannot withdraw 0");

        if (block.timestamp.sub(stakeTimestamp[msg.sender]) < withdrawDelay) {
            // if withdrawal is too early
            if (withdrawFee > 0) {
                // charge fee if set
                amount = amount.mul(FEE_PRECISION.sub(withdrawFee)).div(FEE_PRECISION);
            } else {
                revert("too early");
            }
        }

        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        lpToken.safeTransfer(msg.sender, amount);
        return amount;
    }
}
