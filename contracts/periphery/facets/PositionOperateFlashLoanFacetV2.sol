// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { IMultiPathConverter } from "../../helpers/interfaces/IMultiPathConverter.sol";
import { IPoolManager } from "../../interfaces/IPoolManager.sol";
import { IPool } from "../../interfaces/IPool.sol";

import { WordCodec } from "../../common/codec/WordCodec.sol";
import { LibRouter } from "../libraries/LibRouter.sol";
import { MorphoFlashLoanFacetBase } from "./MorphoFlashLoanFacetBase.sol";

/// @title PositionOperateFlashLoanFacetV2
/// @notice 仓位操作闪电贷门面合约V2，使用Morpho闪电贷实现杠杆开仓和平仓功能
/// @dev 继承MorphoFlashLoanFacetBase，作为Diamond代理模式的一个facet
contract PositionOperateFlashLoanFacetV2 is MorphoFlashLoanFacetBase {
  using EnumerableSet for EnumerableSet.AddressSet;
  using SafeERC20 for IERC20;
  using WordCodec for bytes32;

  /**********
   * Events *
   **********/
  /// @dev 事件定义

  /// @notice 开仓或增加抵押品时触发
  /// @param pool 池子地址
  /// @param position 仓位索引
  /// @param recipient 接收者地址
  /// @param colls 抵押品数量
  /// @param debts 债务数量
  /// @param borrows 借入数量
  event OpenOrAdd(address pool, uint256 position, address recipient, uint256 colls, uint256 debts, uint256 borrows);

  /// @notice 平仓或移除抵押品时触发
  /// @param pool 池子地址
  /// @param position 仓位索引
  /// @param recipient 接收者地址
  /// @param colls 抵押品数量
  /// @param debts 债务数量
  /// @param borrows 借入数量
  event CloseOrRemove(address pool, uint256 position, address recipient, uint256 colls, uint256 debts, uint256 borrows);

  /**********
   * Errors *
   **********/
  /// @dev 错误定义

  /// @dev Thrown when the amount of tokens swapped are not enough.
  /// @dev 当兑换的代币数量不足时抛出
  error ErrorInsufficientAmountSwapped();

  /// @dev Thrown when debt ratio out of range.
  /// @dev 当债务比率超出范围时抛出
  error ErrorDebtRatioOutOfRange();

  /*************
   * Constants *
   *************/
  /// @dev 常量定义

  /// @notice fxUSD代币地址
  address private constant fxUSD = 0x085780639CC2cACd35E474e71f4d000e2405d8f6;

  /***********************
   * Immutable Variables *
   ***********************/
  /// @dev 不可变变量

  /// @dev The address of `PoolManager` contract.
  /// @dev 池管理器合约地址
  address private immutable poolManager;

  /***************
   * Constructor *
   ***************/
  /// @dev 构造函数

  constructor(address _morpho, address _poolManager, address _whitelist) MorphoFlashLoanFacetBase(_morpho, _whitelist) {
    poolManager = _poolManager;
  }

  /****************************
   * Public Mutated Functions *
   ****************************/
  /// @dev 公共状态修改函数

  /// @notice Open a new position or add collateral to position with any tokens.
  /// @notice 使用任意代币开新仓位或向仓位添加抵押品
  /// @param params The parameters to convert source token to collateral token.
  /// @param params 将源代币转换为抵押品代币的参数
  /// @param pool The address of fx position pool.
  /// @param pool fx仓位池地址
  /// @param positionId The index of position.
  /// @param positionId 仓位索引
  /// @param borrowAmount The amount of collateral token to borrow.
  /// @param borrowAmount 要借入的抵押品代币数量
  /// @param data Hook data passing to `onOpenOrAddPositionFlashLoan`.
  /// @param data 传递给`onOpenOrAddPositionFlashLoan`的钩子数据
  function openOrAddPositionFlashLoanV2(
    LibRouter.ConvertInParams memory params,
    address pool,
    uint256 positionId,
    uint256 borrowAmount,
    bytes calldata data
  ) external payable nonReentrant onlyTopLevelCall {
    uint256 amountIn = LibRouter.transferInAndConvert(params, IPool(pool).collateralToken()) + borrowAmount;
    _invokeFlashLoan(
      IPool(pool).collateralToken(),
      borrowAmount,
      abi.encodeCall(
        PositionOperateFlashLoanFacetV2.onOpenOrAddPositionFlashLoanV2,
        (pool, positionId, amountIn, borrowAmount, msg.sender, data)
      )
    );
    // transfer extra collateral token to revenue pool
    LibRouter.refundERC20(IPool(pool).collateralToken(), LibRouter.routerStorage().revenuePool);
  }

  /// @notice Close a position or remove collateral from position.
  /// @notice 关闭仓位或从仓位中移除抵押品
  /// @param params The parameters to convert collateral token to target token.
  /// @param params 将抵押品代币转换为目标代币的参数
  /// @param positionId The index of position.
  /// @param positionId 仓位索引
  /// @param pool The address of fx position pool.
  /// @param pool fx仓位池地址
  /// @param borrowAmount The amount of collateral token to borrow.
  /// @param borrowAmount 要借入的抵押品代币数量
  /// @param data Hook data passing to `onCloseOrRemovePositionFlashLoan`.
  /// @param data 传递给`onCloseOrRemovePositionFlashLoan`的钩子数据
  function closeOrRemovePositionFlashLoanV2(
    LibRouter.ConvertOutParams memory params,
    address pool,
    uint256 positionId,
    uint256 amountOut,
    uint256 borrowAmount,
    bytes calldata data
  ) external nonReentrant onlyTopLevelCall {
    address collateralToken = IPool(pool).collateralToken();

    _invokeFlashLoan(
      collateralToken,
      borrowAmount,
      abi.encodeCall(
        PositionOperateFlashLoanFacetV2.onCloseOrRemovePositionFlashLoanV2,
        (pool, positionId, amountOut, borrowAmount, msg.sender, data)
      )
    );

    // convert collateral token to other token
    amountOut = IERC20(collateralToken).balanceOf(address(this));
    LibRouter.convertAndTransferOut(params, collateralToken, amountOut, msg.sender);

    // transfer extra fxUSD to revenue pool
    LibRouter.refundERC20(fxUSD, LibRouter.routerStorage().revenuePool);
  }

  /// @notice Hook for `openOrAddPositionFlashLoan`.
  /// @notice `openOrAddPositionFlashLoan`的回调钩子
  /// @param pool The address of fx position pool.
  /// @param pool fx仓位池地址
  /// @param position The index of position.
  /// @param position 仓位索引
  /// @param amount The amount of collateral token to supply.
  /// @param amount 要提供的抵押品代币数量
  /// @param repayAmount The amount of collateral token to repay.
  /// @param repayAmount 要偿还的抵押品代币数量
  /// @param recipient The address of position holder.
  /// @param recipient 仓位持有者地址
  /// @param data Hook data passing to `onOpenOrAddPositionFlashLoan`.
  /// @param data 传递给`onOpenOrAddPositionFlashLoan`的钩子数据
  function onOpenOrAddPositionFlashLoanV2(
    address pool,
    uint256 position,
    uint256 amount,
    uint256 repayAmount,
    address recipient,
    bytes memory data
  ) external onlySelf {
    (bytes32 miscData, uint256 fxUSDAmount, address swapTarget, bytes memory swapData) = abi.decode(
      data,
      (bytes32, uint256, address, bytes)
    );

    // open or add collateral to position
    if (position != 0) {
      IERC721(pool).transferFrom(recipient, address(this), position);
    }
    LibRouter.approve(IPool(pool).collateralToken(), poolManager, amount);
    position = IPoolManager(poolManager).operate(pool, position, int256(amount), int256(fxUSDAmount));
    _checkPositionDebtRatio(pool, position, miscData);
    IERC721(pool).transferFrom(address(this), recipient, position);

    emit OpenOrAdd(pool, position, recipient, amount, fxUSDAmount, repayAmount);

    // swap fxUSD to collateral token
    _swap(fxUSD, IPool(pool).collateralToken(), fxUSDAmount, repayAmount, swapTarget, swapData);
  }

  /// @notice Hook for `closeOrRemovePositionFlashLoan`.
  /// @notice `closeOrRemovePositionFlashLoan`的回调钩子
  /// @param pool The address of fx position pool.
  /// @param pool fx仓位池地址
  /// @param position The index of position.
  /// @param position 仓位索引
  /// @param amount The amount of collateral token to withdraw.
  /// @param amount 要提取的抵押品代币数量
  /// @param borrowAmount The amount of collateral token borrowed.
  /// @param borrowAmount 借入的抵押品代币数量
  /// @param recipient The address of position holder.
  /// @param recipient 仓位持有者地址
  /// @param data Hook data passing to `onCloseOrRemovePositionFlashLoan`.
  /// @param data 传递给`onCloseOrRemovePositionFlashLoan`的钩子数据
  function onCloseOrRemovePositionFlashLoanV2(
    address pool,
    uint256 position,
    uint256 amount,
    uint256 borrowAmount,
    address recipient,
    bytes memory data
  ) external onlySelf {
    (bytes32 miscData, uint256 fxUSDAmount, address swapTarget, bytes memory swapData) = abi.decode(
      data,
      (bytes32, uint256, address, bytes)
    );

    // swap collateral token to fxUSD
    _swap(IPool(pool).collateralToken(), fxUSD, borrowAmount, fxUSDAmount, swapTarget, swapData);

    // close or remove collateral from position
    IERC721(pool).transferFrom(recipient, address(this), position);
    (, uint256 maxFxUSD) = IPool(pool).getPosition(position);
    if (fxUSDAmount >= maxFxUSD) {
      // close entire position
      IPoolManager(poolManager).operate(pool, position, type(int256).min, type(int256).min);
    } else {
      IPoolManager(poolManager).operate(pool, position, -int256(amount), -int256(fxUSDAmount));
      _checkPositionDebtRatio(pool, position, miscData);
    }
    IERC721(pool).transferFrom(address(this), recipient, position);

    emit CloseOrRemove(pool, position, recipient, amount, fxUSDAmount, borrowAmount);
  }

  /**********************
   * Internal Functions *
   **********************/
  /// @dev 内部函数

  /// @dev Internal function to do swap. 内部函数：执行代币兑换
  /// @param tokenIn The address of input token. 输入代币地址
  /// @param tokenOut The address of output token. 输出代币地址
  /// @param amountIn The amount of input token. 输入代币数量
  /// @param minOut The minimum amount of output tokens should receive. 应收到的最小输出代币数量
  /// @param swapTarget The address of target contract used for swap. 用于兑换的目标合约地址
  /// @param swapData The calldata passed to target contract. 传递给目标合约的调用数据
  /// @return amountOut The amount of output tokens received. 收到的输出代币数量
  function _swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minOut,
    address swapTarget,
    bytes memory swapData
  ) internal returns (uint256 amountOut) {
    if (amountIn == 0) return 0;

    LibRouter.RouterStorage storage $ = LibRouter.routerStorage();
    if (!$.approvedTargets.contains(swapTarget)) {
      revert LibRouter.ErrorTargetNotApproved();
    }
    address spender = $.spenders[swapTarget];
    if (spender == address(0)) spender = swapTarget;
    LibRouter.approve(tokenIn, spender, amountIn);

    amountOut = IERC20(tokenOut).balanceOf(address(this));
    (bool success, ) = swapTarget.call(swapData);
    // below lines will propagate inner error up
    // 以下代码将内部错误向上传播
    if (!success) {
      // solhint-disable-next-line no-inline-assembly
      assembly {
        let ptr := mload(0x40)
        let size := returndatasize()
        returndatacopy(ptr, 0, size)
        revert(ptr, size)
      }
    }
    amountOut = IERC20(tokenOut).balanceOf(address(this)) - amountOut;

    if (amountOut < minOut) revert ErrorInsufficientAmountSwapped();
  }

  /// @dev Internal function to check debt ratio for the position. 内部函数：检查仓位的债务比率
  /// @param pool The address of fx position pool. fx仓位池地址
  /// @param positionId The index of the position. 仓位索引
  /// @param miscData The encoded data for debt ratio range. 债务比率范围的编码数据
  function _checkPositionDebtRatio(address pool, uint256 positionId, bytes32 miscData) internal view {
    uint256 debtRatio = IPool(pool).getPositionDebtRatio(positionId);
    uint256 minDebtRatio = miscData.decodeUint(0, 60);
    uint256 maxDebtRatio = miscData.decodeUint(60, 60);
    if (debtRatio < minDebtRatio || debtRatio > maxDebtRatio) {
      revert ErrorDebtRatioOutOfRange();
    }
  }
}
