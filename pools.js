const masterChefPools = [
  {
    name: 'TRI-USDT',
    tokenName: 'TRI-USDT Trisolaris Crypt',
    tokenSymbol: 'rf-TRI-USDT',
    masterChef: 'V2',
    poolId: 4,
    wantAddress: '0x61C9E05d1Cdb1b70856c7a2c53fA9c220830633c',
    wantHolderAddr: '0xcfe0c0fddbc896d08a9a14592b6a470e0536b25f',
    rewards: ['TRI'],
    checkPoolExists: false,
    done: true,
  },
  {
    name: 'TRI-wNEAR',
    tokenName: 'TRI-wNEAR Trisolaris Crypt',
    tokenSymbol: 'rf-TRI-wNEAR',
    masterChef: 'V2',
    poolId: 5,
    wantAddress: '0x84b123875F0F36B966d0B6Ca14b31121bd9676AD',
    wantHolderAddr: '0x2adb8dca2291a8dd95e2a7b8458d1121eb3e7ce4',
    rewards: ['TRI'],
    checkPoolExists: false,
    done: false,
  },
  {
    name: 'wNEAR-ETH',
    tokenName: 'wNEAR-ETH Trisolaris Crypt',
    tokenSymbol: 'rf-wNEAR-ETH',
    masterChef: 'V1',
    poolId: 0,
    wantAddress: '0x63da4DB6Ef4e7C62168aB03982399F9588fCd198',
    wantHolderAddr: '0x4dd06d3f05d573db027459e8dc942e37249d71a8',
    rewards: ['TRI'],
    checkPoolExists: false,
    done: false,
  },
];
exports.masterChefPools = masterChefPools;

/**
 * Find a pool in the testPools array by name
 * @param {*} name name of the pool to find
 * @returns {*} the pool object or throws an error if not found
 */
const findPoolByName = (name) => {
  const found = masterChefPools.find((pool) => pool.name === name);
  if (!found) {
    throw new Error(`Pool ${name} not found`);
  }
  return found;
};
exports.findPoolByName = findPoolByName;
