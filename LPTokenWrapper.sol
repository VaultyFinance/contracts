pragma solidity 0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";

contract LPTokenWrapper {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    uint256 public constant FEE_PRECISION = 10**4;

    IBEP20 public lpToken;
    mapping(address => uint256) public stakeTimestamp;
    uint256 public withdrawDelay;
    uint256 public withdrawFee;
    address public feeCollector = address(0);

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    event WithdrawalFeeChanged(uint256 amount);
    event WithdrawalDelayChanged(uint256 delay);
    event FeeTaken(address indexed user, uint256 amount);

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function setWithdrawalDelay(uint256 delay) public virtual{
        withdrawDelay = delay;
        emit WithdrawalDelayChanged(delay);
    }

    function setWithdrawalFee(uint256 fee) public virtual{
        require(fee <= FEE_PRECISION);
        withdrawFee = fee;
        emit WithdrawalFeeChanged(fee);
    }

    function setFeeCollector(address _who) public virtual {
        require(address(0) != _who);
        feeCollector = _who;
    }

    function stakeTokens(uint256 amount) internal {
        require(amount > 0, "Cannot stake 0");
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        lpToken.safeTransferFrom(msg.sender, address(this), amount);

        stakeTimestamp[msg.sender] = block.timestamp;
    }

    function withdrawTokens(uint256 amount) internal returns (uint256, uint256) {
        require(amount > 0, "Cannot withdraw 0");
        uint256 remainingAmount = amount;
        uint256 fee;
        if (block.timestamp.sub(stakeTimestamp[msg.sender]) < withdrawDelay) {
            // if withdrawal is too early
            if (withdrawFee > 0) {
                // charge fee if set
                fee = amount.mul(withdrawFee).div(FEE_PRECISION);
                remainingAmount = amount.sub(fee);
                if (fee > 0) {
                    emit FeeTaken(msg.sender, fee);
                    lpToken.safeTransfer(feeCollector, fee);
                }
            } else {
                revert("too early");
            }
        }

        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        lpToken.safeTransfer(msg.sender, remainingAmount);
        return (remainingAmount, fee);
    }
}
