// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./abstract/ReaperBaseStrategyv1_1.sol";
import "./interfaces/IMasterChef.sol";
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
    address public constant MASTER_CHEF = address(0x3838956710bcc9D122Dd23863a0549ca8D5675D6);

    /**
     * @dev Tokens Used:
     * {WAURORA} - Required for liquidity routing when doing swaps.
     * {TRI} - Reward token for depositing LP into MasterChef.
     * {want} - Address of the LP token to farm. (lowercase name for FE compatibility)
     * {lpToken0} - First token of the want LP
     * {lpToken1} - Second token of the want LP
     */
    address public constant WAURORA = address(0xb1fb4b94d987A6b247d87b3AC7FF2a83367ECDcB);
    address public constant TRI = address(0xFa94348467f64D5A457F75F8bc40495D33c65aBB);
    address public want;
    address public lpToken0;
    address public lpToken1;

    /**
     * @dev Paths used to swap tokens:
     * {triToWauroraPath} - to swap {TRI} to {WAURORA} (using TRISOLARIS_ROUTER)
     */
    address[] public triToWauroraPath;

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
        triToWauroraPath = [TRI, WAURORA];
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
            IMasterChef(MASTER_CHEF).deposit(poolId, wantBalance);
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal override {
        uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMasterChef(MASTER_CHEF).withdraw(poolId, _amount - wantBal, address(this));
        }
        IERC20Upgradeable(want).safeTransfer(vault, _amount);
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     *      1. Claims {TRI} from the {MASTER_CHEF}.
     *      2. Swaps {TRI} to {WAURORA}.
     *      3. Charge fees.
     *      4. Creates new LP tokens.
     *      5. Deposits LP in the Master Chef.
     */
    function _harvestCore() internal override {
        _claimRewards();
        _swapToWAURORA();
        _chargeFees();
        _addLiquidity();
        deposit();
    }

    function _claimRewards() internal {
        IMasterChef(MASTER_CHEF).deposit(poolId, 0); // deposit 0 to claim rewards
    }

    function _swapToWAURORA() internal {
        IERC20Upgradeable tri = IERC20Upgradeable(TRI);
        _swap((tri.balanceOf(address(this))), triToWauroraPath);
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
     *      Charges fees based on the amount of WAURORA gained from reward
     */
    function _chargeFees() internal {
        IERC20Upgradeable waurora = IERC20Upgradeable(WAURORA);
        uint256 wauroraFee = (waurora.balanceOf(address(this)) * totalFee) / PERCENT_DIVISOR;
        if (wauroraFee != 0) {
            uint256 callFeeToUser = (wauroraFee * callFee) / PERCENT_DIVISOR;
            uint256 treasuryFeeToVault = (wauroraFee * treasuryFee) / PERCENT_DIVISOR;
            uint256 feeToStrategist = (treasuryFeeToVault * strategistFee) / PERCENT_DIVISOR;
            treasuryFeeToVault -= feeToStrategist;

            waurora.safeTransfer(msg.sender, callFeeToUser);
            waurora.safeTransfer(treasury, treasuryFeeToVault);
            waurora.safeTransfer(strategistRemitter, feeToStrategist);
        }
    }

    /**
     * @dev Core harvest function. Adds more liquidity using {lpToken0} and {lpToken1}.
     */
    function _addLiquidity() internal {
        uint256 lp0Bal = IERC20Upgradeable(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20Upgradeable(lpToken1).balanceOf(address(this));

        if (lpToken0 == WAURORA) {
            address[] memory wauroraToLP1 = new address[](2);
            wauroraToLP1[0] = WAURORA;
            wauroraToLP1[1] = lpToken1;
            _swap(lp0Bal / 2, wauroraToLP1);
        } else {
            address[] memory wauroraToLP0 = new address[](2);
            wauroraToLP0[0] = WAURORA;
            wauroraToLP0[1] = lpToken0;
            _swap(lp1Bal / 2, wauroraToLP0);
        }

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
        (uint256 amount, ) = IMasterChef(MASTER_CHEF).userInfo(poolId, address(this));
        return amount + IERC20Upgradeable(want).balanceOf(address(this));
    }

    /**
     * @dev Returns the approx amount of profit from harvesting.
     *      Profit is denominated in WAURORA, and takes fees into account.
     */
    function estimateHarvest() external view override returns (uint256 profit, uint256 callFeeToUser) {
        uint256 pendingReward = IMasterChef(MASTER_CHEF).pendingTri(poolId, address(this));
        uint256 totalRewards = pendingReward + IERC20Upgradeable(TRI).balanceOf(address(this));

        if (totalRewards != 0) {
            profit += IUniswapV2Router02(TRISOLARIS_ROUTER).getAmountsOut(totalRewards, triToWauroraPath)[1];
        }

        profit += IERC20Upgradeable(WAURORA).balanceOf(address(this));

        uint256 wauroraFee = (profit * totalFee) / PERCENT_DIVISOR;
        callFeeToUser = (wauroraFee * callFee) / PERCENT_DIVISOR;
        profit -= wauroraFee;
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

        _swapToWAURORA();

        _addLiquidity();

        (uint256 poolBal, ) = IMasterChef(MASTER_CHEF).userInfo(poolId, address(this));
        IMasterChef(MASTER_CHEF).withdraw(poolId, poolBal, address(this));

        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        IERC20Upgradeable(want).safeTransfer(vault, wantBalance);
    }

    /**
     * Withdraws all funds leaving rewards behind.
     */
    function _reclaimWant() internal override {
        IMasterChef(MASTER_CHEF).emergencyWithdraw(poolId, vault);
    }
}
