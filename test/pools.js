/**
 * Array of pools to use during testing
 */
const testPools = [
  {
    name: 'SHITZU-USDC',
    masterChef: 'V2',
    poolId: 19,
    wantAddress: '0x5E74D85311fe2409c341Ce49Ce432BB950D221DE',
    wantHolderAddr: '0xe7b8b36f118f83e0dd3e19e1fa21852adb8f96d0',
    rewards: ['TRI'],
    checkPoolExists: false, // loops over the MasterChef contract and locates the poolId
  },
  {
    name: 'TRI-USDT',
    masterChef: 'V2',
    poolId: 4,
    wantAddress: '0x61C9E05d1Cdb1b70856c7a2c53fA9c220830633c',
    wantHolderAddr: '0xcfe0c0fddbc896d08a9a14592b6a470e0536b25f',
    rewards: ['TRI'],
    checkPoolExists: false,
  },
  // all the other TRI rewarding pools are on the original MasterChef
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
