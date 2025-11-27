// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { LibDiamond } from "../../common/EIP2535/libraries/LibDiamond.sol";
import { LibRouter } from "../libraries/LibRouter.sol";

/// @title RouterManagementFacet
/// @notice 路由器管理门面合约，提供路由器配置的管理功能
/// @dev 作为Diamond代理模式的一个facet，管理批准的目标合约、白名单和收益池
contract RouterManagementFacet {
  using EnumerableSet for EnumerableSet.AddressSet;

  /*************************
   * Public View Functions *
   *************************/
  /// @dev 公共视图函数

  /// @notice Return the token approve spender for the given target.
  /// @notice 返回给定目标的代币授权支出者
  /// @param target 目标合约地址
  /// @return _spender 支出者地址
  function getSpender(address target) external view returns (address _spender) {
    LibRouter.RouterStorage storage $ = LibRouter.routerStorage();
    _spender = $.spenders[target];
    if (_spender == address(0)) _spender = target;
  }

  /// @notice Return the list of approved targets.
  /// @notice 返回已批准的目标合约列表
  /// @return _accounts 已批准的目标地址数组
  function getApprovedTargets() external view returns (address[] memory _accounts) {
    LibRouter.RouterStorage storage $ = LibRouter.routerStorage();
    uint256 _numAccount = $.approvedTargets.length();
    _accounts = new address[](_numAccount);
    for (uint256 i = 0; i < _numAccount; i++) {
      _accounts[i] = $.approvedTargets.at(i);
    }
  }

  /// @notice Return the whitelist kind for the given target.
  /// @notice 返回白名单地址列表
  /// @return _accounts 白名单地址数组
  function getWhitelisted() external view returns (address[] memory _accounts) {
    LibRouter.RouterStorage storage $ = LibRouter.routerStorage();
    uint256 _numAccount = $.whitelisted.length();
    _accounts = new address[](_numAccount);
    for (uint256 i = 0; i < _numAccount; i++) {
      _accounts[i] = $.whitelisted.at(i);
    }
  }

  /// @notice 返回收益池地址
  /// @return 收益池地址
  function getRevenuePool() external view returns (address) {
    LibRouter.RouterStorage storage $ = LibRouter.routerStorage();
    return $.revenuePool;
  }

  /************************
   * Restricted Functions *
   ************************/
  /// @dev 受限函数（仅合约所有者可调用）

  /// @notice Approve contract to be used in token converting.
  /// @notice 批准合约用于代币转换
  /// @param target 目标合约地址
  /// @param spender 支出者地址
  function approveTarget(address target, address spender) external {
    LibDiamond.enforceIsContractOwner();
    LibRouter.approveTarget(target, spender);
  }

  /// @notice Remove approve contract in token converting.
  /// @notice 移除代币转换中的已批准合约
  /// @param target 要移除的目标合约地址
  function removeTarget(address target) external {
    LibDiamond.enforceIsContractOwner();
    LibRouter.removeTarget(target);
  }

  /// @notice Update whitelist status of the given contract.
  /// @notice 更新给定合约的白名单状态
  /// @param target 目标合约地址
  /// @param status 白名单状态（true为添加，false为移除）
  function updateWhitelist(address target, bool status) external {
    LibDiamond.enforceIsContractOwner();
    LibRouter.updateWhitelist(target, status);
  }

  /// @notice Update revenue pool.
  /// @notice 更新收益池地址
  /// @param revenuePool 新的收益池地址
  function updateRevenuePool(address revenuePool) external {
    LibDiamond.enforceIsContractOwner();
    LibRouter.updateRevenuePool(revenuePool);
  }
}
