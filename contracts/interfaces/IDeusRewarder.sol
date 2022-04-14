// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IDeusRewarder {
    struct PoolInfo {
        uint128 accRewardPerShare;
        uint64 lastRewardTime;
        uint64 allocPoint;
    }

    function ACC_TOKEN_PRECISION() external view returns (uint256);

    function add(
        uint64 allocPoint,
        uint256 _pid,
        bool _update
    ) external;

    function massUpdatePools() external;

    function onReward(
        uint256 _pid,
        address _user,
        address _to,
        uint256,
        uint256 _amt
    ) external;

    function owner() external view returns (address);

    function pendingToken(uint256 _pid, address _user) external view returns (uint256 pending);

    function pendingTokens(
        uint256 pid,
        address user,
        uint256
    ) external view returns (address[] memory rewardTokens, uint256[] memory rewardAmounts);

    function poolIds(uint256) external view returns (uint256);

    function poolInfo(uint256)
        external
        view
        returns (
            uint128 accRewardPerShare,
            uint64 lastRewardTime,
            uint64 allocPoint
        );

    function poolLength() external view returns (uint256 pools);

    function recoverTokens(
        address _tokenAddress,
        uint256 _amt,
        address _adr
    ) external;

    function renounceOwnership() external;

    function rewardPerSecond() external view returns (uint256);

    function rewardToken() external view returns (address);

    function set(
        uint256 _pid,
        uint64 _allocPoint,
        bool _update
    ) external;

    function setRewardPerSecond(uint256 _rewardPerSecond) external;

    function transferOwnership(address newOwner) external;

    function updatePool(uint256 pid) external returns (PoolInfo memory pool);

    function userInfo(uint256, address) external view returns (uint256 amount, uint256 rewardDebt);
}
