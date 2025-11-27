// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { IPool } from "../../interfaces/IPool.sol";

/// @title PoolConstant - 池常量合约
/// @notice 定义资金池系统中使用的所有常量和不可变变量
/// @dev 这是一个抽象合约，被其他池合约继承
abstract contract PoolConstant is IPool {
  /*************
   * 常量定义 *
   *************/

  /// @dev 紧急操作角色标识符
  /// @notice 用于访问控制，授予此角色的地址可以执行紧急操作（如暂停借贷/赎回）
  bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

  /// @dev 最小抵押品数量 (1e9 = 1 Gwei)
  /// @notice 防止仓位的抵押品过小，避免精度损失和粉尘攻击
  int256 internal constant MIN_COLLATERAL = 1e9;

  /// @dev 最小债务数量 (1e9 = 1 Gwei)
  /// @notice 防止仓位的债务过小，避免精度损失和粉尘攻击
  int256 internal constant MIN_DEBT = 1e9;

  /// @dev 通用计算精度 (1e18)
  /// @notice 用于份额转换、比率计算等，与 ERC20 的 18 位小数一致
  uint256 internal constant PRECISION = 1e18;

  /// @dev 费用比率计算精度 (1e9)
  /// @notice 用于费用相关的比率计算，1e7 = 1%
  uint256 internal constant FEE_PRECISION = 1e9;

  /// @dev 位操作常量 - 2的60次方
  /// @notice 用于将多个值打包到单个 uint256 中，节省存储空间
  uint256 internal constant E60 = 2 ** 60; // 2^60

  /// @dev 位操作常量 - 2的96次方
  /// @notice 用于将多个值打包到单个 uint256 中
  uint256 internal constant E96 = 2 ** 96; // 2^96

  /// @dev 位掩码 - 60位全1 (2^60 - 1)
  /// @notice 用于从打包数据中提取 60 位字段: value = packed & X60
  uint256 internal constant X60 = 0xfffffffffffffff; // 2^60 - 1

  /// @dev 位掩码 - 96位全1 (2^96 - 1)
  /// @notice 用于从打包数据中提取 96 位字段: value = (packed >> 60) & X96
  uint256 internal constant X96 = 0xffffffffffffffffffffffff; // 2^96 - 1

  /***********************
   * 不可变变量 *
   ***********************/

  /// @inheritdoc IPool
  /// @notice fxUSD 稳定币合约地址
  /// @dev 用户借出的资产就是 fxUSD，借款时铸造，还款时销毁
  address public immutable fxUSD;

  /// @inheritdoc IPool
  /// @notice 池管理器合约地址
  /// @dev 用户交互的入口，负责路由请求到正确的池，管理多个池的全局状态
  address public immutable poolManager;

  /// @inheritdoc IPool
  /// @notice 池配置合约地址
  /// @dev 存储池的配置参数（清算阈值、费用比率、再平衡参数等）
  address public immutable configuration;
}
