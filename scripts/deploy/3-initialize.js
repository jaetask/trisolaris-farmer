async function main() {
  const vaultAddress = '0xee719cF91E88e6eD9F20Da8f3B07288FC70e3e70';
  const strategyAddress = '0x8F9969dE731CBACEF79e03350a1b9052D1B3DC0B';

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
