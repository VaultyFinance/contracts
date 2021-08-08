pragma solidity 0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";

contract Presale is Ownable {
  using SafeMath for uint256;

  uint256 public constant WHITELIST_DURATION = 6 hours;
  uint256 public constant MIN_RESERVE_SIZE = 100 * (10 ** 18); // 100 BUSD
  uint256 public constant MAX_RESERVE_SIZE = 250 * (10 ** 18); // 250 BUSD
  uint256 public constant HARD_CAP = 50000 * (10 ** 18); // 50 000 BUSD
  uint256 public constant TOKENS_PER_BUSD = 1.42857 * (10 ** 18);
  IBEP20 constant BUSD = IBEP20(0x8301F2213c0eeD49a7E28Ae4c3e91722919B8B47); //testnet: 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56

  event Reserve(address indexed user, uint256 busd, uint256 totalReserve);
  event TokensClaimed(address indexed user, uint256 amount);

  mapping(address => uint256) public reserves;
  mapping(address => bool) public whitelist;

  uint256 public totalReserve;
  IBEP20 public token;
  uint256 public startTime;
  bool public canClaim;
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

  constructor(IBEP20 _token) public {
    token = _token;
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
    canClaim = true;
  }

  function startSale() external notStarted onlyOwner {
    startTime = block.timestamp;
  }

  function collectFunds(address to) external onlyOwner {
    require(canClaim, "sale is ongoing");

    BUSD.transfer(to, BUSD.balanceOf(address(this)));
  }

  // Public methods

  function claimTokens() external notCancelled {
    require(canClaim, "can't claim tokens yet");

    uint256 tokensAmount = reserves[msg.sender].mul(TOKENS_PER_BUSD).div(10 ** 18);
    reserves[msg.sender] = 0;

    emit TokensClaimed(msg.sender, tokensAmount);

    token.transfer(msg.sender, tokensAmount);
  }

  function reserve(uint256 busdAmount) external isStarted notCancelled {
    // if it's still a whitelist timer
    if (block.timestamp - startTime < WHITELIST_DURATION) {
      require(whitelist[msg.sender], "not whitelisted");
    }

    // check hardcap
    uint256 newTotalReserves = totalReserve.add(busdAmount);
    if (newTotalReserves > HARD_CAP) {
      uint256 reservesDelta = newTotalReserves.sub(totalReserve);
      if (reservesDelta <= busdAmount) {
        // we have no space left
        revert("hardcap reached");
      }

      // we still can fit a bit
      busdAmount = busdAmount.sub(
        reservesDelta.sub(busdAmount)
      );
    }

    uint256 currentReserve = reserves[msg.sender];
    uint256 newReserve = currentReserve.add(busdAmount);
    require(newReserve >= MIN_RESERVE_SIZE && newReserve <= MAX_RESERVE_SIZE, "too much or too little");

    reserves[msg.sender] = newReserve;

    totalReserve = newTotalReserves;

    emit Reserve(msg.sender, busdAmount, newTotalReserves);

    BUSD.transferFrom(msg.sender, address(this), busdAmount);
  }

  // used to get back BUSD if sale was cancelled
  function withdrawFunds() external isCancelled {
    uint256 reserve = reserves[msg.sender];
    reserves[msg.sender] = 0;

    BUSD.transfer(msg.sender, reserve);
  }
}
