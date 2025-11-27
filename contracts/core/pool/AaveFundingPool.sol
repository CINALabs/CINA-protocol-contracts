// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { IPoolConfiguration } from "../../interfaces/IPoolConfiguration.sol";

import { Math } from "../../libraries/Math.sol";
import { BasePool } from "./BasePool.sol";

/**
 * @title AaveFundingPool
 * @author fxUSD Protocol Team
 * @notice fxUSD 稳定币系统的核心借贷池合约
 *
 * ╔══════════════════════════════════════════════════════════════════════════════╗
 * ║                           合约功能概述                                        ║
 * ╠══════════════════════════════════════════════════════════════════════════════╣
 * ║ 1. 允许用户存入抵押品（如 ETH、wstETH 等）                                      ║
 * ║ 2. 允许用户借出 fxUSD 稳定币                                                   ║
 * ║ 3. 通过资金费率机制从抵押品中扣除费用                                           ║
 * ║ 4. 支持赎回、再平衡、清算机制维护系统稳定性                                      ║
 * ╚══════════════════════════════════════════════════════════════════════════════╝
 *
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │                           继承关系                                           │
 * ├─────────────────────────────────────────────────────────────────────────────┤
 * │ AaveFundingPool                                                              │
 * │    └── BasePool (核心业务逻辑: operate/redeem/rebalance/liquidate)           │
 * │        ├── TickLogic (Tick 管理: 仓位分组、树形结构、清算追踪)                  │
 * │        │   └── PoolStorage (存储层: 状态变量、索引、份额)                       │
 * │        │       ├── ERC721Upgradeable (仓位 NFT 表示)                          │
 * │        │       ├── AccessControlUpgradeable (权限控制)                        │
 * │        │       ├── PoolConstant (常量定义)                                    │
 * │        │       └── PoolErrors (错误定义)                                      │
 * │        └── PositionLogic (仓位管理: 创建、更新、查询)                           │
 * │            └── TickLogic                                                     │
 * └─────────────────────────────────────────────────────────────────────────────┘
 *
 * ┌─────────────────────────────────────────────────────────────────────────────┐
 * │                        资金费率更新机制                                       │
 * ├─────────────────────────────────────────────────────────────────────────────┤
 * │                                                                              │
 * │  时间流逝 (duration = block.timestamp - lastTimestamp)                       │
 * │      │                                                                       │
 * │      ▼                                                                       │
 * │  获取资金费率 fundingRatio = IPoolConfiguration.getLongPoolFundingRatio()    │
 * │      │                                                                       │
 * │      ▼                                                                       │
 * │  计算资金费用 funding = totalRawColls * fundingRatio * duration              │
 * │                        / (PRECISION * 365 days)                              │
 * │      │                                                                       │
 * │      ▼                                                                       │
 * │  更新抵押品索引 newCollIndex = collIndex * totalRawColls                      │
 * │                              / (totalRawColls - funding)                     │
 * │      │                                                                       │
 * │      ▼                                                                       │
 * │  触发 checkpoint 和更新时间戳                                                 │
 * │                                                                              │
 * │  【效果】: collIndex 增加 → 相同份额对应更少原始抵押品 → 实现费用扣除           │
 * │                                                                              │
 * └─────────────────────────────────────────────────────────────────────────────┘
 */
