const hre = require('hardhat');

async function main() {
  const vaultAddress = ''; // todo:  get this from the deployed contract config!

  const Strategy = await ethers.getContractFactory('ReaperStrategyTrisolaris');
  const treasuryAddress = '0x0e7c5313E9BB80b654734d9b7aB1FB01468deE3b';
  const paymentSplitterAddress = '0x65e45d2f3f43b613416614c73f18fdd3aa2b8391'; // todo: check this, what is the real one?
  const strategist1 = '0x53776b2Bc73356b0b9aF4dd4D7E7BeFDa0DfEC05';
  // const strategist2 = '0x81876677843D00a7D792E1617459aC2E93202576';
  // const strategist3 = '0x1A20D7A31e5B3Bc5f02c8A146EF6f394502a10c4';
  const wantAddress = '0x61C9E05d1Cdb1b70856c7a2c53fA9c220830633c'; // todo: change to single source of truth

  const poolId = 4;

  if (!vaultAddress) {
    throw new Error('Please specify the vault address');
  }

  const strategy = await hre.upgrades.deployProxy(
    Strategy,
    [vaultAddress, [treasuryAddress, paymentSplitterAddress], [strategist1], wantAddress, poolId],
    {kind: 'uups', timeout: 0},
  );

  await strategy.deployed();
  console.log('Strategy deployed to:', strategy.address);
  // todo: write the address to the config
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
