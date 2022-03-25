async function main() {
  const vaultAddress = '0xe56F2cCb0C8C31592E711Dbc4649d0B6b1C091D8';
  const strategyAddress = '0x41B7A81f767fB0e4Db93686056E31D9445Ebea4C';

  const Vault = await ethers.getContractFactory('ReaperVaultv1_4');
  const vault = Vault.attach(vaultAddress);

  await vault.initialize(strategyAddress);
  console.log('Vault initialized');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