contract AaveFundingPool is BasePool {

  /*╔══════════════════════════════════════════════════════════════════════════════╗
    ║                              错误定义                                         ║
    ╚══════════════════════════════════════════════════════════════════════════════╝*/

  /// @dev 当尝试减少的抵押品数量超过总抵押品时抛出
  /// @notice 用于 reduceCollateral() 函数的边界检查
  error ErrorReduceTooMuchCollateral();

  /*╔══════════════════════════════════════════════════════════════════════════════╗
    ║                              结构体定义                                       ║
    ╚══════════════════════════════════════════════════════════════════════════════╝*/

  /**
   * @dev AAVE 借款利率快照结构体
   * @notice 用于追踪资金费率计算的时间基准
   *
   * ┌─────────────────────────────────────────────────────────────────────────────┐
   * │ 字段布局 (256 bits total)                                                   │
   * ├─────────────────────────────────────────────────────────────────────────────┤
   * │ borrowIndex (128 bits)     - [已弃用] AAVE 借款索引，乘以 1e27              │
   * │ lastInterestRate (80 bits) - [已弃用] 上次记录的利率，乘以 1e18             │
   * │ timestamp (48 bits)        - 快照时间戳，用于计算时间间隔                    │
   * └─────────────────────────────────────────────────────────────────────────────┘
   */
  struct BorrowRateSnapshot {
    // borrowIndex 初始值为 10^27，不太可能超过 2^128
    uint128 borrowIndex;
    uint80 lastInterestRate;
    uint48 timestamp;
  }

  /*╔══════════════════════════════════════════════════════════════════════════════╗
    ║                              存储变量                                         ║
    ╚══════════════════════════════════════════════════════════════════════════════╝*/

  /**
   * @dev [已弃用] 资金杂项数据存储槽
   * @notice 此存储槽已不再使用，保留以维护存储布局兼容性
   *
   * ┌─────────────────────────────────────────────────────────────────────────────┐
   * │ 原始布局 (256 bits)                                                         │
   * ├─────────────────────────────────────────────────────────────────────────────┤
   * │ [ open ratio | open ratio step | close fee ratio | funding ratio | reserved ]│
   * │ [  30 bits   |     60 bits     |     30 bits     |    32 bits    | 104 bits ]│
   * │ [ MSB                                                                   LSB ]│
   * ├─────────────────────────────────────────────────────────────────────────────┤
   * │ open ratio      - 开仓费率，乘以 1e9                                         │
   * │ open ratio step - 开仓费率步进，乘以 1e18                                    │
   * │ close fee ratio - 平仓费率，乘以 1e9                                         │
   * │ funding ratio   - 资金费率标量，乘以 1e9，最大值 4.294967296                 │
   * └─────────────────────────────────────────────────────────────────────────────┘
   */
  bytes32 private fundingMiscData;

  /**
   * @notice AAVE 借款利率快照
   * @dev borrowIndex 和 lastInterestRate 已弃用，仅 timestamp 仍在使用
   */
  BorrowRateSnapshot public borrowRateSnapshot;

  /*╔══════════════════════════════════════════════════════════════════════════════╗
    ║                              构造函数                                         ║
    ╚══════════════════════════════════════════════════════════════════════════════╝*/

  /**
   * @notice 构造函数
   * @param _poolManager PoolManager 合约地址，负责协调所有池操作
   * @param _configuration PoolConfiguration 合约地址，提供池配置参数
   */
  constructor(address _poolManager, address _configuration) BasePool(_poolManager, _configuration) {}

  /**
   * @notice 初始化函数（代理模式）
   * @dev 只能调用一次，设置初始状态
   *
   * @param admin 管理员地址，拥有 DEFAULT_ADMIN_ROLE
   * @param name_ ERC721 代币名称（仓位 NFT）
   * @param symbol_ ERC721 代币符号
   * @param _collateralToken 抵押品代币地址
   * @param _priceOracle 价格预言机地址
   *
   * ┌─────────────────────────────────────────────────────────────────────────────┐
   * │ 初始化流程                                                                  │
   * ├─────────────────────────────────────────────────────────────────────────────┤
   * │ 1. __ERC721_init          - 初始化 ERC721 (仓位 NFT)                        │
   * │ 2. __PoolStorage_init     - 初始化存储层 (抵押品代币、预言机)                │
   * │ 3. __TickLogic_init       - 初始化 Tick 系统 (树节点ID=1, topTick=MIN)      │
   * │ 4. __PositionLogic_init   - 初始化仓位系统 (positionId=1)                   │
   * │ 5. __BasePool_init        - 初始化基础池参数                                │
   * │    - debtIndex = collIndex = 2^96                                          │
   * │    - debtRatioRange = [50%, 85.7%]                                         │
   * │    - maxRedeemRatioPerTick = 20%                                           │
   * │ 6. 授予管理员角色                                                           │
   * │ 7. 设置借款利率快照时间戳                                                   │
   * └─────────────────────────────────────────────────────────────────────────────┘
   */
  function initialize(
    address admin,
    string memory name_,
    string memory symbol_,
    address _collateralToken,
    address _priceOracle
  ) external initializer {
    // __Context_init();
    // __ERC165_init();
    __ERC721_init(name_, symbol_);
    // __AccessControl_init();

    __PoolStorage_init(_collateralToken, _priceOracle);
    __TickLogic_init();
    __PositionLogic_init();
    __BasePool_init();

    _grantRole(DEFAULT_ADMIN_ROLE, admin);

    borrowRateSnapshot.timestamp = uint40(block.timestamp);
  }

  /*╔══════════════════════════════════════════════════════════════════════════════╗
    ║                           外部函数 - 抵押品减少                               ║
    ╚══════════════════════════════════════════════════════════════════════════════╝*/

  /**
   * @notice 减少池中的总抵押品（仅 PoolManager 可调用）
   * @dev 通过增加 collIndex 来实现抵押品减少，而不是直接转移代币
   *
   * @param amount 要减少的原始抵押品数量
   *
   * ┌─────────────────────────────────────────────────────────────────────────────┐
   * │ 执行流程                                                                    │
   * ├─────────────────────────────────────────────────────────────────────────────┤
   * │                                                                             │
   * │  1. 获取当前状态                                                            │
   * │     ├── totalColls = 总抵押品份额                                           │
   * │     ├── collIndex = 当前抵押品索引                                          │
   * │     └── totalRawColls = totalColls * E96 / collIndex                       │
   * │                                                                             │
   * │  2. 边界检查                                                                │
   * │     └── 如果 amount > totalRawColls → revert ErrorReduceTooMuchCollateral  │
   * │                                                                             │
   * │  3. 计算新索引                                                              │
   * │     └── newCollIndex = collIndex * totalRawColls / (totalRawColls - amount)│
   * │                                                                             │
   * │  4. 更新存储                                                                │
   * │     └── _updateCollateralIndex(newCollIndex)                               │
   * │                                                                             │
   * └─────────────────────────────────────────────────────────────────────────────┘
   *
   * ┌─────────────────────────────────────────────────────────────────────────────┐
   * │ 数学原理                                                                    │
   * ├─────────────────────────────────────────────────────────────────────────────┤
   * │                                                                             │
   * │  原始抵押品 = 份额 * E96 / 索引                                             │
   * │                                                                             │
   * │  设: 原始总量 = T, 减少量 = A, 原索引 = I, 新索引 = I'                      │
   * │                                                                             │
   * │  要求: 份额 * E96 / I' = T - A                                              │
   * │                                                                             │
   * │  因为: 份额 * E96 / I = T                                                   │
   * │  所以: 份额 * E96 = T * I                                                   │
   * │                                                                             │
   * │  代入: T * I / I' = T - A                                                   │
   * │  解得: I' = T * I / (T - A)                                                 │
   * │                                                                             │
   * │  【效果】: 索引增加 → 相同份额对应更少原始抵押品                              │
   * │                                                                             │
   * └─────────────────────────────────────────────────────────────────────────────┘
   *
   * @custom:security 仅 PoolManager 可调用 (onlyPoolManager 修饰符)
   * @custom:warning 没有检查减少后的债务覆盖率，调用方需确保安全
   */
  function reduceCollateral(uint256 amount) external onlyPoolManager {
    (, uint256 totalColls) = _getDebtAndCollateralShares();
    (, uint256 collIndex) = _getDebtAndCollateralIndex();
    uint256 totalRawColls = _convertToRawColl(totalColls, collIndex, Math.Rounding.Down);
    if (totalRawColls < amount) {
      revert ErrorReduceTooMuchCollateral();
    }

    uint256 newCollIndex = (collIndex * totalRawColls) / (totalRawColls - amount);
    _updateCollateralIndex(newCollIndex);
  }

  /*╔══════════════════════════════════════════════════════════════════════════════╗
    ║                           内部函数 - 索引更新                                 ║
    ╚══════════════════════════════════════════════════════════════════════════════╝*/

  /**
   * @inheritdoc BasePool
   * @notice 更新抵押品和债务索引（AaveFundingPool 特有实现）
   * @dev 此函数实现资金费率扣除机制
   *
   * @return newCollIndex 更新后的抵押品索引
   * @return newDebtIndex 更新后的债务索引（此实现中不变）
   *
   * ┌─────────────────────────────────────────────────────────────────────────────┐
   * │ 资金费率计算流程                                                            │
   * ├─────────────────────────────────────────────────────────────────────────────┤
   * │                                                                             │
   * │  1. 获取当前索引                                                            │
   * │     └── (debtIndex, collIndex) = _getDebtAndCollateralIndex()              │
   * │                                                                             │
   * │  2. 计算时间间隔                                                            │
   * │     └── duration = block.timestamp - borrowRateSnapshot.timestamp          │
   * │                                                                             │
   * │  3. 如果 duration > 0:                                                      │
   * │     │                                                                       │
   * │     ├── 3.1 获取资金费率                                                    │
   * │     │   └── fundingRatio = IPoolConfiguration.getLongPoolFundingRatio()    │
   * │     │                                                                       │
   * │     ├── 3.2 如果 fundingRatio > 0:                                          │
   * │     │   │                                                                   │
   * │     │   ├── 获取总抵押品份额和原始数量                                       │
   * │     │   │   └── totalRawColls = totalColls * E96 / collIndex               │
   * │     │   │                                                                   │
   * │     │   ├── 计算资金费用                                                    │
   * │     │   │   └── funding = totalRawColls * fundingRatio * duration          │
   * │     │   │                 / (PRECISION * 365 days)                          │
   * │     │   │                                                                   │
   * │     │   └── 更新抵押品索引                                                  │
   * │     │       └── newCollIndex = collIndex * totalRawColls                   │
   * │     │                         / (totalRawColls - funding)                  │
   * │     │                                                                       │
   * │     ├── 3.3 触发 checkpoint                                                 │
   * │     │   └── IPoolConfiguration.checkpoint(address(this))                   │
   * │     │                                                                       │
   * │     └── 3.4 更新时间戳                                                      │
   * │         └── borrowRateSnapshot.timestamp = block.timestamp                 │
   * │                                                                             │
   * └─────────────────────────────────────────────────────────────────────────────┘
   *
   * ┌─────────────────────────────────────────────────────────────────────────────┐
   * │ 资金费用公式                                                                │
   * ├─────────────────────────────────────────────────────────────────────────────┤
   * │                                                                             │
   * │  funding = totalRawColls × fundingRatio × duration                         │
   * │            ─────────────────────────────────────────                        │
   * │                    PRECISION × 365 days                                     │
   * │                                                                             │
   * │  其中:                                                                      │
   * │  - totalRawColls: 总原始抵押品数量                                          │
   * │  - fundingRatio: 年化资金费率 (乘以 1e18)                                   │
   * │  - duration: 时间间隔 (秒)                                                  │
   * │  - PRECISION: 1e18                                                         │
   * │  - 365 days: 31536000 秒                                                   │
   * │                                                                             │
   * │  【示例】: 如果 fundingRatio = 5% (5e16), duration = 1 day                  │
   * │           funding ≈ totalRawColls × 0.05 / 365 ≈ 0.0137% 的抵押品          │
   * │                                                                             │
   * └─────────────────────────────────────────────────────────────────────────────┘
   *
   * @custom:warning 边界情况: 如果 funding >= totalRawColls，会导致除零错误
   *                 调用方应确保 fundingRatio 和 duration 的乘积不会过大
   */
  function _updateCollAndDebtIndex() internal virtual override returns (uint256 newCollIndex, uint256 newDebtIndex) {
    (newDebtIndex, newCollIndex) = _getDebtAndCollateralIndex();

    BorrowRateSnapshot memory snapshot = borrowRateSnapshot;
    uint256 duration = block.timestamp - snapshot.timestamp;
    if (duration > 0) {
      uint256 fundingRatio = IPoolConfiguration(configuration).getLongPoolFundingRatio(address(this));
      if (fundingRatio > 0) {
        (, uint256 totalColls) = _getDebtAndCollateralShares();
        uint256 totalRawColls = _convertToRawColl(totalColls, newCollIndex, Math.Rounding.Down);
        uint256 funding = (totalRawColls * fundingRatio * duration) / (PRECISION * 365 days);

        // 通过增加抵押品索引来扣除资金费用
        // update collateral index with funding costs
        newCollIndex = (newCollIndex * totalRawColls) / (totalRawColls - funding);
        _updateCollateralIndex(newCollIndex);
      }

      // 在池配置上触发 checkpoint
      // checkpoint on pool configuration
      IPoolConfiguration(configuration).checkpoint(address(this));

      borrowRateSnapshot.timestamp = uint40(block.timestamp);
    }
  }

  /*╔══════════════════════════════════════════════════════════════════════════════╗
    ║                           内部函数 - 协议费用                                 ║
    ╚══════════════════════════════════════════════════════════════════════════════╝*/

  /**
   * @notice 扣除协议费用（AaveFundingPool 实现返回 0）
   * @dev AaveFundingPool 不收取开仓/平仓协议费用，费用通过资金费率机制收取
   *
   * ┌─────────────────────────────────────────────────────────────────────────────┐
   * │ 设计说明                                                                    │
   * ├─────────────────────────────────────────────────────────────────────────────┤
   * │                                                                             │
   * │  AaveFundingPool 的费用模型:                                                │
   * │  ┌─────────────────────────────────────────────────────────────────────┐   │
   * │  │ 开仓费用: 0                                                          │   │
   * │  │ 平仓费用: 0                                                          │   │
   * │  │ 资金费用: 通过 _updateCollAndDebtIndex() 持续扣除                    │   │
   * │  └─────────────────────────────────────────────────────────────────────┘   │
   * │                                                                             │
   * │  与其他池类型的对比:                                                        │
   * │  - 某些池可能在开仓时收取一次性费用                                         │
   * │  - AaveFundingPool 选择通过时间累积的资金费率收费                           │
   * │  - 这种模式对长期持仓者收费更多，短期持仓者收费更少                          │
   * │                                                                             │
   * └─────────────────────────────────────────────────────────────────────────────┘
   */
  /// @inheritdoc BasePool
  function _deductProtocolFees(int256) internal view virtual override returns (uint256) {
    return 0;
  }
}
