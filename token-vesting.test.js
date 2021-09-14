/* eslint-disable space-before-function-paren */
/* eslint-disable no-undef */
const Utils = require('./utils.js')
const { expectRevert, send, time, expectEvent } = require('@openzeppelin/test-helpers')
const BigNumber = require('bignumber.js')
const Deployer = require('./deployer')

const { web3 } = require('@openzeppelin/test-helpers/src/setup')
const { artifacts } = require('hardhat')
const toWei = web3.utils.toWei
const toBN = web3.utils.toBN

BigNumber.config({ DECIMAL_PLACES: 0 })

const DAY_DURATION = 86400

const now = async() => (await web3.eth.getBlock('latest')).timestamp

contract('Token Vesting', () => {
  async function deployVesting() {
    this.vesting = await Deployer.deploy(
      artifacts.require('TokenVesting'),
      this.rewardToken.address,
      this.startTime,
      this.lockingPeriod,
      { from: this.admin }
    )
  }

  async function setup() {
    const accounts = await web3.eth.getAccounts()
    this.admin = accounts[0]
    this.user = accounts[1]

    this.rewardToken = await Deployer.deployRewardToken(this.admin)

    if (this.rewardToken.disableProtection) {
      await this.rewardToken.disableProtection()
    }
  }

  async function addBeneficiaries() {
    let totalAmount = toBN('0')
    for (const vesting of this.vestings) {
      for (const entry of vesting) {
        totalAmount = totalAmount.add(
          toBN(entry.tokensPerDay).mul(
            toBN(entry.vestingDays)
          )
        )
      }
    }

    await this.rewardToken.mint(this.admin, totalAmount, { from: this.admin })
    await this.rewardToken.approve(this.vesting.address, totalAmount, { from: this.admin })

    await this.vesting.addBeneficiaries(this.beneficiaries, this.vestings, { from: this.admin })
    await this.vesting.endSetup({ from: this.admin })
  }

  describe('tokensToClaim', function() {
    describe('typical vesting schedule', function() {
      before(setup)
      before(function() {
        this.lockingPeriod = 0
        this.startTime = 0
        this.beneficiaries = [this.user]
        this.vestings = [[{ tokensPerDay: toWei('1'), vestingDays: '1' }, { tokensPerDay: '0', vestingDays: '7' }, { tokensPerDay: toWei('1'), vestingDays: '1' }]]
      })
      before(deployVesting)
      before(addBeneficiaries)

      describe('when 1 day passed', function() {
        before(async function() {
          await time.advanceBlock()
          await time.increase(DAY_DURATION)
        })

        it('should have correct claimable amount', async function() {
          const tokensToClaim = await this.vesting.tokensToClaim(this.beneficiaries[0])
          Utils.assertBNEq(tokensToClaim, this.vestings[0][0].tokensPerDay)
        })
      })

      describe('when 7 days passed', function() {
        before(async function() {
          await time.advanceBlock()
          await time.increase(DAY_DURATION * 7)
        })

        it('should have correct claimable amount', async function() {
          const tokensToClaim = await this.vesting.tokensToClaim(this.beneficiaries[0])
          Utils.assertBNEq(tokensToClaim, this.vestings[0][0].tokensPerDay)
        })
      })

      describe('when 1 day passed', function() {
        before(async function() {
          await time.advanceBlock()
          await time.increase(DAY_DURATION)
        })

        it('should have correct claimable amount', async function() {
          const tokensToClaim = await this.vesting.tokensToClaim(this.beneficiaries[0])
          Utils.assertBNEq(tokensToClaim, toBN(this.vestings[0][0].tokensPerDay).add(toBN(this.vestings[0][2].tokensPerDay)))
        })
      })
    })

    describe('when locking period is 0 and vesting period is 10 days', function() {
      before(setup)
      before(function() {
        this.lockingPeriod = 0
        this.startTime = 0
        this.beneficiaries = [this.user]
        this.vestings = [[{ tokensPerDay: toWei('1'), vestingDays: '10' }]]
      })
      before(deployVesting)
      before(addBeneficiaries)

      describe('when 1 day passed', function() {
        before(async function() {
          await time.advanceBlock()
          await time.increase(DAY_DURATION)
        })

        it('should have correct claimable amount', async function() {
          const tokensToClaim = await this.vesting.tokensToClaim(this.beneficiaries[0])
          Utils.assertBNEq(tokensToClaim, this.vestings[0][0].tokensPerDay)
        })
      })

      describe('when 10 days passed', function() {
        before(async function() {
          await time.advanceBlock()
          await time.increase(DAY_DURATION * 9)
        })

        it('should have correct claimable amount', async function() {
          const tokensToClaim = await this.vesting.tokensToClaim(this.beneficiaries[0])
          Utils.assertBNEq(tokensToClaim, this.vestings[0][0].tokensPerDay * 10)
        })
      })

      describe('when 30 days passed', function() {
        before(async function() {
          await time.advanceBlock()
          await time.increase(DAY_DURATION * 20)
        })

        it('should have correct claimable amount', async function() {
          const tokensToClaim = await this.vesting.tokensToClaim(this.beneficiaries[0])
          Utils.assertBNEq(tokensToClaim, this.vestings[0][0].tokensPerDay * 10)
        })
      })
    })

    describe('when locking period is 10 days', function() {
      before(setup)
      before(function() {
        this.lockingPeriod = 10
        this.startTime = 0
        this.beneficiaries = [this.user]
        this.vestings = [[{ tokensPerDay: toWei('1'), vestingDays: '10' }]]
      })
      before(deployVesting)
      before(addBeneficiaries)

      describe('when locking period is not finished', function() {
        before(async function() {
          await time.advanceBlock()
          await time.increase(DAY_DURATION * this.lockingPeriod)
        })

        it('should not have any tokens to claim', async function() {
          const tokensToClaim = await this.vesting.tokensToClaim(this.beneficiaries[0])
          Utils.assertBNEq(tokensToClaim, '0')
        })
      })

      describe('when 1 day passed beyond locking period', function() {
        before(async function() {
          await time.advanceBlock()
          await time.increase(DAY_DURATION)
        })

        it('should have correct claimable amount', async function() {
          const tokensToClaim = await this.vesting.tokensToClaim(this.beneficiaries[0])
          Utils.assertBNEq(tokensToClaim, this.vestings[0][0].tokensPerDay)
        })
      })

      describe('when vesting has individual lock period', function() {
        before(setup)
        before(function() {
          this.lockingPeriod = 0
          this.startTime = 0
          this.beneficiaries = [this.user]
          this.vestings = [[{ tokensPerDay: toWei('0'), vestingDays: '10' }, { tokensPerDay: toWei('1'), vestingDays: '10' }]]
        })
        before(deployVesting)
        before(addBeneficiaries)

        describe('when first empty vesting period is not finished', function() {
          before(async function() {
            await time.advanceBlock()
            await time.increase(DAY_DURATION * 9)
          })

          it('should have 0 claimable amount', async function() {
            const tokensToClaim = await this.vesting.tokensToClaim(this.beneficiaries[0])
            Utils.assertBNEq(tokensToClaim, '0')
          })
        })

        describe('when time passed beyond whole vesting period', function() {
          before(async function() {
            await time.advanceBlock()
            await time.increase(DAY_DURATION * 20)
          })

          it('should have correct claimable amount', async function() {
            const tokensToClaim = await this.vesting.tokensToClaim(this.beneficiaries[0])
            Utils.assertBNEq(tokensToClaim, toWei('10'))
          })
        })
      })
    })

    describe('when locking period is 0 days', function() {
      before(setup)
      before(function() {
        this.lockingPeriod = 10
        this.startTime = 0
        this.beneficiaries = [this.user]
        this.vestings = [[{ tokensPerDay: toWei('1'), vestingDays: '10' }]]
      })
      before(deployVesting)
      before(addBeneficiaries)

      describe('when locking period is not finished', function() {
        before(async function() {
          await time.advanceBlock()
          await time.increase(DAY_DURATION * this.lockingPeriod)
        })

        it('should not have any tokens to claim', async function() {
          const tokensToClaim = await this.vesting.tokensToClaim(this.beneficiaries[0])
          Utils.assertBNEq(tokensToClaim, '0')
        })
      })

      describe('when 1 day passed beyond locking period', function() {
        before(async function() {
          await time.advanceBlock()
          await time.increase(DAY_DURATION)
        })

        it('should have correct claimable amount', async function() {
          const tokensToClaim = await this.vesting.tokensToClaim(this.beneficiaries[0])
          Utils.assertBNEq(tokensToClaim, this.vestings[0][0].tokensPerDay)
        })
      })
    })

    describe('when TGE is required', function() {
      before(setup)
      before(async function() {
        // TGE is 2 days since now
        this.lockingPeriod = 0
        this.startTime = await now() + DAY_DURATION // set start time as TGE date - 1 day
        this.beneficiaries = [this.user]
        this.vestings = [[{ tokensPerDay: toWei('1'), vestingDays: '1' }, { tokensPerDay: toWei('0'), vestingDays: '10' }]]
      })
      before(deployVesting)
      before(addBeneficiaries)

      describe('when start time is not passed', function() {
        it('should not have any tokens to claim', async function() {
          const tokensToClaim = await this.vesting.tokensToClaim(this.beneficiaries[0])
          Utils.assertBNEq(tokensToClaim, '0')
        })
      })

      describe('when TGE time arrives', async function() {
        before(async function() {
          await time.advanceBlock()
          await time.increase(DAY_DURATION * 2) // 2 days elapsed
        })

        it('should have correct claimable amount', async function() {
          const tokensToClaim = await this.vesting.tokensToClaim(this.user)
          Utils.assertBNEq(tokensToClaim, this.vestings[0][0].tokensPerDay)
        })

        it('should claim amount', async function() {
          await this.vesting.claimFor(this.user, { from: this.user })
          Utils.assertBNEq(
            await this.rewardToken.balanceOf(this.user),
            this.vestings[0][0].tokensPerDay
          )
        })

        it('should have correct claimable amount', async function() {
          const tokensToClaim = await this.vesting.tokensToClaim(this.user)
          Utils.assertBNEq(tokensToClaim, '0')
        })
      })
    })
  })

  describe('claimFor', function() {
    describe('when user claims several times.', function() {
      let expectedTokens = toBN('0')
      before(setup)
      before(function() {
        this.lockingPeriod = 0
        this.startTime = 0
        this.beneficiaries = [this.user]
        this.vestings = [[{ tokensPerDay: toWei('1'), vestingDays: '10' }, { tokensPerDay: '0', vestingDays: '7' }, { tokensPerDay: toWei('1'), vestingDays: '1' }]]
      })
      before(deployVesting)
      before(addBeneficiaries)

      describe('when 1 day passed', function() {
        before(async function() {
          await time.increase(DAY_DURATION)
          expectedTokens = expectedTokens.add(toBN(this.vestings[0][0].tokensPerDay))
        })

        it('should claim token worth of 1 day', async function() {
          await this.vesting.claimFor(this.user, { from: this.user })
          Utils.assertBNEq(
            await this.rewardToken.balanceOf(this.user),
            expectedTokens
          )
        })
      })

      describe('when the rest of the first period passed', async function() {
        before(async function() {
          await time.increase(DAY_DURATION * 9)
          expectedTokens = toBN(this.vestings[0][0].tokensPerDay * 10)
        })

        it('should claim the rest of the tokens', async function() {
          await this.vesting.claimFor(this.user, { from: this.user })
          Utils.assertBNEq(
            await this.rewardToken.balanceOf(this.user),
            expectedTokens
          )
        })
      })

      describe('when the rest the second period passed', async function() {
        before(async function() {
          await time.increase(DAY_DURATION * 7)
        })

        it('should claim nothing', async function() {
          await this.vesting.claimFor(this.user, { from: this.user })
          Utils.assertBNEq(
            await this.rewardToken.balanceOf(this.user),
            expectedTokens
          )
        })
      })

      describe('when the rest of the third period passed', async function() {
        before(async function() {
          await time.increase(DAY_DURATION)
          expectedTokens = expectedTokens.add(toBN(this.vestings[0][2].tokensPerDay))
        })

        it('should claim the rest of the tokens', async function() {
          await this.vesting.claimFor(this.user, { from: this.user })
          Utils.assertBNEq(
            await this.rewardToken.balanceOf(this.user),
            expectedTokens
          )
        })
      })

      describe('when 20 days passed beyond the last vesting day', function() {
        before(async function() {
          await time.increase(DAY_DURATION * 20)
        })

        it('should not claim any more tokens', async function() {
          await this.vesting.claimFor(this.user, { from: this.user })
          Utils.assertBNEq(
            await this.rewardToken.balanceOf(this.user),
            expectedTokens
          )
        })
      })
    })
  })
})
