// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IFxUSDBasePool } from "../../interfaces/IFxUSDBasePool.sol";
import { IFxShareableRebalancePool } from "../../v2/interfaces/IFxShareableRebalancePool.sol";
import { IFxUSD } from "../../v2/interfaces/IFxUSD.sol";
import { ILiquidityGauge } from "../../voting-escrow/interfaces/ILiquidityGauge.sol";

import { WordCodec } from "../../common/codec/WordCodec.sol";
import { LibRouter } from "../libraries/LibRouter.sol";

/// @title FxUSDBasePoolV2Facet
/// @notice FxUSD基础池V2门面合约，提供增强的迁移和存款功能，支持动态指定gauge
/// @dev 作为Diamond代理模式的一个facet，是FxUSDBasePoolFacet的升级版本
contract FxUSDBasePoolV2Facet {
  using SafeERC20 for IERC20;

  /*************
   * Constants *
   *************/
  /// @dev 常量定义

  /// @notice The address of fxUSD token.
  /// @notice fxUSD代币地址
  address private constant fxUSD = 0x085780639CC2cACd35E474e71f4d000e2405d8f6;

  /***********************
   * Immutable Variables *
   ***********************/
  /// @dev 不可变变量

  /// @dev The address of `FxUSDBasePool` contract.
  /// @dev FxUSD基础池合约地址
  address private immutable fxBASE;

  /***************
   * Constructor *
   ***************/
  /// @dev 构造函数

  constructor(address _fxBASE) {
    fxBASE = _fxBASE;
  }

  /****************************
   * Public Mutated Functions *
   ****************************/
  /// @dev 公共状态修改函数

  /// @notice Migrate fxUSD from rebalance pool to fxBASE gauge.
  /// @notice 将fxUSD从再平衡池迁移到fxBASE流动性挖矿计量器
  /// @param pool The address of rebalance pool.
  /// @param pool 再平衡池地址
  /// @param gauge 流动性挖矿计量器地址
  /// @param amountIn The amount of rebalance pool shares to migrate.
  /// @param amountIn 要迁移的再平衡池份额数量
  /// @param minShares The minimum shares should receive.
  /// @param minShares 应收到的最小份额数量
  /// @param receiver The address of fxBASE share recipient.
  /// @param receiver fxBASE份额接收者地址
  function migrateToFxBaseGaugeV2(address pool, address gauge, uint256 amountIn, uint256 minShares, address receiver) external {
    LibRouter.ensureWhitelisted(gauge);
    IFxShareableRebalancePool(pool).withdrawFrom(msg.sender, amountIn, address(this));
    address baseToken = IFxShareableRebalancePool(pool).baseToken();
    address asset = IFxShareableRebalancePool(pool).asset();
    LibRouter.approve(asset, fxUSD, amountIn);
    IFxUSD(fxUSD).wrap(baseToken, amountIn, address(this));
    LibRouter.approve(fxUSD, fxBASE, amountIn);
    uint256 shares = IFxUSDBasePool(fxBASE).deposit(address(this), fxUSD, amountIn, minShares);
    LibRouter.approve(fxBASE, gauge, shares);
    ILiquidityGauge(gauge).deposit(shares, receiver);
  }

  /// @notice Deposit token to fxBase and then deposit to gauge.
  /// @notice 存款代币到fxBase然后存入流动性挖矿计量器
  /// @param params The parameters to convert source token to `tokenOut`.
  /// @param params 将源代币转换为`tokenOut`的参数
  /// @param gauge 流动性挖矿计量器地址
  /// @param tokenOut The target token, USDC or fxUSD.
  /// @param tokenOut 目标代币，USDC或fxUSD
  /// @param minShares The minimum shares should receive.
  /// @param minShares 应收到的最小份额数量
  /// @param receiver The address of gauge share recipient.
  /// @param receiver 流动性挖矿计量器份额接收者地址
  function depositToFxBaseGaugeV2(
    LibRouter.ConvertInParams memory params,
    address gauge,
    address tokenOut,
    uint256 minShares,
    address receiver
  ) external payable {
    LibRouter.ensureWhitelisted(gauge);
    uint256 amountIn = LibRouter.transferInAndConvert(params, tokenOut);
    LibRouter.approve(tokenOut, fxBASE, amountIn);
    uint256 shares = IFxUSDBasePool(fxBASE).deposit(address(this), tokenOut, amountIn, minShares);
    LibRouter.approve(fxBASE, gauge, shares);
    ILiquidityGauge(gauge).deposit(shares, receiver);
  }
}
