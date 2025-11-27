// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IMorpho } from "../../interfaces/Morpho/IMorpho.sol";
import { ISmartWalletChecker } from "../../voting-escrow/interfaces/ISmartWalletChecker.sol";

import { LibRouter } from "../libraries/LibRouter.sol";

/// @title MorphoFlashLoanFacetBase
/// @notice Morpho闪电贷门面基础合约，提供闪电贷相关的基础功能和修饰符
/// @dev 抽象合约，被其他需要闪电贷功能的facet继承
abstract contract MorphoFlashLoanFacetBase {
  /**********
   * Errors *
   **********/
  /// @dev 错误定义

  /// @dev Thrown when the caller is not self.
  /// @dev 当调用者不是合约自身时抛出
  error ErrorNotFromSelf();

  /// @dev Unauthorized reentrant call.
  /// @dev 未授权的重入调用
  error ReentrancyGuardReentrantCall();

  /// @dev Thrown when the caller is not a top level call.
  /// @dev 当调用不是顶层调用时抛出
  error ErrorTopLevelCall();

  /***********************
   * Immutable Variables *
   ***********************/
  /// @dev 不可变变量

  /// @dev The address of Morpho Blue contract.
  /// @dev Morpho Blue合约地址
  /// In ethereum, it is 0xbbbbbbbbbb9cc5e90e3b3af64bdaf62c37eeffcb.
  /// 在以太坊主网上，地址为0xbbbbbbbbbb9cc5e90e3b3af64bdaf62c37eeffcb
  address private immutable morpho;

  /// @notice The address of smart wallet whitelist.
  /// @notice 智能钱包白名单地址
  address private immutable whitelist;

  /*************
   * Modifiers *
   *************/
  /// @dev 修饰符

  /// @dev 仅允许合约自身调用
  modifier onlySelf() {
    if (msg.sender != address(this)) revert ErrorNotFromSelf();
    _;
  }

  /// @dev 闪电贷上下文修饰符，设置闪电贷状态标志
  modifier onFlashLoan() {
    LibRouter.RouterStorage storage $ = LibRouter.routerStorage();
    $.flashLoanContext = LibRouter.HAS_FLASH_LOAN;
    _;
    $.flashLoanContext = LibRouter.NOT_FLASH_LOAN;
  }

  /// @dev 防重入修饰符
  modifier nonReentrant() {
    LibRouter.RouterStorage storage $ = LibRouter.routerStorage();
    if ($.reentrantContext == LibRouter.HAS_ENTRANT) {
      revert ReentrancyGuardReentrantCall();
    }
    $.reentrantContext = LibRouter.HAS_ENTRANT;
    _;
    $.reentrantContext = LibRouter.NOT_ENTRANT;
  }


  /*************
   * Modifiers *
   *************/
  /// @dev 修饰符（续）

  /// @dev 仅允许顶层调用或白名单智能钱包调用
  modifier onlyTopLevelCall() {
    uint256 codesize = msg.sender.code.length;
    if (whitelist != address(0) && (codesize > 0 || msg.sender != tx.origin)) {
      if (!ISmartWalletChecker(whitelist).check(msg.sender)) {
        revert ErrorTopLevelCall();
      }
    }
    _;
  }

  /***************
   * Constructor *
   ***************/
  /// @dev 构造函数

  constructor(address _morpho, address _whitelist) {
    morpho = _morpho;
    whitelist = _whitelist;
  }

  /**********************
   * Internal Functions *
   **********************/
  /// @dev 内部函数

  /// @dev 内部函数：调用Morpho闪电贷
  /// @param token 要借入的代币地址
  /// @param amount 要借入的数量
  /// @param data 回调数据
  function _invokeFlashLoan(address token, uint256 amount, bytes memory data) internal onFlashLoan {
    IMorpho(morpho).flashLoan(token, amount, abi.encode(token, data));
  }
}
