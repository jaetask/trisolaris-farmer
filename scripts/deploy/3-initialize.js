async function main() {
  const vaultAddress = '0x22dBDDd7b156F17e2da237e7901f322083d330dB';
  const strategyAddress = '0x6f0d1eCfD46A35baA897e044B83c58903B3e88A0';

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
