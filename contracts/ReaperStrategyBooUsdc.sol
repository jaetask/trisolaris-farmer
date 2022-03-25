// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./abstract/ReaperBaseStrategyv1_1.sol";
import "./interfaces/IMasterChef.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniV2Pair.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

/**
 * @dev Deposit SpookySwap LP tokens into MasterChef. Harvest BOO rewards and recompound.
 */
contract ReaperStrategyBooUsdc is ReaperBaseStrategyv1_1 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // 3rd-party contract addresses
    address public constant SPOOKY_ROUTER = address(0xF491e7B69E4244ad4002BC14e878a34207E38c29);
    address public constant MASTER_CHEF = address(0x2b2929E785374c651a81A63878Ab22742656DcDd);

    /**
     * @dev Tokens Used:
     * {WFTM} - Required for liquidity routing when doing swaps.
     * {BOO} - Reward token for depositing LP into MasterChef.
     * {want} - Address of USDC-BOO LP token. (lowercase name for FE compatibility)
     * {lpToken0} - USDC (name for FE compatibility)
     * {lpToken1} - BOO (name for FE compatibility)
     */
    address public constant WFTM = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    address public constant BOO = address(0x841FAD6EAe12c286d1Fd18d1d525DFfA75C7EFFE);
    address public constant want = address(0xf8Cb2980120469d79958151daa45Eb937c6E1eD6);
    address public constant lpToken0 = address(0x04068DA6C83AFCFA0e13ba15A6696662335D5B75);
    address public constant lpToken1 = BOO;

    /**
     * @dev Paths used to swap tokens:
     * {booToWftmPath} - to swap {BOO} to {WFTM} (using SPOOKY_ROUTER)
     * {booToUsdcPath} - to swap half of {BOO} to {lpToken0} (using SPOOKY_ROUTER)
     */
    address[] public booToWftmPath;
    address[] public booToUsdcPath;

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
        address[] memory _strategists
    ) public initializer {
        __ReaperBaseStrategy_init(_vault, _feeRemitters, _strategists);
        booToWftmPath = [BOO, WFTM];
        booToUsdcPath = [BOO, lpToken0];
        poolId = 69;
    }

    /**
     * @dev Function that puts the funds to work.
     *      It gets called whenever someone deposits in the strategy's vault contract.
     */
    function _deposit() internal override {
        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBalance != 0) {
            IERC20Upgradeable(want).safeIncreaseAllowance(MASTER_CHEF, wantBalance);
            IMasterChef(MASTER_CHEF).deposit(poolId, wantBalance);
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal override {
        uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBal < _amount) {
            IMasterChef(MASTER_CHEF).withdraw(poolId, _amount - wantBal);
        }

        IERC20Upgradeable(want).safeTransfer(vault, _amount);
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     *      1. Claims {BOO} from the {MASTER_CHEF}.
     *      2. Swaps {totalFee}% of {BOO} to {WFTM} for fees.
     *      3. Swaps half of leftover {BOO} to {lpToken0}.
     *      4. Creates new LP tokens and deposits.
     */
    function _harvestCore() internal override {
        IMasterChef(MASTER_CHEF).deposit(poolId, 0); // deposit 0 to claim rewards

        IERC20Upgradeable boo = IERC20Upgradeable(BOO);
        _swap((boo.balanceOf(address(this)) * totalFee) / PERCENT_DIVISOR, booToWftmPath);
        _chargeFees();
        _swap(boo.balanceOf(address(this)) / 2, booToUsdcPath);

        _addLiquidity();
        deposit();
    }

    /**
     * @dev Helper function to swap tokens given an {_amount} and swap {_path}.
     */
    function _swap(uint256 _amount, address[] memory _path) internal {
        if (_path.length < 2 || _amount == 0) {
            return;
        }

        IERC20Upgradeable(_path[0]).safeIncreaseAllowance(SPOOKY_ROUTER, _amount);
        IUniswapV2Router02(SPOOKY_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            0,
            _path,
            address(this),
            block.timestamp
        );
    }

    /**
     * @dev Core harvest function.
     *      Charges fees based on the amount of WFTM gained from reward
     */
    function _chargeFees() internal {
        IERC20Upgradeable wftm = IERC20Upgradeable(WFTM);
        uint256 wftmFee = wftm.balanceOf(address(this));
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
     * @dev Core harvest function. Adds more liquidity using {lpToken0} and {lpToken1}.
     */
    function _addLiquidity() internal {
        uint256 lp0Bal = IERC20Upgradeable(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20Upgradeable(lpToken1).balanceOf(address(this));

        if (lp0Bal != 0 && lp1Bal != 0) {
            IUniswapV2Router02(SPOOKY_ROUTER).addLiquidity(
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
        (uint256 amount, ) = IMasterChef(MASTER_CHEF).userInfo(poolId, address(this));
        return amount + IERC20Upgradeable(want).balanceOf(address(this));
    }

    /**
     * @dev Returns the approx amount of profit from harvesting.
     *      Profit is denominated in WFTM, and takes fees into account.
     */
    function estimateHarvest() external view override returns (uint256 profit, uint256 callFeeToUser) {
        uint256 pendingReward = IMasterChef(MASTER_CHEF).pendingBOO(poolId, address(this));
        uint256 totalRewards = pendingReward + IERC20Upgradeable(BOO).balanceOf(address(this));

        if (totalRewards != 0) {
            profit += IUniswapV2Router02(SPOOKY_ROUTER).getAmountsOut(totalRewards, booToWftmPath)[1];
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
        IMasterChef(MASTER_CHEF).deposit(poolId, 0); // deposit 0 to claim rewards

        _swap(IERC20Upgradeable(BOO).balanceOf(address(this)) / 2, booToUsdcPath);

        _addLiquidity();

        (uint256 poolBal, ) = IMasterChef(MASTER_CHEF).userInfo(poolId, address(this));
        IMasterChef(MASTER_CHEF).withdraw(poolId, poolBal);

        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        IERC20Upgradeable(want).safeTransfer(vault, wantBalance);
    }

    /**
     * Withdraws all funds leaving rewards behind.
     */
    function _reclaimWant() internal override {
        IMasterChef(MASTER_CHEF).emergencyWithdraw(poolId);
    }
}
