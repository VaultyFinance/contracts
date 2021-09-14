// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

contract TokenVesting {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;
    using SafeMathUpgradeable for uint64;
    using SafeMathUpgradeable for uint128;

    struct VestingPeriod {
        uint128 vestingDays;
        uint128 tokensPerDay;
    }

    struct VestingClaimInfo {
        uint128 lastClaim;
        uint64 periodIndex;
        uint64 daysClaimed;
    }

    //token to be distributed
    IERC20Upgradeable public token;
    //handles setup
    address public setupAdmin;
    //UTC timestamp from which first vesting period begins (i.e. tokens will first be released 30 days after this time)
    uint256 public startTime;
    //total token obligations from all unpaid vesting amounts
    uint256 public totalObligations;
    //tokens can't be claimed for lockingPeriod days
    uint256 public lockingPeriod;
    //keeps track of contract state
    bool public setupComplete;

    //list of all beneficiaries
    address[] public beneficiaries;

    //amount of tokens to be received by each beneficiary
    mapping(address => VestingPeriod[]) public vestingPeriods;
    mapping(address => VestingClaimInfo) public claimInfo;
    //tracks if addresses have already been added as beneficiaries or not
    mapping(address => bool) public beneficiaryAdded;

    event SetupCompleted();
    event BeneficiaryAdded(address indexed user, uint256 totalAmountToClaim);
    event TokensClaimed(address indexed user, uint256 amount);

    modifier setupOnly() {
        require(!setupComplete, "setup already completed");
        _;
    }

    modifier claimAllowed() {
        require(setupComplete, "setup ongoing");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == setupAdmin, "not admin");
        _;
    }

    constructor(
        IERC20Upgradeable _token,
        uint256 _startTime,
        uint256 _lockingPeriod
    ) public {
        token = _token;
        lockingPeriod = _lockingPeriod;
        setupAdmin = msg.sender;
        startTime = _startTime == 0 ? block.timestamp : _startTime;
    }

    // adds a list of beneficiaries
    function addBeneficiaries(address[] memory _beneficiaries, VestingPeriod[][] memory _vestingPeriods)
        external
        onlyAdmin
        setupOnly
    {
        require(_beneficiaries.length == _vestingPeriods.length, "input length mismatch");

        uint256 _totalObligations;
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            address beneficiary = _beneficiaries[i];

            require(!beneficiaryAdded[beneficiary], "beneficiary already added");
            beneficiaryAdded[beneficiary] = true;

            uint256 amountToClaim;

            VestingPeriod[] memory periods = _vestingPeriods[i];
            for (uint256 j = 0; j < periods.length; j++) {
                VestingPeriod memory period = periods[j];
                amountToClaim = amountToClaim.add(
                    uint256(period.vestingDays).mul(
                        uint256(period.tokensPerDay)
                    )
                );
                vestingPeriods[beneficiary].push(period);
            }

            beneficiaries.push(beneficiary);
            _totalObligations = _totalObligations.add(amountToClaim);

            emit BeneficiaryAdded(beneficiary, amountToClaim);
        }

        totalObligations = totalObligations.add(_totalObligations);
        token.safeTransferFrom(msg.sender, address(this), _totalObligations);
    }

    function tokensToClaim(address _beneficiary) public view returns(uint256) {        
        (uint256 tokensAmount,,) = _tokensToClaim(_beneficiary, claimInfo[_beneficiary]);
        return tokensAmount;
    }

    /**
        @dev This function returns tokensAmount available to claim. Calculates it based on several vesting periods if applicable.
     */
    function _tokensToClaim(address _beneficiary, VestingClaimInfo memory claim) private view returns(uint256 tokensAmount, uint256 daysClaimed, uint256 periodIndex) {
        uint256 lastClaim = claim.lastClaim;
        if (lastClaim == 0) { // first time claim, set it to a contract start time
            lastClaim = startTime;
        }

        if (lastClaim > block.timestamp) {
            // has not started yet
            return (0, 0, 0);
        }

        uint256 daysElapsed = (block.timestamp.sub(lastClaim)).div(1 days);

        if (claim.lastClaim == 0)  { // first time claim
            // check for lock period
            if (daysElapsed > lockingPeriod) {
                // passed beyond locking period, adjust elapsed days by locking period
                daysElapsed = daysElapsed.sub(lockingPeriod);
            } else {
                // tokens are locked
                return (0, 0, 0);
            }
        }

        periodIndex = uint256(claim.periodIndex);
        uint256 totalPeriods = vestingPeriods[_beneficiary].length;

        // it's safe to assume that admin won't setup contract in such way, that this loop will be out of gas
        while (daysElapsed > 0 && totalPeriods > periodIndex) {
            VestingPeriod memory vestingPeriod = vestingPeriods[_beneficiary][periodIndex];

            daysClaimed = claim.daysClaimed;

            uint256 daysInPeriodToClaim = uint256(vestingPeriod.vestingDays).sub(claim.daysClaimed);
            if (daysInPeriodToClaim > daysElapsed) {
                daysInPeriodToClaim = daysElapsed;
            }

            tokensAmount = tokensAmount.add(
                uint256(vestingPeriod.tokensPerDay).mul(daysInPeriodToClaim)
            );

            daysElapsed = daysElapsed.sub(daysInPeriodToClaim);
            daysClaimed = daysClaimed.add(daysInPeriodToClaim);
            // at this point, if any days left to claim, it means that period was consumed
            // move to the next period
            claim.daysClaimed = 0;
            periodIndex++;
        }

        periodIndex--;
    }

    // claims vested tokens for a given beneficiary
    function claimFor(address _beneficiary) external claimAllowed {
        _processClaim(_beneficiary);
    }

    // convenience function for beneficiaries to call to claim all of their vested tokens
    function claimForSelf() external claimAllowed {
        _processClaim(msg.sender);
    }

    // claims vested tokens for all beneficiaries
    function claimForAll() external claimAllowed {
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            _processClaim(beneficiaries[i]);
        }
    }

    // complete setup once all obligations are met, to remove the ability to
    // reclaim tokens until vesting is complete, and allow claims to start
    function endSetup() external onlyAdmin setupOnly {
        uint256 tokenBalance = token.balanceOf(address(this));
        require(tokenBalance >= totalObligations, "obligations not yet met");
        setupComplete = true;
        setupAdmin = address(0);
        emit SetupCompleted();
    }

    // reclaim tokens if necessary prior to finishing setup. otherwise reclaim any
    // extra tokens after the end of vesting
    function reclaimTokens() external onlyAdmin setupOnly {
        uint256 tokenBalance = token.balanceOf(address(this));
        token.safeTransfer(setupAdmin, tokenBalance);
    }

    // Calculates the claimable tokens of a beneficiary and sends them.
    function _processClaim(address _beneficiary) internal {
        VestingClaimInfo memory claim = claimInfo[_beneficiary];
        (uint256 amountToClaim, uint256 daysClaimed, uint256 periodIndex) = _tokensToClaim(_beneficiary, claim);

        if (amountToClaim == 0) {
            return;
        }

        claim.daysClaimed = uint64(daysClaimed);
        claim.lastClaim = uint128(block.timestamp);
        claim.periodIndex = uint64(periodIndex);
        claimInfo[_beneficiary] = claim;

        _sendTokens(_beneficiary, amountToClaim);

        emit TokensClaimed(_beneficiary, amountToClaim);
    }

    // send tokens to beneficiary and remove obligation
    function _sendTokens(address _beneficiary, uint256 _amountToSend) internal {
        totalObligations = totalObligations.sub(_amountToSend);
        token.safeTransfer(_beneficiary, _amountToSend);
    }
}
