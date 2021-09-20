pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";

contract TokenSale is Ownable {
  using SafeMath for uint256;
  using SafeERC20Upgradeable for IERC20Upgradeable;

  uint256 public constant WHITELIST_DURATION = 20 minutes;
  uint256 public constant MIN_RESERVE_SIZE = 100 * (10 ** 18); // 100 BUSD
  uint256 public constant MAX_RESERVE_SIZE = 250 * (10 ** 18); // 250 BUSD
  // uint256 public constant HARD_CAP = 50000 * (10 ** 18); // 50 000 BUSD
  uint256 public constant TOKENS_PER_BUSD = 1.42857 * (10 ** 18);
  uint256 public constant VESTING_AMOUNT = 25; // 25 %
  uint256 public constant VESTING_AMOUNT_TOTAL = 100; // 100 %
  uint256 public constant VESTING_PERIOD = 30 days;
  uint256 public constant RATE_PRECISION = 10 ** 18;
  // IERC20Upgradeable constant BUSD = IERC20Upgradeable(0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47); 
  // testnet: 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56

  event Reserve(address indexed user, uint256 busd, uint256 totalReserve);
  event TokensClaimed(address indexed user, uint256 amount);

  mapping(address => uint256) public claimed;
  mapping(address => uint256) public claimTime;
  mapping(address => uint256) public reserves;
  mapping(address => bool) public whitelist;

  uint256 public totalReserve;
  IERC20Upgradeable public token;
  IERC20Upgradeable public busd;
  uint256 public hardcap;
  uint256 public startTime;
  uint256 public finishTime;
  bool public cancelled;

  modifier notCancelled() {
    require(!cancelled, "sale is cancelled");
    _;
  }

  modifier isCancelled() {
    require(cancelled, "sale is not cancelled");
    _;
  }

  modifier isStarted() {
    require(startTime != 0, "sale is not started");
    _;
  }

  modifier notStarted() {
    require(startTime == 0, "sale is started");
    _;
  }

  modifier claimAllowed() {
    require(finishTime != 0, "sale is not finished");
    _;
  }

  constructor(IERC20Upgradeable _token, IERC20Upgradeable _busd, uint256 _hardcap) public {
    token = _token;
    busd = _busd;
    hardcap = _hardcap;
  }

  // Admin control 

  function addToWhitelist(address[] memory _participants) external notCancelled onlyOwner {
    // gas is cheap!
    for (uint256 i = 0; i < _participants.length; i++) {
      whitelist[_participants[i]] = true;
    }
  }

  function cancelSale() onlyOwner external {
    cancelled = true;
  }

  // allows users to claim their tokens
  function finishSale() external isStarted onlyOwner {
    finishTime = block.timestamp;
  }

  function startSale() external notStarted onlyOwner {
    startTime = block.timestamp;
  }

  function collectFunds(address to) external claimAllowed onlyOwner {
    busd.transfer(to, busd.balanceOf(address(this)));
  }

  function reserve(uint256 busdAmount) external isStarted notCancelled {
    // if it's still a whitelist timer
    if (block.timestamp - startTime < WHITELIST_DURATION) {
      require(whitelist[msg.sender], "not whitelisted");
    }

    // check hardcap
    uint256 newTotalReserves = totalReserve.add(busdAmount);
    if (newTotalReserves > hardcap) {
      uint256 reservesDelta = newTotalReserves.sub(hardcap);
      if (reservesDelta == busdAmount) {
        // we have no space left
        revert("hardcap reached");
      }
      // we still can fit a bit
      busdAmount = busdAmount.sub(reservesDelta);
      newTotalReserves = newTotalReserves.sub(reservesDelta);
    }

    uint256 currentReserve = reserves[msg.sender];
    uint256 newReserve = currentReserve.add(busdAmount);
    require(newReserve >= MIN_RESERVE_SIZE && newReserve <= MAX_RESERVE_SIZE, "too much or too little");

    reserves[msg.sender] = newReserve;

    totalReserve = newTotalReserves;

    emit Reserve(msg.sender, busdAmount, newTotalReserves);

    busd.transferFrom(msg.sender, address(this), busdAmount);
  }

  // used to get back BUSD if sale was cancelled
  function withdrawFunds() external isCancelled {
    uint256 reserve = reserves[msg.sender];
    reserves[msg.sender] = 0;

    busd.transfer(msg.sender, reserve);
  }

  function tokensToClaim(address _beneficiary) public view returns(uint256) {
    (uint256 tokensAmount, ) = _tokensToClaim(_beneficiary);
    return tokensAmount;
  }

  /**
    @dev This function returns tokensAmount available to claim. Calculates it based on several vesting periods if applicable.
  */
  function _tokensToClaim(address _beneficiary) private view returns(uint256 tokensAmount, uint256 lastClaim) {
      uint256 tokensLeft = reserves[_beneficiary].mul(TOKENS_PER_BUSD).div(RATE_PRECISION);
      if (tokensLeft == 0) {
        return (0, 0);
      }

      lastClaim = claimTime[_beneficiary];
      bool firstClaim = false;

      if (lastClaim == 0) { // first time claim, set it to a sale finish time
          firstClaim = true;
          lastClaim = finishTime;
      }

      if (lastClaim > block.timestamp) {
          // has not started yet
          return (0, 0);
      }

      uint256 tokensClaimed = claimed[_beneficiary];
      uint256 tokensPerPeriod = tokensClaimed.add(tokensLeft).mul(VESTING_AMOUNT).div(VESTING_AMOUNT_TOTAL);
      uint256 periodsPassed = block.timestamp.sub(lastClaim).div(VESTING_PERIOD);

      // align it to period passed
      lastClaim = lastClaim.add(periodsPassed.mul(VESTING_PERIOD));

      if (firstClaim)  { // first time claim, add extra period
        periodsPassed += 1;
      }

      tokensAmount = periodsPassed.mul(tokensPerPeriod);
    }

    // claims vested tokens for a given beneficiary
    function claimFor(address _beneficiary) external claimAllowed {
        _processClaim(_beneficiary);
    }

    // convenience function for beneficiaries to call to claim all of their vested tokens
    function claimForSelf() external claimAllowed {
        _processClaim(msg.sender);
    }

    function claimForMany(address[] memory _beneficiaries) external claimAllowed {
      uint256 length = _beneficiaries.length;
      for (uint256 i = 0; i < length; i++) {
        _processClaim(_beneficiaries[i]);
      }
    }

    // Calculates the claimable tokens of a beneficiary and sends them.
    function _processClaim(address _beneficiary) internal {
        (uint256 amountToClaim, uint256 lastClaim) = _tokensToClaim(_beneficiary);

        if (amountToClaim == 0) {
            return;
        }
        claimTime[_beneficiary] = lastClaim;
        claimed[_beneficiary] = claimed[_beneficiary].add(amountToClaim);
        reserves[_beneficiary] = reserves[_beneficiary].sub(amountToClaim.mul(RATE_PRECISION).div(TOKENS_PER_BUSD));

        _sendTokens(_beneficiary, amountToClaim);

        emit TokensClaimed(_beneficiary, amountToClaim);
    }

    // send tokens to beneficiary and remove obligation
    function _sendTokens(address _beneficiary, uint256 _amountToSend) internal {
        token.safeTransfer(_beneficiary, _amountToSend);
    }
}
