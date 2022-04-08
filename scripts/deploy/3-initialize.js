async function main() {
  const vaultAddress = '0x5e7D062B26C588A72D1cF99fb191Df07a4475e11';
  const strategyAddress = '0xA98d9a68E0B8938d9DBE289A0FeDb4feCFFbA59B';

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
