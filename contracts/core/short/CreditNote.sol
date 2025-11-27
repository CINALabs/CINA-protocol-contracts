// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import { ICreditNote } from "../../interfaces/ICreditNote.sol";

/// @title CreditNote - 信用票据合约
/// @notice 代表用户在空头池中的借款凭证
/// @dev 继承自 ERC20Upgradeable，实现可转让的信用票据
///
/// ==================== 信用票据概述 ====================
///
/// 信用票据是什么？
/// - 当用户在空头池中借款时，会收到等量的信用票据
/// - 信用票据代表用户对空头池的债权
/// - 可以用信用票据赎回抵押品
///
/// 使用场景:
/// 1. 用户在空头池借款 -> 获得信用票据
/// 2. 用户持有信用票据 -> 可以转让给他人
/// 3. 用户使用信用票据赎回 -> 获得抵押品
///
contract CreditNote is ERC20Upgradeable, ICreditNote {
  /**********
   * 错误定义 *
   **********/

  /// @dev 当调用者不是 `PoolManager` 合约时抛出
  /// @notice 只有 PoolManager 可以铸造和销毁信用票据
  error ErrorUnauthorized();

  /***********************
   * 不可变变量 *
   ***********************/

  /// @dev 代币小数位数
  uint8 private _decimal;

  /// @notice `PoolManager` 合约地址
  /// @dev 只有 PoolManager 可以铸造和销毁信用票据
  address public immutable poolManager;

  /***************
   * 构造函数 *
   ***************/

  /// @notice 构造函数
  /// @param _poolManager PoolManager 合约地址
  constructor(address _poolManager) {
    poolManager = _poolManager;
  }

  /// @notice 初始化函数（代理模式）
  /// @param name 代币名称
  /// @param symbol 代币符号
  /// @param decimal 代币小数位数
  function initialize(string memory name, string memory symbol, uint8 decimal) external initializer {
    __ERC20_init(name, symbol);

    _decimal = decimal;
  }

  /*************************
   * 公共视图函数 *
   *************************/

  /// @notice 返回代币小数位数
  /// @return 小数位数
  function decimals() public view virtual override returns (uint8) {
    return _decimal;
  }

  /****************************
   * 公共状态修改函数 *
   ****************************/

  /// @inheritdoc ICreditNote
  /// @notice 铸造信用票据
  /// @dev 仅 PoolManager 可调用，当用户借款时调用
  /// @param to 接收者地址
  /// @param amount 铸造数量
  function mint(address to, uint256 amount) external {
    if (msg.sender != poolManager) revert ErrorUnauthorized();

    _mint(to, amount);
  }

  /// @inheritdoc ICreditNote
  /// @notice 销毁信用票据
  /// @dev 仅 PoolManager 可调用，当用户赎回时调用
  /// @param from 持有者地址
  /// @param amount 销毁数量
  function burn(address from, uint256 amount) external {
    if (msg.sender != poolManager) revert ErrorUnauthorized();

    _burn(from, amount);
  }
}
