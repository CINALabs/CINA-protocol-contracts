// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

/// @title PoolErrors - 池错误定义合约
/// @notice 定义资金池系统中所有可能抛出的错误
/// @dev 这是一个抽象合约，被其他池合约继承
abstract contract PoolErrors {
  /**********
   * 错误定义 *
   **********/
  
  /// @dev 当给定地址为零地址时抛出
  /// @notice 用于检查地址参数的有效性
  error ErrorZeroAddress();

  /// @dev 当给定值超过最大允许值时抛出
  /// @notice 用于检查数值参数的边界
  error ErrorValueTooLarge();
  
  /// @dev 当调用者不是池管理器时抛出
  /// @notice 只有 poolManager 可以调用某些函数
  error ErrorCallerNotPoolManager();
  
  /// @dev 当债务金额太小时抛出
  /// @notice 债务必须 >= MIN_DEBT (1e9)，防止粉尘攻击
  error ErrorDebtTooSmall();

  /// @dev 当抵押品金额太小时抛出
  /// @notice 抵押品必须 >= MIN_COLLATERAL (1e9)，防止粉尘攻击
  error ErrorCollateralTooSmall();
  
  /// @dev 当抵押品和债务金额都为零时抛出
  /// @notice 操作必须至少涉及抵押品或债务的变化
  error ErrorNoSupplyAndNoBorrow();
  
  /// @dev 当借款功能被暂停时抛出
  /// @notice 紧急情况下管理员可以暂停借款
  error ErrorBorrowPaused();

  /// @dev 当赎回功能被暂停时抛出
  /// @notice 紧急情况下管理员可以暂停赎回
  error ErrorRedeemPaused();
  
  /// @dev 当调用者不是仓位所有者时抛出（在提取或借款时）
  /// @notice 只有仓位所有者可以操作自己的仓位
  error ErrorNotPositionOwner();
  
  /// @dev 当提取金额超过已存入金额时抛出
  /// @notice 不能提取超过仓位中的抵押品
  error ErrorWithdrawExceedSupply();
  
  /// @dev 当债务比率太小时抛出
  /// @notice 债务比率必须 >= 最小债务比率 (minDebtRatio)
  error ErrorDebtRatioTooSmall();

  /// @dev 当债务比率太大时抛出
  /// @notice 债务比率必须 <= 最大债务比率 (maxDebtRatio)
  error ErrorDebtRatioTooLarge();
  
  /// @dev 当池处于抵押不足状态时抛出
  /// @notice 池的总抵押品价值低于总债务价值
  error ErrorPoolUnderCollateral();
  
  /// @dev 当当前债务比率 <= 再平衡债务比率时抛出
  /// @notice 只有当债务比率超过再平衡阈值时才能执行再平衡
  error ErrorRebalanceDebtRatioNotReached();

  /// @dev 当当前债务比率 > 清算债务比率时抛出
  /// @notice 仓位已进入清算模式，不能执行普通操作
  error ErrorPositionInLiquidationMode();

  /// @dev 当尝试对可清算的 tick 执行再平衡时抛出
  /// @notice 可清算的 tick 应该被清算而不是再平衡
  error ErrorRebalanceOnLiquidatableTick();

  /// @dev 当尝试对可清算的仓位执行再平衡时抛出
  /// @notice 可清算的仓位应该被清算而不是再平衡
  error ErrorRebalanceOnLiquidatablePosition();

  /// @dev 当清算时抵押品不足时抛出
  /// @notice 仓位的抵押品不足以支付清算奖励
  error ErrorInsufficientCollateralToLiquidate();

  /// @dev 当数值溢出时抛出
  /// @notice 计算结果超出数据类型范围
  error ErrorOverflow();

  /// @dev 当减少的债务过多时抛出
  /// @notice 不能减少超过仓位当前的债务
  error ErrorReduceTooMuchDebt();

  /// @dev 当 tick 没有移动时抛出
  /// @notice 某些操作要求 tick 必须发生变化
  error ErrorTickNotMoved();

  /**********************
   * 内部辅助函数 *
   **********************/

  /// @dev 检查值是否超过上限
  /// @param value 要检查的值
  /// @param upperBound 允许的上限值
  /// @notice 如果 value > upperBound，则抛出 ErrorValueTooLarge
  function _checkValueTooLarge(uint256 value, uint256 upperBound) internal pure {
    if (value > upperBound) revert ErrorValueTooLarge();
  }

  /// @dev 检查地址是否为零地址
  /// @param value 要检查的地址
  /// @notice 如果 value == address(0)，则抛出 ErrorZeroAddress
  function _checkAddressNotZero(address value) internal pure {
    if (value == address(0)) revert ErrorZeroAddress();
  }
}
