// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./abstract/ReaperBaseStrategyv1_1.sol";
import "./interfaces/IDeusRewarder.sol";
import "./interfaces/IMasterChefV2.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniV2Pair.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/**
 * @dev Deposit SpookySwap LP tokens into MasterChef. Harvest BOO and DEUS rewards and recompound.
 */
contract ReaperStrategySpookyDeus is ReaperBaseStrategyv1_1 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // 3rd-party contract addresses
    address public constant TRISOLARIS_ROUTER = address(0x2CB45Edb4517d5947aFdE3BEAbF95A582506858B);
    address public constant MASTER_CHEF = address(0x18b4f774fdC7BF685daeeF66c2990b1dDd9ea6aD);

    /**
     * @dev Tokens Used:
     * {WFTM} - Required for liquidity routing when doing swaps.
     * {BOO} - Reward token for depositing LP into MasterChef.
     * {DEUS} - Secondary Reward token for depositing LP into MasterChef.
     * {USDC} - One of the LP tokens
     * {DEI} - Other LP token
     * {want} - Address of the LP token to farm. (lowercase name for FE compatibility)
     * {lpToken0} - First token of the want LP
     * {lpToken1} - Second token of the want LP
     */
    address public constant WFTM = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    address public constant BOO = address(0x841FAD6EAe12c286d1Fd18d1d525DFfA75C7EFFE);
    address public constant DEUS = address(0xDE5ed76E7c05eC5e4572CfC88d1ACEA165109E44);
    address public constant USDC = address(0x04068DA6C83AFCFA0e13ba15A6696662335D5B75);
    address public constant DEI = address(0xDE12c7959E1a72bbe8a5f7A1dc8f8EeF9Ab011B3);
    address public want;
    address public lpToken0;
    address public lpToken1;

    /**
     * @dev Paths used to swap tokens:
     * {booToWftmPath} - to swap {BOO} to {WFTM} (using TRISOLARIS_ROUTER)
     * {deusToWftmPath} - to swap {DEUS} to {WFTM} (using TRISOLARIS_ROUTER)
     * {wftmToUsdcPath} - to swap {WFTM} to {USDC} (using TRISOLARIS_ROUTER)
     * {usdcToDeiPath} - to swap {USDC} to {DEI} (using TRISOLARIS_ROUTER)
     */
    address[] public booToWftmPath;
    address[] public deusToWftmPath;
    address[] public wftmToUsdcPath;
    address[] public usdcToDeiPath;

    /**
     * @dev Spooky variables.
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
        booToWftmPath = [BOO, WFTM];
        deusToWftmPath = [DEUS, WFTM];
        wftmToUsdcPath = [WFTM, USDC];
        usdcToDeiPath = [USDC, DEI];
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
            IMasterChefV2(MASTER_CHEF).deposit(poolId, wantBalance);
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal override {
        uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBal < _amount) {
            IMasterChefV2(MASTER_CHEF).withdraw(poolId, _amount - wantBal);
        }

        IERC20Upgradeable(want).safeTransfer(vault, _amount);
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     *      1. Claims {BOO} and {DEUS} from the {MASTER_CHEF}.
     *      2. Swaps {BOO} and {DEUS} to {WFTM} and charges fees.
     *      3. Creates new LP tokens using remaining {WFTM}.
     *      4. Deposits LP in the Master Chef.
     */
    function _harvestCore() internal override {
        IMasterChefV2(MASTER_CHEF).deposit(poolId, 0); // deposit 0 to claim rewards
        _performSwapsAndChargeFees();
        _addLiquidity();
        deposit();
    }

    /**
     * @dev Core harvest function.
     *      Charges fees based on the amount of WFTM gained from reward
     */
    function _performSwapsAndChargeFees() internal {
        _swap(IERC20Upgradeable(BOO).balanceOf(address(this)), booToWftmPath);
        _swap(IERC20Upgradeable(DEUS).balanceOf(address(this)), deusToWftmPath);

        IERC20Upgradeable wftm = IERC20Upgradeable(WFTM);
        uint256 wftmFee = (wftm.balanceOf(address(this)) * totalFee) / PERCENT_DIVISOR;
        if (wftmFee != 0) {
            uint256 callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
            uint256 treasuryFeeToVault = (wftmFee * treasuryFee) / PERCENT_DIVISOR;
            uint256 feeToStrategist = (treasuryFeeToVault * strategistFee) / PERCENT_DIVISOR;
            treasuryFeeToVault -= feeToStrategist;

            wftm.safeTransfer(msg.sender, callFeeToUser);
            wftm.safeTransfer(treasury, treasuryFeeToVault);
            wftm.safeTransfer(strategistRemitter, feeToStrategist);
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
     * @dev Core harvest function. Adds more liquidity using {lpToken0} and {lpToken1}.
     */
    function _addLiquidity() internal {
        uint256 wftmBal = IERC20Upgradeable(WFTM).balanceOf(address(this));
        if (wftmBal == 0) {
            return;
        }

        _swap(wftmBal, wftmToUsdcPath);
        _swap(IERC20Upgradeable(USDC).balanceOf(address(this)) / 2, usdcToDeiPath);

        uint256 usdcBal = IERC20Upgradeable(USDC).balanceOf(address(this));
        uint256 deiBal = IERC20Upgradeable(DEI).balanceOf(address(this));

        IERC20Upgradeable(USDC).safeIncreaseAllowance(TRISOLARIS_ROUTER, usdcBal);
        IERC20Upgradeable(DEI).safeIncreaseAllowance(TRISOLARIS_ROUTER, deiBal);
        IUniswapV2Router02(TRISOLARIS_ROUTER).addLiquidity(
            USDC,
            DEI,
            usdcBal,
            deiBal,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    /**
     * @dev Function to calculate the total {want} held by the strat.
     *      It takes into account both the funds in hand, plus the funds in the MasterChef.
     */
    function balanceOf() public view override returns (uint256) {
        (uint256 amount, ) = IMasterChefV2(MASTER_CHEF).userInfo(poolId, address(this));
        return amount + IERC20Upgradeable(want).balanceOf(address(this));
    }

    /**
     * @dev Returns the approx amount of profit from harvesting.
     *      Profit is denominated in WFTM, and takes fees into account.
     */
    function estimateHarvest() external view override returns (uint256 profit, uint256 callFeeToUser) {
        IMasterChefV2 masterChef = IMasterChefV2(MASTER_CHEF);
        IDeusRewarder rewarder = IDeusRewarder(masterChef.rewarder(poolId));

        // {BOO} reward
        uint256 pendingReward = masterChef.pendingBOO(poolId, address(this));
        uint256 totalRewards = pendingReward + IERC20Upgradeable(BOO).balanceOf(address(this));
        if (totalRewards != 0) {
            profit += IUniswapV2Router02(TRISOLARIS_ROUTER).getAmountsOut(totalRewards, booToWftmPath)[1];
        }

        // {DEUS} reward
        pendingReward = rewarder.pendingToken(poolId, address(this));
        totalRewards = pendingReward + IERC20Upgradeable(DEUS).balanceOf(address(this));
        if (totalRewards != 0) {
            profit += IUniswapV2Router02(TRISOLARIS_ROUTER).getAmountsOut(totalRewards, deusToWftmPath)[1];
        }

        profit += IERC20Upgradeable(WFTM).balanceOf(address(this));

        uint256 wftmFee = (profit * totalFee) / PERCENT_DIVISOR;
        callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
        profit -= wftmFee;
    }

    /**
     * @dev Function to retire the strategy. Claims all rewards and withdraws
     *      all principal from external contracts, and sends everything back to
     *      the vault. Can only be called by strategist or owner.
     *
     * Note: this is not an emergency withdraw function. For that, see panic().
     */
    function _retireStrat() internal override {
        IMasterChefV2(MASTER_CHEF).deposit(poolId, 0); // deposit 0 to claim rewards
        _swap(IERC20Upgradeable(BOO).balanceOf(address(this)), booToWftmPath);
        _swap(IERC20Upgradeable(DEUS).balanceOf(address(this)), deusToWftmPath);
        _addLiquidity();

        (uint256 poolBal, ) = IMasterChefV2(MASTER_CHEF).userInfo(poolId, address(this));
        if (poolBal != 0) {
            IMasterChefV2(MASTER_CHEF).withdraw(poolId, poolBal);
        }

        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBalance != 0) {
            IERC20Upgradeable(want).safeTransfer(vault, wantBalance);
        }
    }

    /**
     * Withdraws all funds leaving rewards behind.
     */
    function _reclaimWant() internal override {
        IMasterChefV2(MASTER_CHEF).emergencyWithdraw(poolId, address(this));
    }
}
