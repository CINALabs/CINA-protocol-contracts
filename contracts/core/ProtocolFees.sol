// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { IPool } from "../interfaces/IPool.sol";
import { IProtocolFees } from "../interfaces/IProtocolFees.sol";

import { WordCodec } from "../common/codec/WordCodec.sol";

/// @title ProtocolFees - 协议费用管理合约
/// @notice 管理协议的各种费用参数和收益分配
/// @dev 抽象合约，被 PoolManager 和 ShortPoolManager 继承
///
/// ==================== 费用类型概述 ====================
///
/// 1. 奖励费用 (Rewards Expense)
///    - 从质押奖励中收取的协议费用
///    - 分配给国库
///
/// 2. 资金费用 (Funding Expense)
///    - 从资金费率收益中收取的协议费用
///    - 分配给国库
///
/// 3. 清算费用 (Liquidation Expense)
///    - 从清算/再平衡奖励中收取的协议费用
///    - 分配给国库
///
/// 4. 收割者奖励 (Harvester Ratio)
///    - 分配给调用 harvest 函数的用户
///    - 激励及时收割收益
///
/// 5. 闪电贷费用 (Flash Loan Fee)
///    - 闪电贷收取的费用
///
/// 6. 赎回费用 (Redeem Fee)
///    - 赎回操作收取的费用
///
abstract contract ProtocolFees is AccessControlUpgradeable, PausableUpgradeable, IProtocolFees {
  using SafeERC20 for IERC20;
  using WordCodec for bytes32;

  /**********
   * 错误定义 *
   **********/

  /// @dev 当给定地址为零地址时抛出
  error ErrorZeroAddress();

  /// @dev 当给定值超过最大允许值时抛出
  error ErrorValueTooLarge();

  /*************
   * 常量定义 *
   *************/

  /// @dev 最大费用比率 (50%)
  uint256 private constant MAX_EXPENSE_RATIO = 5e8; // 50%

  /// @dev 最大收割者比率 (20%)
  uint256 private constant MAX_HARVESTER_RATIO = 2e8; // 20%

  /// @dev 最大闪电贷费率 (10%)
  uint256 private constant MAX_FLASH_LOAN_FEE_RATIO = 1e8; // 10%

  /// @dev 最大赎回费率 (10%)
  uint256 private constant MAX_REDEEM_FEE_RATIO = 1e8; // 10%

  /// @dev _miscData 中奖励费用比率的位偏移量
  uint256 private constant REWARDS_EXPENSE_RATIO_OFFSET = 0;

  /// @dev _miscData 中收割者比率的位偏移量
  uint256 private constant HARVESTER_RATIO_OFFSET = 30;

  /// @dev _miscData 中闪电贷费率的位偏移量
  uint256 private constant FLASH_LOAN_RATIO_OFFSET = 60;

  /// @dev _miscData 中赎回费率的位偏移量
  uint256 private constant REDEEM_FEE_RATIO_OFFSET = 90;

  /// @dev _miscData 中资金费用比率的位偏移量
  uint256 private constant FUNDING_EXPENSE_RATIO_OFFSET = 120;

  /// @dev _miscData 中清算费用比率的位偏移量
  uint256 private constant LIQUIDATION_EXPENSE_RATIO_OFFSET = 150;

  /// @dev 费用计算精度 (1e9)
  uint256 internal constant FEE_PRECISION = 1e9;

  /*************
   * 存储变量 *
   *************/

  /// @dev `_miscData` 是一个存储槽，用于存储多个不相关的信息
  /// 所有池都存储 *费用比率*、*收割者比率* 和 *提款费率*，
  /// 但 `miscData` 可以扩展以存储更多信息。
  ///
  /// 字段布局 (从 MSB 到 LSB):
  /// | 字段                    | 位数    | 说明                           |
  /// |-------------------------|---------|-------------------------------|
  /// | rewards expense ratio   | 30 bits | 奖励费用比率 (×1e9)            |
  /// | harvester ratio         | 30 bits | 收割者比率 (×1e9)              |
  /// | flash loan ratio        | 30 bits | 闪电贷费率 (×1e9)              |
  /// | redeem ratio            | 30 bits | 赎回费率 (×1e9)                |
  /// | funding expense ratio   | 30 bits | 资金费用比率 (×1e9)            |
  /// | liquidation expense ratio| 30 bits| 清算费用比率 (×1e9)            |
  /// | available               | 76 bits | 保留位                         |
  bytes32 internal _miscData;

  /// @inheritdoc IProtocolFees
  /// @notice 国库地址
  /// @dev 接收协议费用
  address public treasury;

  /// @inheritdoc IProtocolFees
  /// @notice 开仓收益池地址
  /// @dev 存放开仓相关费用
  address public openRevenuePool;

  /// @inheritdoc IProtocolFees
  /// @notice 储备池地址
  /// @dev 用于清算奖励补贴
  address public reservePool;

  /// @inheritdoc IProtocolFees
  /// @notice 池累积的开仓费用
  mapping(address => uint256) public accumulatedPoolOpenFees;

  /// @inheritdoc IProtocolFees
  /// @notice 平仓收益池地址
  /// @dev 存放平仓相关费用
  address public closeRevenuePool;

  /// @inheritdoc IProtocolFees
  /// @notice 池累积的平仓费用
  mapping(address => uint256) public accumulatedPoolCloseFees;

  /// @inheritdoc IProtocolFees
  /// @notice 杂项收益池地址
  /// @dev 存放赎回、清算、再平衡相关费用
  address public miscRevenuePool;

  /// @inheritdoc IProtocolFees
  /// @notice 池累积的杂项费用
  mapping(address => uint256) public accumulatedPoolMiscFees;

  /***************
   * Constructor *
   ***************/

  function __ProtocolFees_init(
    uint256 _expenseRatio,
    uint256 _harvesterRatio,
    uint256 _flashLoanFeeRatio,
    address _treasury,
    address _revenuePool,
    address _reservePool
  ) internal onlyInitializing {
    _updateFundingExpenseRatio(_expenseRatio);
    _updateRewardsExpenseRatio(_expenseRatio);
    _updateLiquidationExpenseRatio(_expenseRatio);
    _updateHarvesterRatio(_harvesterRatio);
    _updateFlashLoanFeeRatio(_flashLoanFeeRatio);
    _updateTreasury(_treasury);
    _updateOpenRevenuePool(_revenuePool);
    _updateCloseRevenuePool(_revenuePool);
    _updateMiscRevenuePool(_revenuePool);
    _updateReservePool(_reservePool);
  }

  /*************************
   * Public View Functions *
   *************************/

  /// @inheritdoc IProtocolFees
  function getFundingExpenseRatio() public view returns (uint256) {
    return _miscData.decodeUint(FUNDING_EXPENSE_RATIO_OFFSET, 30);
  }

  /// @inheritdoc IProtocolFees
  function getRewardsExpenseRatio() public view returns (uint256) {
    return _miscData.decodeUint(REWARDS_EXPENSE_RATIO_OFFSET, 30);
  }

  /// @inheritdoc IProtocolFees
  function getLiquidationExpenseRatio() public view returns (uint256) {
    return _miscData.decodeUint(LIQUIDATION_EXPENSE_RATIO_OFFSET, 30);
  }

  /// @inheritdoc IProtocolFees
  function getHarvesterRatio() public view returns (uint256) {
    return _miscData.decodeUint(HARVESTER_RATIO_OFFSET, 30);
  }

  /* @dev removed to reduce codesize, since it is not used.
  /// @inheritdoc IProtocolFees
  function getFundingFxSaveRatio() external view returns (uint256) {
    return FEE_PRECISION - getFundingExpenseRatio() - getHarvesterRatio();
  }
  */

  /* @dev removed to reduce codesize, since it is not used.
  /// @inheritdoc IProtocolFees
  function getRewardsFxSaveRatio() external view returns (uint256) {
    unchecked {
      return FEE_PRECISION - getRewardsExpenseRatio() - getHarvesterRatio();
    }
  }
  */

  /// @inheritdoc IProtocolFees
  function getFlashLoanFeeRatio() public view returns (uint256) {
    return _miscData.decodeUint(FLASH_LOAN_RATIO_OFFSET, 30);
  }

  /// @inheritdoc IProtocolFees
  function getRedeemFeeRatio() public view returns (uint256) {
    return _miscData.decodeUint(REDEEM_FEE_RATIO_OFFSET, 30);
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @inheritdoc IProtocolFees
  function withdrawAccumulatedPoolFee(address[] memory pools) external {
    for (uint256 i = 0; i < pools.length; ++i) {
      _takeAccumulatedPoolFee(pools[i]);
    }
  }

  /************************
   * Restricted Functions *
   ************************/

  /// @notice Change address of reserve pool contract.
  /// @param _newReservePool The new address of reserve pool contract.
  function updateReservePool(address _newReservePool) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateReservePool(_newReservePool);
  }

  /// @notice Change address of treasury contract.
  /// @param _newTreasury The new address of treasury contract.
  function updateTreasury(address _newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateTreasury(_newTreasury);
  }

  /// @notice Change address of open revenue pool contract.
  /// @param _newPool The new address of revenue pool contract.
  function updateOpenRevenuePool(address _newPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateOpenRevenuePool(_newPool);
  }

  /// @notice Change address of close revenue pool contract.
  /// @param _newPool The new address of revenue pool contract.
  function updateCloseRevenuePool(address _newPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateCloseRevenuePool(_newPool);
  }

  /// @notice Change address of misc revenue pool contract.
  /// @param _newPool The new address of revenue pool contract.
  function updateMiscRevenuePool(address _newPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateMiscRevenuePool(_newPool);
  }

  /// @notice Update the fee ratio distributed to treasury.
  /// @param newRewardsRatio The new ratio for rewards to update, multiplied by 1e9.
  /// @param newFundingRatio The new ratio for funding to update, multiplied by 1e9.
  /// @param newLiquidationRatio The new ratio for liquidation/rebalance to update, multiplied by 1e9.
  function updateExpenseRatio(
    uint32 newRewardsRatio,
    uint32 newFundingRatio,
    uint32 newLiquidationRatio
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateRewardsExpenseRatio(newRewardsRatio);
    _updateFundingExpenseRatio(newFundingRatio);
    _updateLiquidationExpenseRatio(newLiquidationRatio);
  }

  /// @notice Update the fee ratio distributed to harvester.
  /// @param newRatio The new ratio to update, multiplied by 1e9.
  function updateHarvesterRatio(uint32 newRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateHarvesterRatio(newRatio);
  }

  /// @notice Update the flash loan fee ratio.
  /// @param newRatio The new ratio to update, multiplied by 1e9.
  function updateFlashLoanFeeRatio(uint32 newRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateFlashLoanFeeRatio(newRatio);
  }

  /// @notice Update the redeem fee ratio.
  /// @param newRatio The new ratio to update, multiplied by 1e9.
  function updateRedeemFeeRatio(uint32 newRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateRedeemFeeRatio(newRatio);
  }

  /**********************
   * Internal Functions *
   **********************/

  /// @dev Internal function to change address of treasury contract.
  /// @param _newTreasury The new address of treasury contract.
  function _updateTreasury(address _newTreasury) private {
    _checkAddressNotZero(_newTreasury);

    address _oldTreasury = treasury;
    treasury = _newTreasury;

    emit UpdateTreasury(_oldTreasury, _newTreasury);
  }

  /// @dev Internal function to change address of revenue pool contract.
  /// @param _newPool The new address of revenue pool contract.
  function _updateOpenRevenuePool(address _newPool) private {
    _checkAddressNotZero(_newPool);

    address _oldPool = openRevenuePool;
    openRevenuePool = _newPool;

    emit UpdateOpenRevenuePool(_oldPool, _newPool);
  }

  /// @dev Internal function to change address of revenue pool contract.
  /// @param _newPool The new address of revenue pool contract.
  function _updateCloseRevenuePool(address _newPool) private {
    _checkAddressNotZero(_newPool);

    address _oldPool = closeRevenuePool;
    closeRevenuePool = _newPool;

    emit UpdateCloseRevenuePool(_oldPool, _newPool);
  }

  /// @dev Internal function to change address of revenue pool contract.
  /// @param _newPool The new address of revenue pool contract.
  function _updateMiscRevenuePool(address _newPool) private {
    _checkAddressNotZero(_newPool);

    address _oldPool = miscRevenuePool;
    miscRevenuePool = _newPool;

    emit UpdateMiscRevenuePool(_oldPool, _newPool);
  }

  /// @dev Internal function to change the address of reserve pool contract.
  /// @param newReservePool The new address of reserve pool contract.
  function _updateReservePool(address newReservePool) private {
    _checkAddressNotZero(newReservePool);

    address oldReservePool = reservePool;
    reservePool = newReservePool;

    emit UpdateReservePool(oldReservePool, newReservePool);
  }

  /// @dev Internal function to update the misc data.
  /// @param newValue The new value to update.
  /// @param offset The offset of the value to update.
  /// @param length The length of the value to update.
  /// @return oldValue The old value.
  function _updateMiscData(uint256 newValue, uint256 offset, uint256 length) private returns (uint256 oldValue) {
    bytes32 _data = _miscData;
    oldValue = _miscData.decodeUint(offset, length);
    _miscData = _data.insertUint(newValue, offset, length);

    return oldValue;
  }

  /// @dev Internal function to update the fee ratio distributed to treasury.
  /// @param newRatio The new ratio to update, multiplied by 1e9.
  function _updateRewardsExpenseRatio(uint256 newRatio) private {
    _checkValueTooLarge(newRatio, MAX_EXPENSE_RATIO);
    uint256 oldRatio = _updateMiscData(newRatio, REWARDS_EXPENSE_RATIO_OFFSET, 30);
    emit UpdateRewardsExpenseRatio(oldRatio, newRatio);
  }

  /// @dev Internal function to update the fee ratio distributed to treasury.
  /// @param newRatio The new ratio to update, multiplied by 1e9.
  function _updateLiquidationExpenseRatio(uint256 newRatio) private {
    _checkValueTooLarge(newRatio, MAX_EXPENSE_RATIO);
    uint256 oldRatio = _updateMiscData(newRatio, LIQUIDATION_EXPENSE_RATIO_OFFSET, 30);
    emit UpdateLiquidationExpenseRatio(oldRatio, newRatio);
  }

  /// @dev Internal function to update the fee ratio distributed to treasury.
  /// @param newRatio The new ratio to update, multiplied by 1e9.
  function _updateFundingExpenseRatio(uint256 newRatio) private {
    _checkValueTooLarge(newRatio, MAX_EXPENSE_RATIO);
    uint256 oldRatio = _updateMiscData(newRatio, FUNDING_EXPENSE_RATIO_OFFSET, 30);
    emit UpdateFundingExpenseRatio(oldRatio, newRatio);
  }

  /// @dev Internal function to update the fee ratio distributed to harvester.
  /// @param newRatio The new ratio to update, multiplied by 1e9.
  function _updateHarvesterRatio(uint256 newRatio) private {
    _checkValueTooLarge(newRatio, MAX_HARVESTER_RATIO);
    uint256 oldRatio = _updateMiscData(newRatio, HARVESTER_RATIO_OFFSET, 30);
    emit UpdateHarvesterRatio(oldRatio, newRatio);
  }

  /// @dev Internal function to update the flash loan fee ratio.
  /// @param newRatio The new ratio to update, multiplied by 1e9.
  function _updateFlashLoanFeeRatio(uint256 newRatio) private {
    _checkValueTooLarge(newRatio, MAX_FLASH_LOAN_FEE_RATIO);
    uint256 oldRatio = _updateMiscData(newRatio, FLASH_LOAN_RATIO_OFFSET, 30);
    emit UpdateFlashLoanFeeRatio(oldRatio, newRatio);
  }

  /// @dev Internal function to update the redeem fee ratio.
  /// @param newRatio The new ratio to update, multiplied by 1e9.
  function _updateRedeemFeeRatio(uint256 newRatio) private {
    _checkValueTooLarge(newRatio, MAX_REDEEM_FEE_RATIO);
    uint256 oldRatio = _updateMiscData(newRatio, REDEEM_FEE_RATIO_OFFSET, 30);
    emit UpdateRedeemFeeRatio(oldRatio, newRatio);
  }

  /// @dev Internal function to accumulate protocol fee for the given pool.
  /// @param pool The address of pool.
  /// @param amount The amount of protocol fee.
  function _accumulatePoolOpenFee(address pool, uint256 amount) internal {
    unchecked {
      accumulatedPoolOpenFees[pool] += amount;
    }
  }

  /// @dev Internal function to accumulate protocol fee for the given pool.
  /// @param pool The address of pool.
  /// @param amount The amount of protocol fee.
  function _accumulatePoolCloseFee(address pool, uint256 amount) internal {
    unchecked {
      accumulatedPoolCloseFees[pool] += amount;
    }
  }

  /// @dev Internal function to accumulate protocol fee for the given pool.
  /// @param pool The address of pool.
  /// @param amount The amount of protocol fee.
  function _accumulatePoolMiscFee(address pool, uint256 amount) internal {
    unchecked {
      accumulatedPoolMiscFees[pool] += amount;
    }
  }

  /// @dev Internal function to withdraw accumulated protocol fee for the given pool.
  /// @param pool The address of pool.
  function _takeAccumulatedPoolFee(address pool) internal virtual {
    address collateralToken = IPool(pool).collateralToken();
    uint256 fees = accumulatedPoolOpenFees[pool];
    if (fees > 0) {
      IERC20(collateralToken).safeTransfer(openRevenuePool, fees);
      accumulatedPoolOpenFees[pool] = 0;
    }
    fees = accumulatedPoolCloseFees[pool];
    if (fees > 0) {
      IERC20(collateralToken).safeTransfer(closeRevenuePool, fees);
      accumulatedPoolCloseFees[pool] = 0;
    }
    fees = accumulatedPoolMiscFees[pool];
    if (fees > 0) {
      IERC20(collateralToken).safeTransfer(miscRevenuePool, fees);
      accumulatedPoolMiscFees[pool] = 0;
    }
  }

  /// @dev Internal function to check value not too large.
  /// @param value The value to check.
  /// @param upperBound The upper bound for the given value.
  function _checkValueTooLarge(uint256 value, uint256 upperBound) internal pure {
    if (value > upperBound) revert ErrorValueTooLarge();
  }

  /// @dev Internal function to check address is nonzero
  function _checkAddressNotZero(address value) internal pure {
    if (value == address(0)) revert ErrorZeroAddress();
  }

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   */
  uint256[41] private __gap;
}
