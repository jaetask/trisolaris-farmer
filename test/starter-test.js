const hre = require('hardhat');
const chai = require('chai');
const {solidity} = require('ethereum-waffle');
const {findPoolByName} = require('../pools');

chai.use(solidity);
const {expect} = chai;
const {ethers, network} = hre;

/**
 * How to get the top holders for a token on Aurora
 * https://aurorascan.dev/token/0x61C9E05d1Cdb1b70856c7a2c53fA9c220830633c#balances
 */

const moveTimeForward = async (seconds) => {
  await network.provider.send('evm_increaseTime', [seconds]);
  await network.provider.send('evm_mine');
};

// use with small values in case harvest is block-dependent instead of time-dependent
const moveBlocksForward = async (blocks) => {
  for (let i = 0; i < blocks; i++) {
    await network.provider.send('evm_increaseTime', [1]);
    await network.provider.send('evm_mine');
  }
};

// todo: we also have USDT on this farm
const toWantUnit = (num, isUSDC = false) => {
  if (isUSDC) {
    return ethers.BigNumber.from(num * 10 ** 8);
  }
  return ethers.utils.parseEther(num);
};

describe('Vaults', function () {
  let Vault;
  let vault;

  let Strategy;
  let strategy;

  let Want;
  let want;

  let whale;

  const testPool = findPoolByName('wNEAR-ETH');
  const {wantAddress, wantHolderAddr, poolId, checkPoolExists, tokenName, tokenSymbol} = testPool;
  const treasuryAddr = '0x0e7c5313E9BB80b654734d9b7aB1FB01468deE3b';
  const paymentSplitterAddress = '0x65e45d2f3f43b613416614c73f18fdd3aa2b8391';
  const strategistAddr = '0x6ca3052E6D4b46c3437FA4C7235A0907805aaeC8';
  const whaleAddress = '0xb0bD02F6a392aF548bDf1CfAeE5dFa0EefcC8EaB';
  const triTokenAddress = '0xFa94348467f64D5A457F75F8bc40495D33c65aBB';

  let owner;
  let wantHolder;
  let strategist;
  let triToken;

  beforeEach(async function () {
    // reset network
    await network.provider.request({
      method: 'hardhat_reset',
      params: [
        {
          forking: {
            jsonRpcUrl: 'https://mainnet.aurora.dev',
            blockNumber: 70603499, // This is after the want holder bought their LP tokens
          },
        },
      ],
    });

    // get signers
    [owner] = await ethers.getSigners();
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [wantHolderAddr],
    });
    wantHolder = await ethers.provider.getSigner(wantHolderAddr);
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [strategistAddr],
    });
    strategist = await ethers.provider.getSigner(strategistAddr);
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [whaleAddress],
    });
    whale = await ethers.provider.getSigner(whaleAddress);

    // -----------------------------------------------------------------------
    // Ensure sufficient account balances
    await whale.sendTransaction({
      to: wantHolderAddr,
      value: ethers.utils.parseEther('10'),
    });

    // get artifacts
    Vault = await ethers.getContractFactory('ReaperVaultv1_4');
    Strategy = await ethers.getContractFactory('ReaperStrategyTrisolaris');
    Want = await ethers.getContractFactory('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20');

    // deploy contracts
    vault = await Vault.deploy(wantAddress, tokenName, tokenSymbol, 0, ethers.constants.MaxUint256);

    strategy = await hre.upgrades.deployProxy(
      Strategy,
      [vault.address, [treasuryAddr, paymentSplitterAddress], [strategistAddr], wantAddress, poolId],
      {kind: 'uups'},
    );
    await strategy.deployed();
    await vault.initialize(strategy.address);
    want = await Want.attach(wantAddress);

    // approving LP token and vault share spend
    await want.connect(wantHolder).approve(vault.address, ethers.constants.MaxUint256);

    // connect to the TRI token
    const ERC20 = await ethers.getContractFactory('@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20');
    triToken = await ERC20.attach(triTokenAddress);
  });

  describe('Deploying the vault and strategy', function () {
    it('should initiate vault with a 0 balance', async function () {
      const totalBalance = await vault.balance();
      const availableBalance = await vault.available();
      const pricePerFullShare = await vault.getPricePerFullShare();
      expect(totalBalance).to.equal(0);
      expect(availableBalance).to.equal(0);
      expect(pricePerFullShare).to.equal(ethers.utils.parseEther('1'));
    });
  });

  describe('Vault Tests', function () {
    it('should allow deposits and account for them correctly', async function () {
      const depositAmount = toWantUnit('10');
      const depositTx = await vault.connect(wantHolder).deposit(depositAmount);
      await depositTx.wait(1);

      const newVaultBalance = await vault.balance();
      const allowedInaccuracy = depositAmount.div(200);

      expect(depositAmount).to.be.closeTo(newVaultBalance, allowedInaccuracy);
    });

    it('should mint user their pool share', async function () {
      // const userBalance = await want.balanceOf(wantHolderAddr);
      const depositAmount = toWantUnit('0.0000029');
      await vault.connect(wantHolder).deposit(depositAmount);

      const ownerDepositAmount = toWantUnit('0.00000001');
      await want.connect(wantHolder).transfer(owner.address, ownerDepositAmount);
      await want.connect(owner).approve(vault.address, ethers.constants.MaxUint256);
      await vault.connect(owner).deposit(ownerDepositAmount);

      const allowedImprecision = toWantUnit('0.00000000001');

      const userVaultBalance = await vault.balanceOf(wantHolderAddr);
      expect(userVaultBalance).to.be.closeTo(depositAmount, allowedImprecision);
      const ownerVaultBalance = await vault.balanceOf(owner.address);
      expect(ownerVaultBalance).to.be.closeTo(ownerDepositAmount, allowedImprecision);

      await vault.connect(owner).withdrawAll();
      const ownerWantBalance = await want.balanceOf(owner.address);
      expect(ownerWantBalance).to.be.closeTo(ownerDepositAmount, allowedImprecision);
      const afterOwnerVaultBalance = await vault.balanceOf(owner.address);
      expect(afterOwnerVaultBalance).to.equal(0);
    });

    it('should allow withdrawals', async function () {
      const userBalance = await want.balanceOf(wantHolderAddr);
      const depositAmount = toWantUnit('0.0000029');
      await vault.connect(wantHolder).deposit(depositAmount);

      await vault.connect(wantHolder).withdrawAll();
      const userBalanceAfterWithdraw = await want.balanceOf(wantHolderAddr);

      const securityFee = 10;
      const percentDivisor = 10000;
      const withdrawFee = depositAmount.mul(securityFee).div(percentDivisor);
      const expectedBalance = userBalance.sub(withdrawFee);
      const smallDifference = expectedBalance.div(200);
      const isSmallBalanceDifference = expectedBalance.sub(userBalanceAfterWithdraw) < smallDifference;
      expect(isSmallBalanceDifference).to.equal(true);
    });

    it('should allow small withdrawal', async function () {
      const userBalance = await want.balanceOf(wantHolderAddr);
      const depositAmount = toWantUnit('0.00000001');
      await vault.connect(wantHolder).deposit(depositAmount);

      await vault.connect(wantHolder).withdrawAll();
      const userBalanceAfterWithdraw = await want.balanceOf(wantHolderAddr);

      const securityFee = 10;
      const percentDivisor = 10000;
      const withdrawFee = depositAmount.mul(securityFee).div(percentDivisor);
      const expectedBalance = userBalance.sub(withdrawFee);
      const smallDifference = depositAmount.div(10);
      const isSmallBalanceDifference = expectedBalance.sub(userBalanceAfterWithdraw) < smallDifference;
      expect(isSmallBalanceDifference).to.equal(true);
    });

    it('should handle small deposit + withdraw', async function () {
      const userBalance = await want.balanceOf(wantHolderAddr);
      const depositAmount = toWantUnit('0.0000000000001');
      await vault.connect(wantHolder).deposit(depositAmount);

      await vault.connect(wantHolder).withdraw(depositAmount);
      const userBalanceAfterWithdraw = await want.balanceOf(wantHolderAddr);

      const securityFee = 10;
      const percentDivisor = 10000;
      const withdrawFee = (depositAmount * securityFee) / percentDivisor;
      const expectedBalance = userBalance.sub(withdrawFee);
      const isSmallBalanceDifference = expectedBalance.sub(userBalanceAfterWithdraw) < 200;
      expect(isSmallBalanceDifference).to.equal(true);
    });

    it('should be able to harvest', async function () {
      const timeToSkip = 3600;
      const blocksToSkip = 100;

      await vault.connect(wantHolder).deposit(toWantUnit('1000'));

      await moveTimeForward(timeToSkip);
      await moveBlocksForward(blocksToSkip);
      await strategy.harvest();
    });

    it('should provide yield', async function () {
      const timeToSkip = 3600;
      const blocksToSkip = 100;
      const balances = {
        user: {
          initial: 0,
        },
        vault: {
          initial: 0,
          postDeposit: 0,
          postDepositDiff: 0,
          current: 0,
          currentDiff: 0,
          final: 0,
        },
        strategy: {
          initial: 0,
          postDeposit: 0,
          postDepositDiff: 0,
          current: 0,
          currentDiff: 0,
          final: 0,
        },
      };

      await strategy.updateHarvestLogCadence(timeToSkip / 2);

      balances.user.initial = await want.balanceOf(wantHolderAddr);
      balances.vault.initial = await vault.balance();
      balances.strategy.initial = await strategy.balanceOf();

      await vault.connect(wantHolder).deposit(balances.user.initial);

      balances.vault.postDeposit = await vault.balance();
      balances.vault.postDepositDiff = balances.vault.postDeposit.sub(balances.vault.initial);
      balances.strategy.postDeposit = await strategy.balanceOf();
      balances.strategy.postDepositDiff = balances.strategy.postDeposit.sub(balances.strategy.initial);

      // console.log('balances', balances);

      const numHarvests = 5;
      for (let i = 0; i < numHarvests; i++) {
        await moveTimeForward(timeToSkip);
        await moveBlocksForward(blocksToSkip);

        // check tri token balance at master chef for this block
        // const triBalance = await triToken.balanceOf(masterChefAddress);
        // console.log('triBalance > pre balance', triBalance);

        await strategy.harvest();

        balances.vault.current = await vault.balance();
        balances.vault.currentDiff = balances.vault.current.sub(balances.vault.postDeposit);
        balances.strategy.current = await strategy.balanceOf();
        balances.strategy.currentDiff = balances.strategy.current.sub(balances.strategy.postDeposit);
        // console.log(i, 'balances', balances);
      }

      balances.strategy.final = await strategy.balanceOf();
      balances.vault.final = await vault.balance();

      // We expect the yield to have increased the balance in the vault
      expect(balances.vault.final).to.be.gt(balances.vault.postDeposit);
      expect(balances.strategy.final).to.be.gt(balances.strategy.postDeposit);

      const averageAPR = await strategy.averageAPRAcrossLastNHarvests(numHarvests);
      console.log(`Average APR across ${numHarvests} harvests is ${averageAPR} basis points.`);
    });
  });

  describe('Strategy', function () {
    it('should be able to pause and unpause', async function () {
      await strategy.pause();
      const depositAmount = toWantUnit('0.0000029');
      await expect(vault.connect(wantHolder).deposit(depositAmount)).to.be.reverted;

      await strategy.unpause();
      await expect(vault.connect(wantHolder).deposit(depositAmount)).to.not.be.reverted;
    });

    /**
     * This is an old test that was `xit` out and doesn't make any sense any more.
     */
    it.skip('should be able to panic', async function () {
      const depositAmount = toWantUnit('0.0000029');
      await vault.connect(wantHolder).deposit(depositAmount);
      // const vaultBalance = await vault.balance();
      const strategyBalance = await strategy.balanceOf();
      await strategy.panic();

      const wantStrategyBalance = await want.balanceOf(strategy.address);
      const allowedImprecision = toWantUnit('0.00000000001');

      console.log('strategyBalance', strategyBalance);
      console.log('wantStrategyBalance', wantStrategyBalance);

      expect(strategyBalance).to.be.closeTo(wantStrategyBalance, allowedImprecision);
    });

    it('should be able to retire strategy', async function () {
      const depositAmount = toWantUnit('1000');
      await vault.connect(wantHolder).deposit(depositAmount);
      const vaultBalance = await vault.balance();
      const strategyBalance = await strategy.balanceOf();
      expect(vaultBalance).to.equal(strategyBalance);

      await expect(strategy.retireStrat()).to.not.be.reverted;
      const newVaultBalance = await vault.balance();
      const newStrategyBalance = await strategy.balanceOf();
      const allowedImprecision = toWantUnit('0.1');
      expect(newVaultBalance).to.be.closeTo(vaultBalance, allowedImprecision);
      expect(newStrategyBalance).to.be.lt(allowedImprecision);
    });

    it('should be able to retire strategy with no balance', async function () {
      await expect(strategy.retireStrat()).to.not.be.reverted;
    });

    it('should be able to estimate harvest', async function () {
      const whaleDepositAmount = toWantUnit('1000');
      await vault.connect(wantHolder).deposit(whaleDepositAmount);
      await moveBlocksForward(100);
      await strategy.harvest();
      await moveBlocksForward(500); // needs to process enough blocks for callFeeToUser to be > 0
      const [profit, callFeeToUser] = await strategy.estimateHarvest();
      console.log(`profit: ${profit}`);
      const hasProfit = profit.gt(0);
      const hasCallFee = callFeeToUser.gt(0);
      expect(hasProfit).to.equal(true, 'profit should be greater than 0');
      expect(hasCallFee).to.equal(true, 'callFeeToUser should be greater than 0');
    });
  });
});
