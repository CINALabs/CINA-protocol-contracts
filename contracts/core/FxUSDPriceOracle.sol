// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import { AggregatorV3Interface } from "../interfaces/Chainlink/AggregatorV3Interface.sol";
import { ICurveStableSwapNG } from "../interfaces/Curve/ICurveStableSwapNG.sol";
import { IFxUSDPriceOracle } from "../interfaces/IFxUSDPriceOracle.sol";

/// @title FxUSDPriceOracle - fxUSD 价格预言机合约
/// @notice 提供 fxUSD 的价格信息和脱锚检测
/// @dev 使用 Curve 池的 EMA 价格和 Chainlink 的 USDC/USD 价格
///
/// ==================== 价格预言机概述 ====================
///
/// 价格来源:
/// 1. Curve 池的 EMA 价格 - fxUSD/USDC 的指数移动平均价格
/// 2. Chainlink USDC/USD - USDC 相对于 USD 的价格
///
/// 最终价格 = Curve EMA 价格 × USDC/USD 价格
///
/// 脱锚检测:
/// - 下脱锚: 价格 < 1 - maxDePegPriceDeviation
/// - 上脱锚: 价格 > 1 + maxUpPegPriceDeviation
///
/// 脱锚时的行为:
/// - 下脱锚时: 禁止借款，允许赎回，启用资金费率
/// - 上脱锚时: 允许使用稳定币还款
///
contract FxUSDPriceOracle is AccessControlUpgradeable, IFxUSDPriceOracle {
  /**********
   * 错误定义 *
   **********/

  /// @dev 当地址为零地址时抛出
  error ErrorZeroAddress();

  /*************
   * 常量定义 *
   *************/

  /// @dev 计算精度 (1e18)
  uint256 private constant PRECISION = 1e18;

  /***********************
   * 不可变变量 *
   ***********************/

  /// @notice fxUSD 代币地址
  address public immutable fxUSD;

  /// @notice Chainlink USDC/USD 价格源
  /// @dev 编码格式:
  /// ```text
  /// |  32 bits  | 64 bits |  160 bits  |
  /// | heartbeat |  scale  | price_feed |
  /// |low                          high |
  /// ```
  /// - heartbeat: 价格过期时间（秒）
  /// - scale: 价格缩放因子
  /// - price_feed: Chainlink 聚合器地址
  bytes32 public immutable Chainlink_USDC_USD_Spot;

  /*********************
   * 存储变量 *
   *********************/

  /// @notice Curve 池地址（fxUSD/USDC 交易对）
  /// @dev 用于获取 fxUSD 的 EMA 价格
  address public curvePool;

  /// @notice 下脱锚价格偏差阈值
  /// @dev 当价格 < 1 - maxDePegPriceDeviation 时，认为下脱锚
  uint256 public maxDePegPriceDeviation;

  /// @notice 上脱锚价格偏差阈值
  /// @dev 当价格 > 1 + maxUpPegPriceDeviation 时，认为上脱锚
  uint256 public maxUpPegPriceDeviation;

  /***************
   * 构造函数 *
   ***************/

  /// @notice 构造函数
  /// @param _fxUSD fxUSD 代币地址
  /// @param _Chainlink_USDC_USD_Spot Chainlink USDC/USD 价格源编码
  constructor(address _fxUSD, bytes32 _Chainlink_USDC_USD_Spot) {
    fxUSD = _fxUSD;
    Chainlink_USDC_USD_Spot = _Chainlink_USDC_USD_Spot;
  }

  /// @notice 初始化函数（代理模式）
  /// @param admin 管理员地址
  /// @param _curvePool Curve 池地址
  function initialize(address admin, address _curvePool) external initializer {
    __Context_init();
    __AccessControl_init();
    __ERC165_init();

    _grantRole(DEFAULT_ADMIN_ROLE, admin);

    _updateCurvePool(_curvePool);
  }

  /*************************
   * 公共视图函数 *
   *************************/

  /// @inheritdoc IFxUSDPriceOracle
  /// @notice 获取 USDC/USD 价格
  /// @return USDC 价格（×1e18）
  function getUSDCPrice() external view returns (uint256) {
    return _readUSDCPriceByChainlink();
  }

  /// @inheritdoc IFxUSDPriceOracle
  /// @notice 获取 fxUSD 价格和锚定状态
  /// @return isPegged 是否锚定
  /// @return price fxUSD 价格（×1e18）
  function getPrice() external view returns (bool isPegged, uint256 price) {
    price = _getFxUSDEmaPrice();
    // 锚定条件: 1 - maxDePegDeviation <= price <= 1 + maxUpPegDeviation
    isPegged = price >= PRECISION - maxDePegPriceDeviation && price <= PRECISION + maxUpPegPriceDeviation;
  }

  /// @inheritdoc IFxUSDPriceOracle
  /// @notice 检查价格是否高于上脱锚阈值
  /// @return 如果价格 > 1 + maxUpPegDeviation 返回 true
  function isPriceAboveMaxDeviation() external view returns (bool) {
    return _getFxUSDEmaPrice() > PRECISION + maxUpPegPriceDeviation;
  }

  /// @inheritdoc IFxUSDPriceOracle
  /// @notice 检查价格是否低于下脱锚阈值
  /// @return 如果价格 < 1 - maxDePegDeviation 返回 true
  function isPriceBelowMaxDeviation() external view returns (bool) {
    return _getFxUSDEmaPrice() < PRECISION - maxDePegPriceDeviation;
  }

  /************************
   * 管理函数 *
   ************************/

  /// @notice 更新 Curve 池地址
  /// @param newPool 新的 Curve 池地址
  function updateCurvePool(address newPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateCurvePool(newPool);
  }

  /// @notice 更新价格偏差阈值
  /// @param newDePegDeviation 新的下脱锚偏差阈值
  /// @param newUpPegDeviation 新的上脱锚偏差阈值
  function updateMaxPriceDeviation(
    uint256 newDePegDeviation,
    uint256 newUpPegDeviation
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateMaxPriceDeviation(newDePegDeviation, newUpPegDeviation);
  }

  /**********************
   * 内部函数 *
   **********************/

  /// @dev 获取 fxUSD 的 EMA 价格
  /// @return price EMA 价格（×1e18）
  ///
  /// 计算步骤:
  /// 1. 从 Curve 池获取 EMA 价格（fxUSD/USDC）
  /// 2. 如果 fxUSD 是池中的第一个代币，需要取倒数
  /// 3. 乘以 USDC/USD 价格，得到 fxUSD/USD 价格
  function _getFxUSDEmaPrice() internal view returns (uint256 price) {
    address cachedCurvePool = curvePool; // 节省 gas
    address firstCoin = ICurveStableSwapNG(cachedCurvePool).coins(0);
    price = ICurveStableSwapNG(cachedCurvePool).price_oracle(0);
    
    // 如果 fxUSD 是第一个代币，价格是 USDC/fxUSD，需要取倒数
    if (firstCoin == fxUSD) {
      price = (PRECISION * PRECISION) / price;
    }

    // 价格是以 USDC 计价的，需要转换为 USD
    price = (_readUSDCPriceByChainlink() * price) / PRECISION;
  }

  /// @dev 更新 Curve 池地址
  /// @param newPool 新的 Curve 池地址
  function _updateCurvePool(address newPool) internal {
    if (newPool == address(0)) revert ErrorZeroAddress();

    address oldPool = curvePool;
    curvePool = newPool;

    emit UpdateCurvePool(oldPool, newPool);
  }

  /// @dev 更新价格偏差阈值
  /// @param newDePegDeviation 新的下脱锚偏差阈值
  /// @param newUpPegDeviation 新的上脱锚偏差阈值
  function _updateMaxPriceDeviation(uint256 newDePegDeviation, uint256 newUpPegDeviation) internal {
    uint256 oldDePegDeviation = maxDePegPriceDeviation;
    uint256 oldUpPegDeviation = maxUpPegPriceDeviation;
    maxDePegPriceDeviation = newDePegDeviation;
    maxUpPegPriceDeviation = newUpPegDeviation;

    emit UpdateMaxPriceDeviation(oldDePegDeviation, oldUpPegDeviation, newDePegDeviation, newUpPegDeviation);
  }

  /// @dev 从 Chainlink 读取 USDC/USD 价格
  /// @return USDC 价格（×1e18）
  ///
  /// 解码 Chainlink_USDC_USD_Spot:
  /// - 高 160 位: 聚合器地址
  /// - 中 64 位: 缩放因子
  /// - 低 32 位: 心跳时间（过期阈值）
  function _readUSDCPriceByChainlink() internal view returns (uint256) {
    bytes32 encoding = Chainlink_USDC_USD_Spot;
    address aggregator;
    uint256 scale;
    uint256 heartbeat;
    assembly {
      aggregator := shr(96, encoding)
      scale := and(shr(32, encoding), 0xffffffffffffffff)
      heartbeat := and(encoding, 0xffffffff)
    }
    (, int256 answer, , uint256 updatedAt, ) = AggregatorV3Interface(aggregator).latestRoundData();
    if (answer < 0) revert("invalid");
    if (block.timestamp - updatedAt > heartbeat) revert("expired");
    return uint256(answer) * scale;
  }
}
