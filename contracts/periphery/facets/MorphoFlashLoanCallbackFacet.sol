// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IMorphoFlashLoanCallback } from "../../interfaces/Morpho/IMorphoFlashLoanCallback.sol";

import { LibRouter } from "../libraries/LibRouter.sol";

/// @title MorphoFlashLoanCallbackFacet
/// @notice Morpho闪电贷回调门面合约，处理来自Morpho Blue的闪电贷回调
/// @dev 实现IMorphoFlashLoanCallback接口，作为Diamond代理模式的一个facet
contract MorphoFlashLoanCallbackFacet is IMorphoFlashLoanCallback {
  using SafeERC20 for IERC20;

  /**********
   * Errors *
   **********/
  /// @dev 错误定义

  /// @dev Thrown when the caller is not morpho.
  /// @dev 当调用者不是Morpho时抛出
  error ErrorNotFromMorpho();

  /// @dev 当调用不是来自路由器闪电贷时抛出
  error ErrorNotFromRouterFlashLoan();

  /***********************
   * Immutable Variables *
   ***********************/
  /// @dev 不可变变量

  /// @dev The address of Morpho Blue contract.
  /// @dev Morpho Blue合约地址
  /// In ethereum, it is 0xbbbbbbbbbb9cc5e90e3b3af64bdaf62c37eeffcb.
  /// 在以太坊主网上，地址为0xbbbbbbbbbb9cc5e90e3b3af64bdaf62c37eeffcb
  address private immutable morpho;

  /***************
   * Constructor *
   ***************/
  /// @dev 构造函数

  constructor(address _morpho) {
    morpho = _morpho;
  }

  /****************************
   * Public Mutated Functions *
   ****************************/
  /// @dev 公共状态修改函数

  /// @inheritdoc IMorphoFlashLoanCallback
  /// @notice Morpho闪电贷回调函数，在闪电贷执行后被Morpho调用
  /// @param assets 借入的资产数量
  /// @param data 编码的回调数据，包含代币地址和实际调用数据
  function onMorphoFlashLoan(uint256 assets, bytes calldata data) external {
    if (msg.sender != morpho) revert ErrorNotFromMorpho();

    // make sure call invoked by router
    LibRouter.RouterStorage storage $ = LibRouter.routerStorage();
    if ($.flashLoanContext != LibRouter.HAS_FLASH_LOAN) revert ErrorNotFromRouterFlashLoan();

    (address token, bytes memory realData) = abi.decode(data, (address, bytes));
    (bool success, ) = address(this).call(realData);
    // below lines will propagate inner error up
    if (!success) {
      // solhint-disable-next-line no-inline-assembly
      assembly {
        let ptr := mload(0x40)
        let size := returndatasize()
        returndatacopy(ptr, 0, size)
        revert(ptr, size)
      }
    }

    // flashloan fee is zero in Morpho
    LibRouter.approve(token, msg.sender, assets);
  }
}
