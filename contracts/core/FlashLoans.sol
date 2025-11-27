// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { ProtocolFees } from "./ProtocolFees.sol";

/// @title FlashLoans - 闪电贷合约
/// @notice 提供闪电贷功能的基础合约
/// @dev 此合约已弃用，保留以维护存储布局兼容性
/// @custom:deprecated 此合约已弃用
contract FlashLoans is ProtocolFees, ReentrancyGuardUpgradeable {
  using SafeERC20 for IERC20;

  /*************
   * 存储变量 *
   *************/

  /// @dev 预留存储空间，用于未来扩展
  uint256[50] private _gap;

  /***************
   * 构造函数 *
   ***************/

  /// @dev 初始化闪电贷模块
  function __FlashLoans_init() internal onlyInitializing {}

  /*************************
   * 公共视图函数 *
   *************************/

  /****************************
   * 公共状态修改函数 *
   ****************************/
}
