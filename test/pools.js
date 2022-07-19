/**
 * Array of pools to use during testing
 */
const testPools = [
  {
    name: 'USDC-wNEAR',
    masterChef: '',
    poolId: 0,
    wantAddress: '',
    wantHolderAddr: '',
    rewards: ['TRI', 'AURORA'],
    checkPoolExists: true, // loops over the MasterChef contract and locates the poolId
  },
  {
    name: 'USDT-wNEAR',
    masterChef: '',
    poolId: 0,
    wantAddress: '',
    wantHolderAddr: '',
    rewards: ['TRI', 'AURORA'],
    checkPoolExists: true,
  },
  {
    name: 'AURORA-wNEAR',
    masterChef: '',
    poolId: 0,
    wantAddress: '',
    wantHolderAddr: '',
    rewards: ['TRI', 'AURORA'],
    checkPoolExists: true,
  },
];
exports.testPools = testPools;

/**
 * Find a pool in the testPools array by name
 * @param {*} name name of the pool to find
 * @returns {*} the pool object or throws an error if not found
 */
const findPoolByName = (name) => {
  const found = testPools.find((pool) => pool.name === name);
  if (!found) {
    throw new Error(`Pool ${name} not found`);
  }
  return found;
};

exports.findPoolByName = findPoolByName;
