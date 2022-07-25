import {findPoolByName} from '../../pools';

async function main() {
  const Vault = await ethers.getContractFactory('ReaperVaultv1_4');

  const depositFee = 0;
  const tvlCap = ethers.constants.MaxUint256;
  const pool = findPoolByName('wNEAR-ETH');
  const {wantAddress, tokenName, tokenSymbol} = pool;
  console.log('');
  console.log('Deploying:');
  console.log('tokenName', tokenName, `(${tokenSymbol})`);
  console.log('wantAddress', wantAddress);

  const vault = await Vault.deploy(wantAddress, tokenName, tokenSymbol, depositFee, tvlCap);

  await vault.deployed();
  console.log('Vault deployed to:', vault.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
