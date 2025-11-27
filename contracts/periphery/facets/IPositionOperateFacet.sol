// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/// @title IPositionOperateFacet
/// @notice 仓位操作门面接口，定义仓位操作相关的事件
/// @dev 被其他仓位操作相关的facet合约继承使用
interface IPositionOperateFacet {
  /// @notice Emitted when a position is operated.
  /// @notice 当仓位被操作时触发
  /// @param pool The address of the pool.
  /// @param pool 池子地址
  /// @param positionId The index of the position.
  /// @param positionId 仓位索引
  /// @param userCollateralsDelta The amount of collateral transferred from/to the user. Negative value means the user is transferring collateral to the position.
  /// @param userCollateralsDelta 用户转入/转出的抵押品数量。负值表示用户正在向仓位转入抵押品
  /// @param userDebtsDelta The amount of debt transferred from/to the user. Negative value means the user is transferring debt to the position.
  /// @param userDebtsDelta 用户转入/转出的债务数量。负值表示用户正在向仓位转入债务
  /// @param newColl The new collateral amount of the position.
  /// @param newColl 仓位的新抵押品数量
  /// @param newDebt The new debt amount of the position.
  /// @param newDebt 仓位的新债务数量
  event PositionOperate(
    address indexed pool,
    uint256 positionId,
    int256 userCollateralsDelta,
    int256 userDebtsDelta,
    int256 newColl,
    int256 newDebt
  );
}
