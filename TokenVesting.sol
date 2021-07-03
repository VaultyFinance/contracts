// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

contract TokenVesting {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    //token to be distributed
    IERC20Upgradeable public token;
    //handles setup
    address public setupAdmin;
    //UTC timestamp from which first vesting period begins (i.e. tokens will first be released 30 days after this time)
    uint256 public startTime;
    //total token obligations from all unpaid vesting amounts
    uint256 public totalObligations;
    //tokens can't be claimed for LOCK_PERIOD of time
    uint256 public constant LOCK_PERIOD = 120 days;
    //length of time that each vesting period lasts
    uint256 public constant VESTING_PERIOD = 90 days;
    //keeps track of contract state
    bool public setupComplete;

    //list of all beneficiaries
    address[] public beneficiaries;

    //amount of tokens to be received by each beneficiary
    mapping(address => uint256[]) public vestingAmounts;
    //tracks if addresses have already been added as beneficiaries or not
    mapping(address => bool) public beneficiaryAdded;

    event SetupCompleted();

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
        address _owner,
        uint256 _startTime
    ) public {
        token = _token;
        setupAdmin = msg.sender;
        startTime = _startTime == 0 ? block.timestamp : _startTime;
    }

    // adds a list of beneficiaries
    function addBeneficiaries(address[] memory _beneficiaries, uint256[][] memory _vestingAmounts)
        external
        onlyAdmin
        setupOnly
    {
        require(_beneficiaries.length == _vestingAmounts.length, "input length mismatch");

        uint256 _totalObligations;
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            address beneficiary = _beneficiaries[i];

            require(!beneficiaryAdded[beneficiary], "beneficiary already added");
            beneficiaryAdded[beneficiary] = true;

            uint256[] memory amountsForBeneficiary = _vestingAmounts[i];
            for (uint256 j = 0; j < amountsForBeneficiary.length; j++) {
                _totalObligations += amountsForBeneficiary[j];
            }

            beneficiaries.push(beneficiary);
            vestingAmounts[beneficiary] = amountsForBeneficiary;
        }

        totalObligations += _totalObligations;
        token.safeTransferFrom(msg.sender, address(this), _totalObligations);
    }

    // returns the active vesting period (i.e. one more than the number of
    // completed vesting periods)
    function currentVestingPeriod() public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - startTime;
        if (timeElapsed < LOCK_PERIOD) {
            return 0;
        }

        return timeElapsed / VESTING_PERIOD;
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
        token.transfer(setupAdmin, tokenBalance);
    }

    // add an array of vesting amounts to the total obligations
    function _accountForObligations(uint256[] memory _vestingAmounts) internal {
        for (uint256 j = 0; j < _vestingAmounts.length; j++) {
            totalObligations += _vestingAmounts[j];
        }
    }

    // Calculates the claimable tokens of a beneficiary and sends them.
    function _processClaim(address _beneficiary) internal {
        uint256 maxPeriodToClaim = currentVestingPeriod();
        uint256 amountToClaim = 0;
        uint256 totalAmounts = vestingAmounts[_beneficiary].length;
        if (maxPeriodToClaim > totalAmounts) {
            maxPeriodToClaim = totalAmounts;
        }

        for (uint256 i = 0; i < maxPeriodToClaim; i++) {
            uint256 amount = vestingAmounts[_beneficiary][i];
            if (amount == 0) {
                continue;
            }

            amountToClaim += amount;
            vestingAmounts[_beneficiary][i] = 0;
        }

        if (amountToClaim == 0) {
            return;
        }

        _sendTokens(_beneficiary, amountToClaim);
    }

    // send tokens to beneficiary and remove obligation
    function _sendTokens(address _beneficiary, uint256 _amountToSend) internal {
        totalObligations -= _amountToSend;
        token.transfer(_beneficiary, _amountToSend);
    }
}
