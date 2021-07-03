pragma solidity 0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "../Governable.sol";
import "../token/Lantti.sol";
import "./INftHub.sol";
import "../interfaces/IUpgradeSource.sol";
import "../ControllableInit.sol";
import "../upgradability/BaseProxyStorage.sol";

contract LanttiPools is ControllableInit, BaseProxyStorage, IUpgradeSource {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    uint256 public constant BONUS_PRECISION = 10**5;
    uint256 public constant REWARD_PRECISION = 10**12;

    // info of each user.
    struct UserInfo {
        uint256 amount; // how many tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // we do some fancy math here. basically, any point in time, the amount of LANTTI
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accLanttiPerShare) - user.rewardDebt
        //
        // whenever a user deposits or withdraws tokens to a pool. Here's what happens:
        //   1. user's pending reward is minted to his/her address.
        //   2. user's `amount` gets updated.
        //   3. user's `lastUpdate` gets updated.
    }

    // info of each pool.
    struct PoolInfo {
        IBEP20 token; // address of token contract.
        uint256 lanttiPerDay; // the amount of LANTTI per day generated for each token staked
        uint256 maxStake; // the maximum amount of tokens which can be staked in this pool
        uint256 lastUpdateTime; // last timestamp that LANTTI distribution occurs.
        uint256 accLanttiPerShare; // accumulated LANTTI per share. See below.
    }

    // info of each pool.
    PoolInfo[] public poolInfo;
    // info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // record whether the pair has been added.
    mapping(address => uint256) public tokenPID;

    Lantti public lantti;
    INftHub public hub;
    uint256 public rewardsUnit;

    event PoolCreated(address indexed token, uint256 pid);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor() public {}

    function initialize(
        address _storage,
        Lantti _lantti,
        INftHub _hub
    ) public initializer {
        ControllableInit.initialize(_storage);

        lantti = _lantti;
        hub = _hub;

        uint256 d = _lantti.decimals();
        rewardsUnit = 10**d;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // add a new token to the pool. can only be called by the owner.
    // XXX DO NOT add the same token more than once. rewards will be messed up if you do.
    function add(
        address _token,
        uint256 _lanttiPerDay,
        uint256 _maxStake
    ) public onlyGovernance {
        uint256 pid = poolInfo.length.add(1);

        require(tokenPID[_token] == 0, "duplicated pool");
        require(_token != address(lantti), "can't stake lantti");
        poolInfo.push(
            PoolInfo({
                token: IBEP20(_token),
                maxStake: _maxStake,
                lanttiPerDay: _lanttiPerDay,
                lastUpdateTime: block.timestamp,
                accLanttiPerShare: 0
            })
        );

        tokenPID[_token] = pid;

        emit PoolCreated(_token, pid);
    }

    // set a new max stake. value must be greater than previous one,
    // to not give an unfair advantage to people who already staked > new max
    function setMaxStake(uint256 pid, uint256 amount) public onlyGovernance {
        poolInfo[pid.sub(1)].maxStake = amount;
    }

    // set the amount of LANTTI generated per day for each token staked
    function setLanttiPerDay(uint256 pid, uint256 amount) public onlyGovernance {
        PoolInfo storage pool = poolInfo[pid.sub(1)];
        uint256 blockTime = block.timestamp;
        uint256 lanttiReward = blockTime.sub(pool.lastUpdateTime).mul(pool.lanttiPerDay);

        pool.accLanttiPerShare = pool.accLanttiPerShare.add(
            lanttiReward.mul(REWARD_PRECISION).div(24 hours)
        );
        pool.lastUpdateTime = block.timestamp;
        pool.lanttiPerDay = amount;
    }

    function _userPoolState(uint256 _pid, address _user)
        internal
        view
        returns (uint256 pending, uint256 accLantti)
    {
        PoolInfo storage pool = poolInfo[_pid.sub(1)];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 blockTime = block.timestamp;
        accLantti = pool.accLanttiPerShare;

        uint256 lanttiReward = blockTime.sub(pool.lastUpdateTime).mul(pool.lanttiPerDay);
        accLantti = accLantti.add(lanttiReward.mul(REWARD_PRECISION).div(24 hours));

        pending = user.amount.mul(accLantti).div(REWARD_PRECISION).sub(user.rewardDebt).div(
            rewardsUnit
        );
    }

    // view function to see pending LANTTI on a frontend.
    function pendingLantti(uint256 _pid, address _user) public view returns (uint256) {
        (uint256 pending, ) = _userPoolState(_pid, _user);
        uint256 booster = hub.getBoosterForUser(_user, _pid);
        if (booster > 0) {
            pending = pending.mul(booster.add(BONUS_PRECISION));
            pending = pending.div(BONUS_PRECISION);
        }
        return pending;
    }

    // view function to calculate the total pending LANTTI of address across all pools
    function totalPendingLantti(address _user) public view returns (uint256) {
        uint256 total = 0;
        uint256 length = poolInfo.length;
        for (uint256 pid = 1; pid <= length; ++pid) {
            total = total.add(pendingLantti(pid, _user));
        }

        return total;
    }

    // harvest pending LANTTI of a list of pools.
    // might be worth it checking in the frontend for the pool IDs with pending lantti for this address and only harvest those
    function rugPull(uint256[] memory _pids) public {
        for (uint256 i = 0; i < _pids.length; i++) {
            withdraw(_pids[i], 0, msg.sender);
        }
    }

    // deposit LP tokens to pool for LANTTI allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid.sub(1)];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 userAmount = user.amount;
        require(_amount.add(userAmount) <= pool.maxStake, "cannot stake beyond max stake value");

        (uint256 pending, uint256 accLantti) = _userPoolState(_pid, msg.sender);
        userAmount = userAmount.add(_amount);
        user.rewardDebt = userAmount.mul(accLantti).div(REWARD_PRECISION);
        user.amount = userAmount;

        uint256 booster = hub.getBoosterForUser(msg.sender, _pid).add(BONUS_PRECISION);
        uint256 pendingWithBooster = pending.mul(booster).div(BONUS_PRECISION);
        if (pendingWithBooster > 0) {
            lantti.mint(msg.sender, pendingWithBooster);
        }

        pool.token.safeTransferFrom(address(msg.sender), address(this), _amount);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // withdraw tokens from pool
    // withdrawing 0 amount will harvest rewards only
    function withdraw(
        uint256 _pid,
        uint256 _amount,
        address _staker
    ) public {
        address staker = _staker;
        PoolInfo storage pool = poolInfo[_pid.sub(1)];
        UserInfo storage user = userInfo[_pid][staker];

        uint256 userAmount = user.amount;

        if (userAmount == 0) {
            // early exit, nothing was staked to this pool
            return;
        }

        require(userAmount >= _amount, "not enough amount");
        require(msg.sender == staker || _amount == 0);

        (uint256 pending, uint256 accLantti) = _userPoolState(_pid, staker);

        // in case the maxstake has been lowered and address is above maxstake, we force it to withdraw what is above current maxstake
        // user can delay his/her withdraw/harvest to take advantage of a reducing of maxstake,
        // if he/she entered the pool at maxstake before the maxstake reducing occured
        uint256 leftAfterWithdraw = userAmount.sub(_amount);
        if (leftAfterWithdraw > pool.maxStake) {
            _amount = _amount.add(leftAfterWithdraw - pool.maxStake);
        }

        userAmount = userAmount.sub(_amount);
        user.rewardDebt = userAmount.mul(accLantti).div(REWARD_PRECISION);
        user.amount = userAmount;

        uint256 booster = hub.getBoosterForUser(staker, _pid).add(BONUS_PRECISION);
        uint256 pendingWithBooster = pending.mul(booster).div(BONUS_PRECISION);
        if (pendingWithBooster > 0) {
            lantti.mint(staker, pendingWithBooster);
        }

        pool.token.safeTransfer(address(staker), _amount);
        emit Withdraw(staker, _pid, _amount);
    }

    // withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid.sub(1)];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount > 0, "not enough amount");

        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.token.safeTransfer(address(msg.sender), _amount);

        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    // update hub address if the booster logic changed.
    function updateNftHubAddress(INftHub _hub) public onlyGovernance {
        hub = _hub;
    }

    function scheduleUpgrade(address impl) public onlyGovernance {
        _setNextImplementation(impl);
        _setNextImplementationTimestamp(block.timestamp.add(nextImplementationDelay()));
    }

    function shouldUpgrade() external view override returns (bool, address) {
        return (
            nextImplementationTimestamp() != 0 &&
                block.timestamp > nextImplementationTimestamp() &&
                nextImplementation() != address(0),
            nextImplementation()
        );
    }

    function finalizeUpgrade() external override onlyGovernance {
        _setNextImplementation(address(0));
        _setNextImplementationTimestamp(0);
    }
}
