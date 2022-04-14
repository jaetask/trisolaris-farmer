// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IMasterChefV2 {
    struct PoolInfo {
        uint128 accBooPerShare;
        uint64 lastRewardTime;
        uint64 allocPoint;
    }

    function BOO() external view returns (address);

    function MASTER_CHEF() external view returns (address);

    function MASTER_PID() external view returns (uint256);

    function V1_HARVEST_QUERY_TIME() external view returns (uint256);

    function add(
        uint64 allocPoint,
        address _lpToken,
        address _rewarder,
        bool update
    ) external;

    function booPerSecond() external view returns (uint256 amount);

    function deposit(
        uint256 pid,
        uint256 amount,
        address to
    ) external;

    function deposit(uint256 pid, uint256 amount) external;

    function emergencyWithdraw(uint256 pid, address to) external;

    function getFarmData(uint256 pid)
        external
        view
        returns (
            PoolInfo memory,
            uint256,
            address
        );

    function harvestAll() external;

    function harvestFromMasterChef() external;

    function harvestMultiple(uint256[] memory pids) external;

    function init(address dummyToken) external;

    function isLpToken(address) external view returns (bool);

    function lastV1HarvestTimestamp() external view returns (uint256);

    function lpToken(uint256) external view returns (address);

    function massUpdateAllPools() external;

    function massUpdatePools(uint256[] calldata pids) external;

    function owner() external view returns (address);

    function pendingBOO(uint256 _pid, address _user) external view returns (uint256 pending);

    function poolInfo(uint256)
        external
        view
        returns (
            uint128 accBooPerShare,
            uint64 lastRewardTime,
            uint64 allocPoint
        );

    function poolInfoAmount() external view returns (uint256);

    function poolLength() external view returns (uint256 pools);

    function queryHarvestFromMasterChef() external;

    function renounceOwnership() external;

    function rewarder(uint256) external view returns (address);

    function set(
        uint256 _pid,
        uint64 _allocPoint,
        address _rewarder,
        bool overwrite,
        bool update
    ) external;

    function setBatch(
        uint256[] memory _pid,
        uint64[] memory _allocPoint,
        address[] memory _rewarders,
        bool[] memory overwrite,
        bool update
    ) external;

    function setV1HarvestQueryTime(uint256 newTime, bool inDays) external;

    function totalAllocPoint() external view returns (uint256);

    function transferOwnership(address newOwner) external;

    function updatePool(uint256 pid) external returns (PoolInfo memory pool);

    function userInfo(uint256, address) external view returns (uint256 amount, uint256 rewardDebt);

    function withdraw(
        uint256 pid,
        uint256 amount,
        address to
    ) external;

    function withdraw(uint256 pid, uint256 amount) external;
}
