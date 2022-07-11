async function main() {
  const vaultAddress = ''; // todo: should come from dynamic config file
  const strategyAddress = '';

  if (!vaultAddress) {
    throw new Error('Please specify the vault address');
  }
  if (!strategyAddress) {
    throw new Error('Please specify the strategy address');
  }

  const Vault = await ethers.getContractFactory('ReaperVaultv1_4');
  const vault = Vault.attach(vaultAddress);

  // todo: should we wait for the transaction to ccomplete here? with await tx.wait(1)?
  await vault.initialize(strategyAddress);

  console.log('Vault initialized');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
