// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { ILongPoolManager } from "../../interfaces/ILongPoolManager.sol";
import { ILongPool } from "../../interfaces/ILongPool.sol";
import { IPoolConfiguration } from "../../interfaces/IPoolConfiguration.sol";
import { IShortPoolManager } from "../../interfaces/IShortPoolManager.sol";
import { IShortPool } from "../../interfaces/IShortPool.sol";

import { LibRouter } from "../libraries/LibRouter.sol";

/// @title PositionOperateFacet
/// @notice 仓位操作门面合约，提供多头仓位的借款和还款功能
/// @dev 作为Diamond代理模式的一个facet，处理仓位的基本操作
contract PositionOperateFacet {
  using SafeERC20 for IERC20;

  /**********
   * Events *
   **********/
  /// @dev 事件定义

  /// @notice Emitted when a position is operated.
  /// @notice 当仓位被操作时触发
  /// @param pool The address of the pool.
  /// @param pool 池子地址
  /// @param user The address of the user.
  /// @param user 用户地址
  /// @param positionId The index of the position.
  /// @param positionId 仓位索引
  /// @param deltaColls The amount of collateral transferred from/to the user. Negative value means the user is transferring collateral to the position.
  /// @param deltaColls 用户转入/转出的抵押品数量。负值表示用户正在向仓位转入抵押品
  /// @param deltaDebts The amount of debt transferred from/to the user. Negative value means the user is transferring debt to the position.
  /// @param deltaDebts 用户转入/转出的债务数量。负值表示用户正在向仓位转入债务
  event Operate(address indexed pool, address indexed user, uint256 positionId, int256 deltaColls, int256 deltaDebts);

  /**********
   * Errors *
   **********/
  /// @dev 错误定义

  /// @dev Unauthorized reentrant call.
  /// @dev 未授权的重入调用
  error ReentrancyGuardReentrantCall();

  /*************
   * Constants *
   *************/
  /// @dev 常量定义

  /// @dev The precision used for various calculation.
  /// @dev 用于各种计算的精度
  uint256 private constant PRECISION = 1e18;

  /// @dev The precision used to compute fees.
  /// @dev 用于计算费用的精度
  uint256 private constant FEE_PRECISION = 1e9;

  /// @dev The address of fxUSD token.
  /// @dev fxUSD代币地址
  address private constant fxUSD = 0x085780639CC2cACd35E474e71f4d000e2405d8f6;

  /// @dev The address of long pool manager.
  /// @dev 多头池管理器地址
  address private constant longPoolManager = 0x250893CA4Ba5d05626C785e8da758026928FCD24;

  /// @dev The address of short pool manager.
  /// @dev 空头池管理器地址
  address private constant shortPoolManager = 0xaCDc0AB51178d0Ae8F70c1EAd7d3cF5421FDd66D;

  /// @dev The address of PoolConfiguration.
  /// @dev 池配置合约地址
  address private constant configuration = 0x16b334f2644cc00b85DB1A1efF0C2C395e00C28d;

  /***********
   * Structs *
   ***********/
  /// @dev 结构体定义

  /// @notice The parameters to borrow from long pool.
  /// @notice 从多头池借款的参数
  /// @param pool The address of long pool.
  /// @param pool 多头池地址
  /// @param positionId The id of the position.
  /// @param positionId 仓位ID
  /// @param borrowAmount The amount of collateral token to borrow.
  /// @param borrowAmount 要借入的抵押品代币数量
  struct BorrowFromLongParams {
    address pool;
    uint256 positionId;
    uint256 borrowAmount;
  }

  /// @notice The parameters to repay to long pool.
  /// @notice 向多头池还款的参数
  /// @param pool The address of long pool.
  /// @param pool 多头池地址
  /// @param positionId The id of the position.
  /// @param positionId 仓位ID
  /// @param withdrawAmount The amount of collateral token to withdraw.
  /// @param withdrawAmount 要提取的抵押品代币数量
  struct RepayToLongParams {
    address pool;
    uint256 positionId;
    uint256 withdrawAmount;
  }

  /*************
   * Modifiers *
   *************/
  /// @dev 修饰符

  /// @dev Modifier to prevent reentrancy.
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

  /***************
   * Constructor *
   ***************/
  /// @dev 构造函数

  /****************************
   * Public Mutated Functions *
   ****************************/
  /// @dev 公共状态修改函数

  /// @notice Borrow collateral token from long pool with any tokens.
  ///         使用任意代币从多头池借入抵押品代币
  /// @param convertInParams The parameters to convert source token to collateral token. 将源代币转换为抵押品代币的参数
  /// @param borrowParams The parameters to borrow from long pool. 从多头池借款的参数
  /// @return positionId The actual position id. 实际的仓位ID
  function borrowFromLong(
    LibRouter.ConvertInParams memory convertInParams,
    BorrowFromLongParams memory borrowParams
  ) external payable nonReentrant returns (uint256) {
    address collateralToken = ILongPool(borrowParams.pool).collateralToken();
    uint256 amountIn;
    if (convertInParams.amount > 0) {
      amountIn = LibRouter.transferInAndConvert(convertInParams, collateralToken);
    }

    if (borrowParams.positionId > 0) {
      IERC721(borrowParams.pool).transferFrom(msg.sender, address(this), borrowParams.positionId);
    }
    if (amountIn > 0) {
      IERC20(collateralToken).forceApprove(longPoolManager, amountIn);
    }
    borrowParams.positionId = ILongPoolManager(longPoolManager).operate(
      borrowParams.pool,
      borrowParams.positionId,
      int256(amountIn),
      int256(borrowParams.borrowAmount)
    );
    IERC721(borrowParams.pool).transferFrom(address(this), msg.sender, borrowParams.positionId);

    emit Operate(
      borrowParams.pool,
      msg.sender,
      borrowParams.positionId,
      int256(amountIn),
      int256(borrowParams.borrowAmount)
    );

    // transfer borrowed fxUSD to caller
    LibRouter.refundERC20(fxUSD, msg.sender);

    return borrowParams.positionId;
  }

  /// @notice Repay collateral token to long pool with any tokens.
  /// @notice 使用任意代币向多头池还款
  /// @param convertInParams The parameters to convert source token to collateral token.
  /// @param convertInParams 将源代币转换为抵押品代币的参数
  /// @param repayParams The parameters to repay to long pool.
  /// @param repayParams 向多头池还款的参数
  function repayToLong(
    LibRouter.ConvertInParams memory convertInParams,
    RepayToLongParams memory repayParams
  ) external payable nonReentrant {
    // convert and repay to long pool
    // 转换并向多头池还款
    _repayToLong(convertInParams, repayParams);

    // transfer withdrawn collateral token to caller
    // 将提取的抵押品代币转给调用者
    address collateralToken = ILongPool(repayParams.pool).collateralToken();
    LibRouter.refundERC20(collateralToken, msg.sender);

    // transfer extra fxUSD to caller
    // 将多余的fxUSD转给调用者
    LibRouter.refundERC20(fxUSD, msg.sender);
  }

  /// @notice Repay collateral token to long pool with any tokens.
  /// @notice 使用任意代币向多头池还款并提取
  /// @param convertInParams The parameters to convert source token to collateral token.
  /// @param convertInParams 将源代币转换为抵押品代币的参数
  /// @param repayParams The parameters to repay to long pool.
  /// @param repayParams 向多头池还款的参数
  function repayToLongAndZapOut(
    LibRouter.ConvertInParams memory convertInParams,
    RepayToLongParams memory repayParams,
    LibRouter.ConvertOutParams memory convertOutParams
  ) external payable nonReentrant {
    // convert and repay to long pool
    _repayToLong(convertInParams, repayParams);

    // transfer withdrawn collateral token to caller
    address collateralToken = ILongPool(repayParams.pool).collateralToken();
    uint256 amountOut = IERC20(collateralToken).balanceOf(address(this));
    LibRouter.convertAndTransferOut(convertOutParams, collateralToken, amountOut, msg.sender);

    // transfer extra fxUSD to caller
    LibRouter.refundERC20(fxUSD, msg.sender);
  }

  /// @dev Internal function to repay to long pool.
  /// @dev 内部函数：向多头池还款
  /// @param convertInParams The parameters to convert source token to collateral token.
  /// @param convertInParams 将源代币转换为抵押品代币的参数
  /// @param repayParams The parameters to repay to long pool.
  /// @param repayParams 向多头池还款的参数
  function _repayToLong(
    LibRouter.ConvertInParams memory convertInParams,
    RepayToLongParams memory repayParams
  ) internal {
    uint256 amountIn;
    if (convertInParams.amount > 0) {
      amountIn = LibRouter.transferInAndConvert(convertInParams, fxUSD);
    }

    IERC721(repayParams.pool).transferFrom(msg.sender, address(this), repayParams.positionId);
    if (amountIn > 0) {
      IERC20(fxUSD).forceApprove(longPoolManager, amountIn);
    }
    // repay * (1 + repayFeeRatio) <= amountIn
    // repay <= amountIn / (1 + repayFeeRatio)
    (, , , uint256 repayFeeRatio) = IPoolConfiguration(configuration).getPoolFeeRatio(repayParams.pool, address(this));
    uint256 actualRepay = (amountIn * FEE_PRECISION) / (FEE_PRECISION + repayFeeRatio);

    // check whether it is fully repay
    address collateralToken = ILongPool(repayParams.pool).collateralToken();
    int256 deltaColl = -int256(repayParams.withdrawAmount);
    int256 deltaDebts = -int256(actualRepay);
    (uint256 colls, uint256 debts) = ILongPool(repayParams.pool).getPosition(repayParams.positionId);
    uint256 scalingFactor = ILongPoolManager(longPoolManager).getTokenScalingFactor(collateralToken);
    colls = _scaleDown(colls, scalingFactor);
    if (actualRepay >= debts && repayParams.withdrawAmount >= colls) {
      deltaColl = type(int256).min;
      deltaDebts = type(int256).min;
    }
    ILongPoolManager(longPoolManager).operate(repayParams.pool, repayParams.positionId, deltaColl, deltaDebts);
    IERC721(repayParams.pool).transferFrom(address(this), msg.sender, repayParams.positionId);

    // emit event for operate
    if (deltaColl == type(int256).min) {
      deltaColl = -int256(colls);
      deltaDebts = -int256(debts);
    }
    emit Operate(repayParams.pool, msg.sender, repayParams.positionId, deltaColl, deltaDebts);
  }

  /// @dev Internal function to scaler down for `uint256`, rounding down.
  /// @dev 内部函数：对`uint256`进行缩放，向下取整
  function _scaleDown(uint256 value, uint256 scale) internal pure returns (uint256) {
    return (value * PRECISION) / scale;
  }
}
