// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import { IMultiPathConverter } from "../helpers/interfaces/IMultiPathConverter.sol";
import { ICurveStableSwapNG } from "../interfaces/Curve/ICurveStableSwapNG.sol";
import { IFxUSDRegeneracy } from "../interfaces/IFxUSDRegeneracy.sol";
import { IPegKeeper } from "../interfaces/IPegKeeper.sol";
import { IFxUSDBasePool } from "../interfaces/IFxUSDBasePool.sol";

/// @title PegKeeper - 锚定维护者合约
/// @notice 负责维护 fxUSD 的价格锚定
/// @dev 通过回购和套利机制来稳定 fxUSD 价格
///
/// ==================== 锚定维护机制 ====================
///
/// 1. 回购 (Buyback)
///    - 当 fxUSD 价格低于锚定时使用
///    - 用稳定币储备购买 fxUSD 并销毁
///    - 减少 fxUSD 供应，推高价格
///
/// 2. 套利 (Stabilize)
///    - 在 FxUSDBasePool 中进行套利
///    - 当 fxUSD 价格偏离时，通过交换获利
///    - 套利者获得利润，同时帮助稳定价格
///
/// 工作流程:
/// 1. 检测 fxUSD 价格偏离
/// 2. 授权的角色调用 buyback 或 stabilize
/// 3. 通过 MultiPathConverter 执行交换
/// 4. 价格回归锚定
///
contract PegKeeper is AccessControlUpgradeable, IPegKeeper {
  using SafeERC20 for IERC20;

  /**********
   * 错误定义 *
   **********/

  /// @dev 当不在回调上下文中时抛出
  error ErrorNotInCallbackContext();

  /// @dev 当地址为零地址时抛出
  error ErrorZeroAddress();

  /// @dev 当输出不足时抛出
  error ErrorInsufficientOutput();

  /*************
   * 常量定义 *
   *************/

  /// @dev 计算精度 (1e18)
  uint256 private constant PRECISION = 1e18;

  /// @notice 回购角色标识符
  /// @dev 拥有此角色的地址可以执行回购操作
  bytes32 public constant BUYBACK_ROLE = keccak256("BUYBACK_ROLE");

  /// @notice 稳定角色标识符
  /// @dev 拥有此角色的地址可以执行套利操作
  bytes32 public constant STABILIZE_ROLE = keccak256("STABILIZE_ROLE");

  /// @dev 回调上下文常量 - 无上下文
  uint8 private constant CONTEXT_NO_CONTEXT = 1;
  /// @dev 回调上下文常量 - 回购
  uint8 private constant CONTEXT_BUYBACK = 2;
  /// @dev 回调上下文常量 - 套利
  uint8 private constant CONTEXT_STABILIZE = 3;

  /***********************
   * 不可变变量 *
   ***********************/

  /// @notice fxUSD 代币地址
  address public immutable fxUSD;

  /// @notice 稳定币地址（USDC）
  address public immutable stable;

  /// @notice FxUSDBasePool 合约地址
  address public immutable fxBASE;

  /*********************
   * 存储变量 *
   *********************/

  /// @dev 回调上下文
  /// @notice 用于验证回调的有效性
  uint8 private context;

  /// @notice MultiPathConverter 合约地址
  /// @dev 用于执行代币交换
  address public converter;

  /// @notice Curve 池地址（fxUSD/USDC 交易对）
  /// @dev 用于获取 fxUSD 的 EMA 价格
  address public curvePool;

  /// @notice fxUSD 脱锚价格阈值
  /// @dev 当价格低于此阈值时，认为 fxUSD 脱锚
  uint256 public priceThreshold;

  /*************
   * 修饰符 *
   *************/

  /// @dev 设置回调上下文
  /// @notice 在函数执行前设置上下文，执行后重置
  modifier setContext(uint8 c) {
    context = c;
    _;
    context = CONTEXT_NO_CONTEXT;
  }

  /***************
   * 构造函数 *
   ***************/

  /// @notice 构造函数
  /// @param _fxBASE FxUSDBasePool 合约地址
  constructor(address _fxBASE) {
    fxBASE = _fxBASE;
    fxUSD = IFxUSDBasePool(_fxBASE).yieldToken();
    stable = IFxUSDBasePool(_fxBASE).stableToken();
  }

  /// @notice 初始化函数（代理模式）
  /// @param admin 管理员地址
  /// @param _converter MultiPathConverter 合约地址
  /// @param _curvePool Curve 池地址
  function initialize(address admin, address _converter, address _curvePool) external initializer {
    __Context_init();
    __ERC165_init();
    __AccessControl_init();

    _grantRole(DEFAULT_ADMIN_ROLE, admin);

    _updateConverter(_converter);
    _updateCurvePool(_curvePool);
    _updatePriceThreshold(995000000000000000); // 0.995 = 99.5%

    context = CONTEXT_NO_CONTEXT;
  }

  /*************************
   * 公共视图函数 *
   *************************/

  /// @inheritdoc IPegKeeper
  /// @notice 检查是否允许借款
  /// @return 如果 fxUSD 价格 >= 阈值返回 true
  function isBorrowAllowed() external view returns (bool) {
    return _getFxUSDEmaPrice() >= priceThreshold;
  }

  /// @inheritdoc IPegKeeper
  /// @notice 检查是否启用资金费率
  /// @return 如果 fxUSD 价格 < 阈值返回 true（脱锚时启用）
  function isFundingEnabled() external view returns (bool) {
    return _getFxUSDEmaPrice() < priceThreshold;
  }

  /// @inheritdoc IPegKeeper
  /// @notice 检查是否允许赎回
  /// @return 如果 fxUSD 价格 < 阈值返回 true（脱锚时允许）
  function isRedeemAllowed() external view returns (bool) {
    return _getFxUSDEmaPrice() < priceThreshold;
  }

  /// @inheritdoc IPegKeeper
  /// @notice 获取 fxUSD 价格
  /// @return fxUSD 的 EMA 价格（×1e18）
  function getFxUSDPrice() external view returns (uint256) {
    return _getFxUSDEmaPrice();
  }

  /****************************
   * 公共状态修改函数 *
   ****************************/

  /// @inheritdoc IPegKeeper
  /// @notice 执行回购操作
  /// @dev 用稳定币储备购买 fxUSD 并销毁
  /// @param amountIn 输入的稳定币数量
  /// @param data 交换路径数据
  /// @return amountOut 购买的 fxUSD 数量
  /// @return bonus 额外奖励
  function buyback(
    uint256 amountIn,
    bytes calldata data
  ) external onlyRole(BUYBACK_ROLE) setContext(CONTEXT_BUYBACK) returns (uint256 amountOut, uint256 bonus) {
    (amountOut, bonus) = IFxUSDRegeneracy(fxUSD).buyback(amountIn, _msgSender(), data);
  }

  /// @inheritdoc IPegKeeper
  /// @notice 执行套利操作
  /// @dev 在 FxUSDBasePool 中进行套利
  /// @param srcToken 源代币地址
  /// @param amountIn 输入数量
  /// @param data 交换路径数据
  /// @return amountOut 输出数量
  /// @return bonus 套利利润
  function stabilize(
    address srcToken,
    uint256 amountIn,
    bytes calldata data
  ) external onlyRole(STABILIZE_ROLE) setContext(CONTEXT_STABILIZE) returns (uint256 amountOut, uint256 bonus) {
    (amountOut, bonus) = IFxUSDBasePool(fxBASE).arbitrage(srcToken, amountIn, _msgSender(), data);
  }

  /// @inheritdoc IPegKeeper
  /// @notice 交换回调函数
  /// @dev 在 buyback 和 stabilize 中被调用
  /// @param srcToken 源代币地址
  /// @param targetToken 目标代币地址
  /// @param amountIn 输入数量
  /// @param data 交换路径数据
  /// @return amountOut 输出数量
  function onSwap(
    address srcToken,
    address targetToken,
    uint256 amountIn,
    bytes calldata data
  ) external returns (uint256 amountOut) {
    // 检查回调有效性
    if (context == CONTEXT_NO_CONTEXT) revert ErrorNotInCallbackContext();

    amountOut = _doSwap(srcToken, amountIn, data);
    IERC20(targetToken).safeTransfer(_msgSender(), amountOut);
  }

  /************************
   * 管理函数 *
   ************************/

  /// @notice 更新 MultiPathConverter 地址
  /// @param newConverter 新的 Converter 地址
  function updateConverter(address newConverter) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateConverter(newConverter);
  }

  /// @notice 更新 Curve 池地址
  /// @param newPool 新的 Curve 池地址
  function updateCurvePool(address newPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateCurvePool(newPool);
  }

  /// @notice 更新脱锚价格阈值
  /// @param newThreshold 新的价格阈值
  function updatePriceThreshold(uint256 newThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updatePriceThreshold(newThreshold);
  }

  /**********************
   * 内部函数 *
   **********************/

  /// @dev 更新 MultiPathConverter 地址
  /// @param newConverter 新的 Converter 地址
  function _updateConverter(address newConverter) internal {
    if (newConverter == address(0)) revert ErrorZeroAddress();

    address oldConverter = converter;
    converter = newConverter;

    emit UpdateConverter(oldConverter, newConverter);
  }

  /// @dev 更新 Curve 池地址
  /// @param newPool 新的 Curve 池地址
  function _updateCurvePool(address newPool) internal {
    if (newPool == address(0)) revert ErrorZeroAddress();

    address oldPool = curvePool;
    curvePool = newPool;

    emit UpdateCurvePool(oldPool, newPool);
  }

  /// @dev 更新脱锚价格阈值
  /// @param newThreshold 新的价格阈值
  function _updatePriceThreshold(uint256 newThreshold) internal {
    uint256 oldThreshold = priceThreshold;
    priceThreshold = newThreshold;

    emit UpdatePriceThreshold(oldThreshold, newThreshold);
  }

  /// @dev 执行代币交换
  /// @param srcToken 源代币地址
  /// @param amountIn 输入数量
  /// @param data 交换路径数据（包含 minOut、encoding、routes）
  /// @return amountOut 输出数量
  function _doSwap(address srcToken, uint256 amountIn, bytes calldata data) internal returns (uint256 amountOut) {
    IERC20(srcToken).forceApprove(converter, amountIn);

    (uint256 minOut, uint256 encoding, uint256[] memory routes) = abi.decode(data, (uint256, uint256, uint256[]));
    amountOut = IMultiPathConverter(converter).convert(srcToken, amountIn, encoding, routes);
    if (amountOut < minOut) revert ErrorInsufficientOutput();
  }

  /// @dev 获取 fxUSD 的 EMA 价格
  /// @return price EMA 价格（×1e18）
  function _getFxUSDEmaPrice() internal view returns (uint256 price) {
    address cachedCurvePool = curvePool; // 节省 gas
    address firstCoin = ICurveStableSwapNG(cachedCurvePool).coins(0);
    price = ICurveStableSwapNG(cachedCurvePool).price_oracle(0);
    // 如果 fxUSD 是第一个代币，需要取倒数
    if (firstCoin == fxUSD) {
      price = (PRECISION * PRECISION) / price;
    }
  }
}
