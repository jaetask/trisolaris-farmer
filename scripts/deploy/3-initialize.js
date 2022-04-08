async function main() {
  const vaultAddress = '0xb1f916892c649EB163328F952642199F106C08b4';
  const strategyAddress = '0x99DA24ce0Ae29A0D8448f0a9821334c68c23aAC8';

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
