// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { IFxUSDBasePool } from "../../interfaces/IFxUSDBasePool.sol";
import { ISavingFxUSD } from "../../interfaces/ISavingFxUSD.sol";
import { IFxShareableRebalancePool } from "../../v2/interfaces/IFxShareableRebalancePool.sol";
import { IFxUSD } from "../../v2/interfaces/IFxUSD.sol";
import { ILiquidityGauge } from "../../voting-escrow/interfaces/ILiquidityGauge.sol";

import { WordCodec } from "../../common/codec/WordCodec.sol";
import { LibRouter } from "../libraries/LibRouter.sol";

/// @title SavingFxUSDFacet
/// @notice fxUSD储蓄门面合约，提供存款到fxSAVE和从fxSAVE赎回的功能
/// @dev 作为Diamond代理模式的一个facet，处理fxUSD储蓄相关操作
contract SavingFxUSDFacet {
  using SafeERC20 for IERC20;

  /*************
   * Constants *
   *************/
  /// @dev 常量定义

  /// @notice The role for no instantly redeem fee.
  /// @notice 免即时赎回费用的角色
  bytes32 public constant NO_INSTANT_REDEEM_FEE_ROLE = keccak256("NO_INSTANT_REDEEM_FEE_ROLE");

  /// @notice The address of USDC token.
  /// @notice USDC代币地址
  address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

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

  /// @dev The address of `SavingFxUSD` contract.
  /// @dev fxUSD储蓄合约地址
  address private immutable fxSAVE;

  /***************
   * Constructor *
   ***************/
  /// @dev 构造函数

  constructor(address _fxBASE, address _fxSAVE) {
    fxBASE = _fxBASE;
    fxSAVE = _fxSAVE;
  }

  /****************************
   * Public Mutated Functions *
   ****************************/
  /// @dev 公共状态修改函数

  /// @notice Deposit token to fxSAVE.
  /// @notice 存款代币到fxSAVE
  /// @param params The parameters to convert source token to `tokenOut`.
  /// @param params 将源代币转换为`tokenOut`的参数
  /// @param tokenOut The target token, USDC or fxUSD.
  /// @param tokenOut 目标代币，USDC或fxUSD
  /// @param minShares The minimum shares should receive.
  /// @param minShares 应收到的最小份额数量
  /// @param receiver The address of fxSAVE share recipient.
  /// @param receiver fxSAVE份额接收者地址
  function depositToFxSave(
    LibRouter.ConvertInParams memory params,
    address tokenOut,
    uint256 minShares,
    address receiver
  ) external payable {
    uint256 amountIn = LibRouter.transferInAndConvert(params, tokenOut);
    LibRouter.approve(tokenOut, fxBASE, amountIn);
    uint256 shares = IFxUSDBasePool(fxBASE).deposit(address(this), tokenOut, amountIn, minShares);
    LibRouter.approve(fxBASE, fxSAVE, shares);
    IERC4626(fxSAVE).deposit(shares, receiver);
  }

  /// @notice Burn fxSave shares and then convert USDC and fxUSD to another token.
  /// @notice 销毁fxSave份额然后将USDC和fxUSD转换为其他代币
  /// @param fxusdParams The parameters to convert fxUSD to target token.
  /// @param fxusdParams 将fxUSD转换为目标代币的参数
  /// @param usdcParams The parameters to convert USDC to target token.
  /// @param usdcParams 将USDC转换为目标代币的参数
  /// @param receiver The address of token recipient.
  /// @param receiver 代币接收者地址
  function redeemFromFxSave(
    LibRouter.ConvertOutParams memory fxusdParams,
    LibRouter.ConvertOutParams memory usdcParams,
    address receiver
  ) external {
    ISavingFxUSD(fxSAVE).claimFor(msg.sender, address(this));
    uint256 amountFxUSD = IERC20(fxUSD).balanceOf(address(this));
    uint256 amountUSDC = IERC20(USDC).balanceOf(address(this));
    LibRouter.convertAndTransferOut(fxusdParams, fxUSD, amountFxUSD, receiver);
    LibRouter.convertAndTransferOut(usdcParams, USDC, amountUSDC, receiver);
  }

  /// @notice Burn fxSave shares and then convert USDC and fxUSD to another token instantly.
  /// @notice 即时销毁fxSave份额然后将USDC和fxUSD转换为其他代币
  /// @param fxusdParams The parameters to convert fxUSD to target token.
  /// @param fxusdParams 将fxUSD转换为目标代币的参数
  /// @param usdcParams The parameters to convert USDC to target token.
  /// @param usdcParams 将USDC转换为目标代币的参数
  /// @param shares 要赎回的份额数量
  /// @param receiver The address of token recipient.
  /// @param receiver 代币接收者地址
  function instantRedeemFromFxSave(
    LibRouter.ConvertOutParams memory fxusdParams,
    LibRouter.ConvertOutParams memory usdcParams,
    uint256 shares,
    address receiver
  ) external {
    uint256 assets = IERC4626(fxSAVE).redeem(shares, address(this), msg.sender);
    uint256 amountFxUSD;
    uint256 amountUSDC;
    if (IAccessControl(fxBASE).hasRole(NO_INSTANT_REDEEM_FEE_ROLE, msg.sender)) {
      (amountFxUSD, amountUSDC) = IFxUSDBasePool(fxBASE).instantRedeemNoFee(address(this), assets);
    } else {
      (amountFxUSD, amountUSDC) = IFxUSDBasePool(fxBASE).instantRedeem(address(this), assets);
    }
    LibRouter.convertAndTransferOut(fxusdParams, fxUSD, amountFxUSD, receiver);
    LibRouter.convertAndTransferOut(usdcParams, USDC, amountUSDC, receiver);
  }
}
