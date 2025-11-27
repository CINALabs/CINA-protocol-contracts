// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IMultiPathConverter } from "../../helpers/interfaces/IMultiPathConverter.sol";
import { IWrappedEther } from "../../interfaces/IWrappedEther.sol";

/// @title LibRouter
/// @notice 路由器库，提供代币转换、授权管理和存储访问等核心功能
/// @dev 作为Diamond代理模式的共享库，被多个facet使用
library LibRouter {
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  /**********
   * Errors *
   **********/
  /// @dev 错误定义

  /// @dev Thrown when use unapproved target contract.
  /// @dev 当使用未批准的目标合约时抛出
  error ErrorTargetNotApproved();

  /// @dev Thrown when msg.value is different from amount.
  /// @dev 当msg.value与金额不匹配时抛出
  error ErrorMsgValueMismatch();

  /// @dev Thrown when the output token is not enough.
  /// @dev 当输出代币不足时抛出
  error ErrorInsufficientOutput();

  /// @dev Thrown when the whitelisted account type is incorrect.
  /// @dev 当账户不在白名单中时抛出
  error ErrorNotWhitelisted();

  /*************
   * Constants *
   *************/
  /// @dev 常量定义

  /// @dev The storage slot for router storage.
  /// @dev 路由器存储的存储槽
  bytes32 private constant ROUTER_STORAGE_SLOT = keccak256("diamond.router.storage");

  /// @dev The address of WETH token.
  /// @dev WETH代币地址
  address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

  /// @dev 非闪电贷状态标志
  uint8 internal constant NOT_FLASH_LOAN = 0;

  /// @dev 闪电贷状态标志
  uint8 internal constant HAS_FLASH_LOAN = 1;

  /// @dev 非重入状态标志
  uint8 internal constant NOT_ENTRANT = 0;

  /// @dev 重入状态标志
  uint8 internal constant HAS_ENTRANT = 1;

  /***********
   * Structs *
   ***********/
  /// @dev 结构体定义

  /// @notice 路由器存储结构
  /// @param spenders Mapping from target address to token spender address.
  /// @param spenders 从目标地址到代币支出者地址的映射
  /// @param approvedTargets The list of approved target contracts.
  /// @param approvedTargets 已批准的目标合约列表
  /// @param whitelisted The list of whitelisted contracts.
  /// @param whitelisted 白名单合约列表
  /// @param revenuePool 收益池地址
  /// @param flashLoanContext 闪电贷上下文状态
  /// @param reentrantContext 重入上下文状态
  struct RouterStorage {
    mapping(address => address) spenders;
    EnumerableSet.AddressSet approvedTargets;
    EnumerableSet.AddressSet whitelisted;
    address revenuePool;
    uint8 flashLoanContext;
    uint8 reentrantContext;
  }

  /// @notice The struct for input token convert parameters.
  /// @notice 输入代币转换参数结构
  ///
  /// @param tokenIn The address of source token.
  /// @param tokenIn 源代币地址
  /// @param amount The amount of source token.
  /// @param amount 源代币数量
  /// @param target The address of converter contract.
  /// @param target 转换器合约地址
  /// @param data The calldata passing to the target contract.
  /// @param data 传递给目标合约的调用数据
  /// @param minOut The minimum amount of output token should receive.
  /// @param minOut 应收到的最小输出代币数量
  /// @param signature The optional data for future usage.
  /// @param signature 用于未来使用的可选数据
  struct ConvertInParams {
    address tokenIn;
    uint256 amount;
    address target;
    bytes data;
    uint256 minOut;
    bytes signature;
  }

  /// @notice The struct for output token convert parameters.
  /// @notice 输出代币转换参数结构
  /// @param tokenOut The address of output token.
  /// @param tokenOut 输出代币地址
  /// @param converter The address of converter contract.
  /// @param converter 转换器合约地址
  /// @param encodings The encodings for `MultiPathConverter`.
  /// @param encodings `MultiPathConverter`的编码
  /// @param minOut The minimum amount of output token should receive.
  /// @param minOut 应收到的最小输出代币数量
  /// @param routes The convert route encodings.
  /// @param routes 转换路由编码
  /// @param signature The optional data for future usage.
  /// @param signature 用于未来使用的可选数据
  struct ConvertOutParams {
    address tokenOut;
    address converter;
    uint256 encodings;
    uint256[] routes;
    uint256 minOut;
    bytes signature;
  }

  /**********************
   * Internal Functions *
   **********************/
  /// @dev 内部函数

  /// @dev Return the RouterStorage reference.
  /// @dev 返回RouterStorage引用
  function routerStorage() internal pure returns (RouterStorage storage gs) {
    bytes32 position = ROUTER_STORAGE_SLOT;
    assembly {
      gs.slot := position
    }
  }

  /// @dev Approve contract to be used in token converting.
  /// @dev 批准合约用于代币转换
  /// @param target 目标合约地址
  /// @param spender 支出者地址
  function approveTarget(address target, address spender) internal {
    RouterStorage storage $ = routerStorage();

    if ($.approvedTargets.add(target) && target != spender) {
      $.spenders[target] = spender;
    }
  }

  /// @dev Remove approve contract in token converting.
  /// @dev 移除代币转换中的已批准合约
  /// @param target 要移除的目标合约地址
  function removeTarget(address target) internal {
    RouterStorage storage $ = routerStorage();

    if ($.approvedTargets.remove(target)) {
      delete $.spenders[target];
    }
  }

  /// @dev Whitelist account with type.
  /// @dev 更新账户的白名单状态
  /// @param account 账户地址
  /// @param status 白名单状态
  function updateWhitelist(address account, bool status) internal {
    RouterStorage storage $ = routerStorage();

    if (status) {
      $.whitelisted.add(account);
    } else {
      $.whitelisted.remove(account);
    }
  }

  /// @dev Check whether the account is whitelisted with specific type.
  /// @dev 检查账户是否在白名单中
  /// @param account 要检查的账户地址
  function ensureWhitelisted(address account) internal view {
    RouterStorage storage $ = routerStorage();
    if (!$.whitelisted.contains(account)) {
      revert ErrorNotWhitelisted();
    }
  }

  /// @dev 更新收益池地址
  /// @param revenuePool 新的收益池地址
  function updateRevenuePool(address revenuePool) internal {
    RouterStorage storage $ = routerStorage();
    $.revenuePool = revenuePool;
  }

  /// @dev Transfer token into this contract and convert to `tokenOut`.
  ///      将代币转入此合约并转换为`tokenOut`
  /// @param params The parameters used in token converting. 代币转换使用的参数
  /// @param tokenOut The address of final converted token. 最终转换代币的地址
  /// @return amountOut The amount of token received. 收到的代币数量
  function transferInAndConvert(ConvertInParams memory params, address tokenOut) internal returns (uint256 amountOut) {
    RouterStorage storage $ = routerStorage();
    if (!$.approvedTargets.contains(params.target)) {
      revert ErrorTargetNotApproved();
    }

    transferTokenIn(params.tokenIn, address(this), params.amount);

    amountOut = IERC20(tokenOut).balanceOf(address(this));
    if (params.tokenIn == tokenOut) return amountOut;

    bool _success;
    if (params.tokenIn == address(0)) {
      (_success, ) = params.target.call{ value: params.amount }(params.data);
    } else {
      address _spender = $.spenders[params.target];
      if (_spender == address(0)) _spender = params.target;

      approve(params.tokenIn, _spender, params.amount);
      (_success, ) = params.target.call(params.data);
    }

    // below lines will propagate inner error up
    if (!_success) {
      // solhint-disable-next-line no-inline-assembly
      assembly {
        let ptr := mload(0x40)
        let size := returndatasize()
        returndatacopy(ptr, 0, size)
        revert(ptr, size)
      }
    }

    amountOut = IERC20(tokenOut).balanceOf(address(this)) - amountOut;

    if (amountOut < params.minOut) revert ErrorInsufficientOutput();
  }

  /// @dev Convert `tokenIn` to other token and transfer out.
  ///      将`tokenIn`转换为其他代币并转出
  /// @param params The parameters used in token converting. 代币转换使用的参数
  /// @param tokenIn The address of token to convert. 要转换的代币地址
  /// @param amountIn The amount of token to convert. 要转换的代币数量
  /// @param receiver The address of receiver. 接收者地址
  /// @return amountOut The amount of token received. 收到的代币数量
  function convertAndTransferOut(
    ConvertOutParams memory params,
    address tokenIn,
    uint256 amountIn,
    address receiver
  ) internal returns (uint256 amountOut) {
    RouterStorage storage $ = routerStorage();
    if (!$.approvedTargets.contains(params.converter)) {
      revert ErrorTargetNotApproved();
    }
    if (amountIn == 0) return 0;

    amountOut = amountIn;
    if (params.routes.length > 0) {
      approve(tokenIn, params.converter, amountIn);
      amountOut = IMultiPathConverter(params.converter).convert(tokenIn, amountIn, params.encodings, params.routes);
    }
    if (amountOut < params.minOut) revert ErrorInsufficientOutput();
    if (params.tokenOut == address(0)) {
      IWrappedEther(WETH).withdraw(amountOut);
      Address.sendValue(payable(receiver), amountOut);
    } else {
      IERC20(params.tokenOut).safeTransfer(receiver, amountOut);
    }
  }

  /// @dev Internal function to transfer token to this contract.
  ///      内部函数：将代币转入此合约
  /// @param token The address of token to transfer. 要转入的代币地址
  /// @param receiver The address of receiver. 接收者地址
  /// @param amount The amount of token to transfer. 要转入的代币数量
  /// @return The amount of token transferred. 转入的代币数量
  function transferTokenIn(address token, address receiver, uint256 amount) internal returns (uint256) {
    if (token == address(0)) {
      if (msg.value != amount) revert ErrorMsgValueMismatch();
    } else {
      IERC20(token).safeTransferFrom(msg.sender, receiver, amount);
    }
    return amount;
  }

  /// @dev Internal function to refund extra token.
  /// @dev 内部函数：退还多余的代币
  /// @param token The address of token to refund.
  /// @param token 要退还的代币地址
  /// @param recipient The address of the token receiver.
  /// @param recipient 代币接收者地址
  function refundERC20(address token, address recipient) internal {
    uint256 _balance = IERC20(token).balanceOf(address(this));
    if (_balance > 0) {
      IERC20(token).safeTransfer(recipient, _balance);
    }
  }

  /// @dev Internal function to approve token.
  /// @dev 内部函数：授权代币
  /// @param token 代币地址
  /// @param spender 支出者地址
  /// @param amount 授权数量
  function approve(address token, address spender, uint256 amount) internal {
    IERC20(token).forceApprove(spender, amount);
  }
}
