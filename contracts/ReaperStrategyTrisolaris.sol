// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./abstract/ReaperBaseStrategyv1_1.sol";
import "./interfaces/IMasterChefV1.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniV2Pair.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

/**
 * @dev Deposit SpookySwap LP tokens into MasterChef. Harvest TRI rewards and recompound.
 * @dev Please pay particular attention to the MasterChef withdraw/deposit transactions,
 *      they have a third parameter `to` which isn't present on the Spooky MasterChef.
 */
contract ReaperStrategyTrisolaris is ReaperBaseStrategyv1_1 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // 3rd-party contract addresses
    address public constant TRISOLARIS_ROUTER = address(0x2CB45Edb4517d5947aFdE3BEAbF95A582506858B);
    address public constant MASTER_CHEF = address(0x1f1Ed214bef5E83D8f5d0eB5D7011EB965D0D79B);

    /**
     * @dev Tokens Used:
     * {USDC} - Required for liquidity routing when doing swaps.
     * {wNEAR} - Required for liquidity routing when doing swaps.
     * {wETH} - Required for liquidity routing when doing swaps.
     * {TRI} - Reward token for depositing LP into MasterChef.
     * {want} - Address of the LP token to farm. (lowercase name for FE compatibility)
     * {lpToken0} - First token of the want LP
     * {lpToken1} - Second token of the want LP
     */
    address public constant USDC = address(0xB12BFcA5A55806AaF64E99521918A4bf0fC40802);
    address public constant wNEAR = address(0xC42C30aC6Cc15faC9bD938618BcaA1a1FaE8501d);
    address public constant wETH = address(0xC9BdeEd33CD01541e1eeD10f90519d2C06Fe3feB);
    address public constant TRI = address(0xFa94348467f64D5A457F75F8bc40495D33c65aBB);
    address public want;
    address public lpToken0;
    address public lpToken1;

    /**
     * @dev Paths used to swap tokens:
     * {triToUsdcPath} - to swap {TRI} to {USDC} (using TRISOLARIS_ROUTER)
     * {triToWnearPath} - to swap {TRI} to {USDT} (using TRISOLARIS_ROUTER)
     */
    address[] public triToUsdcPath;
    address[] public triToWnearPath;
    address[] public triToWethPath;

    /**
     * @dev Trisolaris variables.
     * {poolId} - ID of pool in which to deposit LP tokens
     */
    uint256 public poolId;

    /**
     * @dev Initializes the strategy. Sets parameters and saves routes.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _vault,
        address[] memory _feeRemitters,
        address[] memory _strategists,
        address _want,
        uint256 _poolId
    ) public initializer {
        __ReaperBaseStrategy_init(_vault, _feeRemitters, _strategists);
        want = _want;
        poolId = _poolId;
        triToUsdcPath = [TRI, USDC];
        triToWnearPath = [TRI, wNEAR];
        triToWethPath = [TRI, wETH];
        lpToken0 = IUniV2Pair(want).token0();
        lpToken1 = IUniV2Pair(want).token1();
    }

    /**
     * @dev Function that puts the funds to work.
     *      It gets called whenever someone deposits in the strategy's vault contract.
     */
    function _deposit() internal override {
        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBalance != 0) {
            IERC20Upgradeable(want).safeIncreaseAllowance(MASTER_CHEF, wantBalance);
            IMasterChefV1(MASTER_CHEF).deposit(poolId, wantBalance);
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal override {
        uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMasterChefV1(MASTER_CHEF).withdraw(poolId, _amount - wantBal);
        }
        IERC20Upgradeable(want).safeTransfer(vault, _amount);
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     *      1. Claims {TRI} from the {MASTER_CHEF}.
     *      3. Charge fees.
     *      2. Swaps half remaining {TRI} to {wNEAR}.
     *      2. Swaps remaining {TRI} to {wETH}.
     *      4. Creates new LP tokens.
     *      5. Deposits LP in the Master Chef.
     */
    function _harvestCore() internal override {
        // claim TRI from masterchef
        _claimRewards();
        // charge fees on rewards, and convert them to USDC to distribture
        _chargeFees();
        // Swaps half remaining {TRI} to {wNEAR}
        _swapToWnear();
        // Swaps remaining {TRI} to {wETH}.
        _swapToWeth();
        // create LP tokens
        _addLiquidity();
        // deposit LP back into strategy as compounded
        deposit();
    }

    function _swapToWnear() internal {
        IERC20Upgradeable tri = IERC20Upgradeable(TRI);
        uint256 triBalance = tri.balanceOf(address(this));
        _swap(triBalance / 2, triToWnearPath);
    }

    function _swapToWeth() internal {
        IERC20Upgradeable tri = IERC20Upgradeable(TRI);
        uint256 triBalance = tri.balanceOf(address(this));
        _swap(triBalance, triToWethPath);
    }

    function _claimRewards() internal {
        uint256 pendingTri = IMasterChefV1(MASTER_CHEF).pendingTri(poolId, address(this));
        if (pendingTri > 0) {
            IMasterChefV1(MASTER_CHEF).harvest(poolId);
        }
    }

    /**
     * @dev Helper function to swap tokens given an {_amount} and swap {_path}.
     */
    function _swap(uint256 _amount, address[] memory _path) internal {
        if (_path.length < 2 || _amount == 0) {
            return;
        }

        IERC20Upgradeable(_path[0]).safeIncreaseAllowance(TRISOLARIS_ROUTER, _amount);
        IUniswapV2Router02(TRISOLARIS_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            0,
            _path,
            address(this),
            block.timestamp
        );
    }

    /**
     * @dev Core harvest function.
     *      Charges fees based on the amount of TRI gained from reward
     */
    function _chargeFees() internal {
        IERC20Upgradeable tri = IERC20Upgradeable(TRI);
        IERC20Upgradeable usdc = IERC20Upgradeable(USDC);

        uint256 triBalance = tri.balanceOf(address(this));
        uint256 triFee = (triBalance * totalFee) / PERCENT_DIVISOR;

        if (triFee != 0) {
            // swap tri fees to usdc
            uint256 usdcBalanceBefore = usdc.balanceOf(address(this));
            _swap(triFee, triToUsdcPath);
            uint256 usdcBalanceAfter = usdc.balanceOf(address(this));
            uint256 usdcFee = usdcBalanceAfter - usdcBalanceBefore;

            // distribtute usdc to fee remitters
            uint256 callFeeToUser = (usdcFee * callFee) / PERCENT_DIVISOR;
            uint256 treasuryFeeToVault = (usdcFee * treasuryFee) / PERCENT_DIVISOR;
            uint256 feeToStrategist = (treasuryFeeToVault * strategistFee) / PERCENT_DIVISOR;
            treasuryFeeToVault -= feeToStrategist;

            usdc.safeTransfer(msg.sender, callFeeToUser);
            usdc.safeTransfer(treasury, treasuryFeeToVault);
            usdc.safeTransfer(strategistRemitter, feeToStrategist);
        }
    }

    /**
     * @dev Core harvest function. Adds more liquidity using {lpToken0} and {lpToken1}.
     */
    function _addLiquidity() internal {
        uint256 lp0Bal = IERC20Upgradeable(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20Upgradeable(lpToken1).balanceOf(address(this));

        lp0Bal = IERC20Upgradeable(lpToken0).balanceOf(address(this));
        lp1Bal = IERC20Upgradeable(lpToken1).balanceOf(address(this));

        if (lp0Bal != 0 && lp1Bal != 0) {
            IERC20Upgradeable(lpToken0).safeIncreaseAllowance(TRISOLARIS_ROUTER, lp0Bal);
            IERC20Upgradeable(lpToken1).safeIncreaseAllowance(TRISOLARIS_ROUTER, lp1Bal);
            IUniswapV2Router02(TRISOLARIS_ROUTER).addLiquidity(
                lpToken0,
                lpToken1,
                lp0Bal,
                lp1Bal,
                0,
                0,
                address(this),
                block.timestamp
            );
        }
    }

    /**
     * @dev Function to calculate the total {want} held by the strat.
     *      It takes into account both the funds in hand, plus the funds in the MasterChef.
     */
    function balanceOf() public view override returns (uint256) {
        (uint256 amount, ) = IMasterChefV1(MASTER_CHEF).userInfo(poolId, address(this));
        return amount + IERC20Upgradeable(want).balanceOf(address(this));
    }

    /**
     * @dev Returns the approx amount of profit from harvesting.
     *      Profit is denominated in USDT, and takes fees into account.
     */
    function estimateHarvest() external view override returns (uint256 profit, uint256 callFeeToUser) {
        uint256 pendingReward = IMasterChefV1(MASTER_CHEF).pendingTri(poolId, address(this));
        uint256 totalRewards = pendingReward + IERC20Upgradeable(TRI).balanceOf(address(this));

        if (totalRewards != 0) {
            profit += IUniswapV2Router02(TRISOLARIS_ROUTER).getAmountsOut(totalRewards, triToWnearPath)[1];
        }

        profit += IERC20Upgradeable(USDC).balanceOf(address(this));

        uint256 usdcFee = (profit * totalFee) / PERCENT_DIVISOR;
        callFeeToUser = (usdcFee * callFee) / PERCENT_DIVISOR;
        profit -= usdcFee;
    }

    /**
     * @dev Function to retire the strategy. Claims all rewards and withdraws
     *      all principal from external contracts, and sends everything back to
     *      the vault. Can only be called by strategist or owner.
     *
     * Note: this is not an emergency withdraw function. For that, see panic().
     */
    function _retireStrat() internal override {
        IMasterChefV1(MASTER_CHEF).deposit(poolId, 0); // deposit 0 to claim rewards

        _swapToWnear();

        _swapToWeth();

        _addLiquidity();

        (uint256 poolBal, ) = IMasterChefV1(MASTER_CHEF).userInfo(poolId, address(this));
        IMasterChefV1(MASTER_CHEF).withdraw(poolId, poolBal);

        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        IERC20Upgradeable(want).safeTransfer(vault, wantBalance);
    }

    /**
     * Withdraws all funds leaving rewards behind.
     */
    function _reclaimWant() internal override {
        IMasterChefV1(MASTER_CHEF).emergencyWithdraw(poolId, vault);
    }
}
