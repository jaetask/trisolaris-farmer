// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMasterChef {
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. TRI to distribute per block.
        uint256 lastRewardBlock; // Last block number that TRI distribution occurs.
        uint256 accSushiPerShare; // Accumulated TRI per share, times 1e12. See below.
    }

    function poolInfo(uint256 pid) external view returns (IMasterChef.PoolInfo memory);

    function userInfo(uint256 pid, address _user) external view returns (uint256 amount, uint256 rewardDebt);

    function poolLength() external view returns (uint256);

    function updatePool(uint256 _pid) external;

    function totalAllocPoint() external view returns (uint256);

    function deposit(uint256 _pid, uint256 _amount) external;

    function tri() external view returns (address);

    function triPerBlock() external view returns (uint256);

    function pendingTri(uint256 _pid, address _user) external view returns (uint256);

    function emergencyWithdraw(uint256 _pid, address to) external;

    function withdraw(
        uint256 _pid,
        uint256 _amount,
        address _to
    ) external;
}
