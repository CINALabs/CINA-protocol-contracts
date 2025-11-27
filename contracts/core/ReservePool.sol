// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;
pragma abicoder v2;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IReservePool } from "../interfaces/IReservePool.sol";

/// @title ReservePool - 储备池合约
/// @notice 管理协议的储备资金，用于清算奖励补贴
/// @dev 当清算时抵押品不足以支付奖励时，从储备池中补贴
///
/// ==================== 储备池概述 ====================
///
/// 储备池的作用:
/// 1. 存储协议的储备资金
/// 2. 在清算时提供奖励补贴
/// 3. 确保清算者始终能获得足够的奖励
///
/// 工作流程:
/// 1. 协议收益的一部分存入储备池
/// 2. 清算时，如果仓位的抵押品不足以支付奖励
/// 3. PoolManager 从储备池请求补贴
/// 4. 储备池转移资金给清算者
///
contract ReservePool is AccessControl, IReservePool {
  using EnumerableSet for EnumerableSet.AddressSet;
  using SafeERC20 for IERC20;

  /**********
   * 错误定义 *
   **********/

  /// @dev 当奖励比率过大时抛出
  error ErrorRatioTooLarge();

  /// @dev 当添加已存在的再平衡池时抛出
  error ErrorRebalancePoolAlreadyAdded();

  /// @dev 当移除不存在的再平衡池时抛出
  error ErrorRebalancePoolNotAdded();

  /// @dev 当调用者不是 PoolManager 时抛出
  error ErrorCallerNotPoolManager();

  /*************
   * 常量定义 *
   *************/

  /// @notice PoolManager 角色标识符
  /// @dev 拥有此角色的地址可以请求奖励补贴
  bytes32 public constant POOL_MANAGER_ROLE = keccak256("POOL_MANAGER_ROLE");

  /*************
   * 存储变量 *
   *************/

  /***************
   * 构造函数 *
   ***************/

  /// @notice 构造函数
  /// @param admin 管理员地址
  /// @param _poolManager PoolManager 合约地址
  constructor(address admin, address _poolManager) {
    _grantRole(POOL_MANAGER_ROLE, _poolManager);
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
  }

  /*************************
   * 公共视图函数 *
   *************************/

  /// @inheritdoc IReservePool
  /// @notice 获取指定代币的余额
  /// @param token 代币地址（address(0) 表示 ETH）
  /// @return 代币余额
  function getBalance(address token) external view returns (uint256) {
    return _getBalance(token);
  }

  /****************************
   * 公共状态修改函数 *
   ****************************/

  /// @notice 接收 ETH
  // solhint-disable-next-line no-empty-blocks
  receive() external payable {}

  /// @inheritdoc IReservePool
  /// @notice 请求奖励补贴
  /// @dev 仅 PoolManager 可调用，用于清算时的奖励补贴
  /// @param _token 代币地址
  /// @param _recipient 接收者地址
  /// @param _bonus 请求的奖励数量
  function requestBonus(address _token, address _recipient, uint256 _bonus) external onlyRole(POOL_MANAGER_ROLE) {
    uint256 _balance = _getBalance(_token);

    // 如果请求的奖励超过余额，只转移余额
    if (_bonus > _balance) {
      _bonus = _balance;
    }
    if (_bonus > 0) {
      _transferToken(_token, _recipient, _bonus);

      emit RequestBonus(_token, _recipient, _bonus);
    }
  }

  /************************
   * 管理函数 *
   ************************/

  /// @notice 提取合约中的资金
  /// @dev 仅管理员可调用，用于提取多余的资金
  /// @param _token 代币地址
  /// @param amount 提取数量
  /// @param _recipient 接收者地址
  function withdrawFund(address _token, uint256 amount, address _recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _transferToken(_token, _recipient, amount);
  }

  /**********************
   * 内部函数 *
   **********************/

  /// @dev 获取指定代币的余额
  /// @param _token 代币地址（address(0) 表示 ETH）
  /// @return 代币余额
  function _getBalance(address _token) internal view returns (uint256) {
    if (_token == address(0)) {
      return address(this).balance;
    } else {
      return IERC20(_token).balanceOf(address(this));
    }
  }

  /// @dev 转移 ETH 或 ERC20 代币
  /// @param _token 代币地址（address(0) 表示 ETH）
  /// @param _receiver 接收者地址
  /// @param _amount 转移数量
  function _transferToken(address _token, address _receiver, uint256 _amount) internal {
    if (_token == address(0)) {
      Address.sendValue(payable(_receiver), _amount);
    } else {
      IERC20(_token).safeTransfer(_receiver, _amount);
    }
  }
}
