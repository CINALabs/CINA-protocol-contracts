// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { IPool } from "../../interfaces/IPool.sol";
import { IPoolConfiguration } from "../../interfaces/IPoolConfiguration.sol";
import { IPoolManager } from "../../interfaces/IPoolManager.sol";
import { IPriceOracle } from "../../price-oracle/interfaces/IPriceOracle.sol";

import { WordCodec } from "../../common/codec/WordCodec.sol";
import { Math } from "../../libraries/Math.sol";
import { TickBitmap } from "../../libraries/TickBitmap.sol";
import { PositionLogic } from "./PositionLogic.sol";
import { TickLogic } from "./TickLogic.sol";

/// @title BasePool - 基础池合约
/// @notice 实现资金池的核心业务逻辑，包括仓位操作、赎回、再平衡和清算
/// @dev 这是一个抽象合约，需要子合约实现 _updateCollAndDebtIndex 和 _deductProtocolFees
///
/// ==================== 核心功能概述 ====================
///
/// 1. operate() - 仓位操作
///    - 创建新仓位 / 修改现有仓位
///    - 存入/取出抵押品
///    - 借入/偿还债务
///
/// 2. redeem() - 赎回
///    - 用 fxUSD 换取抵押品
///    - 从高 tick 开始赎回
///    - 每个 tick 最多赎回一定比例
///
/// 3. rebalance() - 再平衡
///    - 降低高风险仓位的债务比率
///    - 再平衡者获得奖励
///    - 不会触发坏账
///
/// 4. liquidate() - 清算
///    - 清算超过清算阈值的仓位
///    - 清算者获得奖励
///    - 可能触发坏账重分配
///
/// ==================== 债务比率阈值 ====================
///
/// minDebtRatio < maxDebtRatio < rebalanceDebtRatio < liquidateDebtRatio
///
/// - [minDebtRatio, maxDebtRatio]: 正常操作范围
/// - rebalanceDebtRatio: 触发再平衡的阈值
/// - liquidateDebtRatio: 触发清算的阈值
///
abstract contract BasePool is TickLogic, PositionLogic {
  using TickBitmap for mapping(int8 => uint256);
  using WordCodec for bytes32;

  /***********
   * 结构体定义 *
   ***********/

  /// @dev operate() 函数使用的内存变量
  /// @notice 将多个变量打包到结构体中，避免 stack too deep 错误
  struct OperationMemoryVar {
    int256 tick;           // 仓位所属的 tick
    uint48 node;           // 仓位所属的树节点 ID
    uint256 positionColl;  // 仓位的抵押品份额
    uint256 positionDebt;  // 仓位的债务份额
    int256 newColl;        // 抵押品变化量（正=存入，负=取出）
    int256 newDebt;        // 债务变化量（正=借入，负=偿还）
    uint256 collIndex;     // 当前抵押品索引
    uint256 debtIndex;     // 当前债务索引
    uint256 globalColl;    // 全局抵押品份额
    uint256 globalDebt;    // 全局债务份额
    uint256 price;         // 当前价格
  }

  /*************
   * 修饰符 *
   *************/

  /// @dev 仅允许 PoolManager 调用
  /// @notice 所有用户操作都通过 PoolManager 路由，确保统一的入口
  modifier onlyPoolManager() {
    if (_msgSender() != poolManager) {
      revert ErrorCallerNotPoolManager();
    }
    _;
  }

  /***************
   * 构造函数 *
   ***************/

  /// @dev 设置不可变变量
  /// @param _poolManager 池管理器地址
  /// @param _configuration 配置合约地址
  constructor(address _poolManager, address _configuration) {
    _checkAddressNotZero(_poolManager);

    poolManager = _poolManager;
    fxUSD = IPoolManager(_poolManager).fxUSD();
    configuration = _configuration;
  }

  /// @dev 初始化基础池
  /// @notice 设置初始参数:
  ///   - 债务索引和抵押品索引初始化为 2^96
  ///   - 债务比率范围: 50% ~ 85.7% (1/2 ~ 6/7)
  ///   - 每个 tick 最大赎回比例: 20%
  function __BasePool_init() internal onlyInitializing {
    _updateDebtIndex(E96);                                      // 初始债务索引 = 2^96
    _updateCollateralIndex(E96);                                // 初始抵押品索引 = 2^96
    _updateDebtRatioRange(500000000000000000, 857142857142857142); // 债务比率范围: 50% ~ 85.7%
    _updateMaxRedeemRatioPerTick(200000000);                    // 每个 tick 最大赎回 20%
  }

  /****************************
   * 公共状态修改函数 *
   ****************************/

  /// @inheritdoc IPool
  /// @notice 仓位操作 - 核心函数
  /// @dev 处理所有仓位相关操作：创建、存入、取出、借入、偿还
  ///
  /// ==================== 函数流程 ====================
  ///
  /// 1. 参数验证
  ///    - 检查操作是否有效（不能同时为0）
  ///    - 检查数量是否满足最小要求
  ///    - 检查借款是否被暂停
  ///
  /// 2. 初始化
  ///    - 获取价格、索引、全局份额
  ///    - 创建新仓位或加载现有仓位
  ///
  /// 3. 处理抵押品变化
  ///    - 存入: 扣除协议费用，增加份额
  ///    - 取出: 减少份额，扣除协议费用
  ///
  /// 4. 处理债务变化
  ///    - 借入: 增加债务份额
  ///    - 偿还: 减少债务份额
  ///
  /// 5. 最终检查
  ///    - 验证债务比率在允许范围内
  ///
  /// 6. 更新状态
  ///    - 将仓位添加到新的 tick
  ///    - 更新全局份额
  ///
  /// @param positionId 仓位 ID（0 表示创建新仓位）
  /// @param newRawColl 抵押品变化量（正=存入，负=取出，type(int256).min=全部取出）
  /// @param newRawDebt 债务变化量（正=借入，负=偿还，type(int256).min=全部偿还）
  /// @param owner 仓位所有者地址
  /// @return positionId 仓位 ID
  /// @return newRawColl 实际抵押品变化量
  /// @return newRawDebt 实际债务变化量
  /// @return protocolFees 协议费用
  function operate(
    uint256 positionId,
    int256 newRawColl,
    int256 newRawDebt,
    address owner
  ) external onlyPoolManager returns (uint256, int256, int256, uint256) {
    // ========== 步骤1: 参数验证 ==========
    
    // 必须有操作（不能同时为0）
    if (newRawColl == 0 && newRawDebt == 0) revert ErrorNoSupplyAndNoBorrow();
    
    // 抵押品变化量必须满足最小要求（或为0）
    if (newRawColl != 0 && (newRawColl > -MIN_COLLATERAL && newRawColl < MIN_COLLATERAL)) {
      revert ErrorCollateralTooSmall();
    }
    
    // 债务变化量必须满足最小要求（或为0）
    if (newRawDebt != 0 && (newRawDebt > -MIN_DEBT && newRawDebt < MIN_DEBT)) {
      revert ErrorDebtTooSmall();
    }
    
    // 借款时检查是否被暂停
    if (newRawDebt > 0 && (_isBorrowPaused() || !IPoolConfiguration(configuration).isBorrowAllowed())) {
      revert ErrorBorrowPaused();
    }

    // ========== 步骤2: 初始化 ==========
    
    OperationMemoryVar memory op;
    // 获取交换价格（价格精度和比率精度都是 1e18）
    op.price = IPriceOracle(priceOracle).getExchangePrice();
    // 获取全局份额
    (op.globalDebt, op.globalColl) = _getDebtAndCollateralShares();
    // 更新并获取索引
    (op.collIndex, op.debtIndex) = _updateCollAndDebtIndex();
    
    if (positionId == 0) {
      // 创建新仓位
      positionId = _mintPosition(owner);
    } else {
      // 加载现有仓位
      // 取出或借款时必须是仓位所有者
      if (ownerOf(positionId) != owner && (newRawColl < 0 || newRawDebt > 0)) {
        revert ErrorNotPositionOwner();
      }
      
      // 获取并更新仓位数据（应用树节点比率）
      PositionInfo memory position = _getAndUpdatePosition(positionId);
      
      // 临时从 tick 树中移除仓位（简化后续处理）
      _removePositionFromTick(position);
      
      op.tick = position.tick;
      op.node = position.nodeId;
      op.positionDebt = position.debts;
      op.positionColl = position.colls;

      // 取出或借款时，检查仓位是否已超过清算阈值
      if (newRawColl < 0 || newRawDebt > 0) {
        uint256 rawColls = _convertToRawColl(op.positionColl, op.collIndex, Math.Rounding.Down);
        uint256 rawDebts = _convertToRawDebt(op.positionDebt, op.debtIndex, Math.Rounding.Down);
        (uint256 debtRatio, ) = _getLiquidateRatios();
        // 债务比率 = rawDebts / (rawColls × price)
        // 检查: rawDebts × PRECISION² > debtRatio × rawColls × price
        if (rawDebts * PRECISION * PRECISION > debtRatio * rawColls * op.price) {
          revert ErrorPositionInLiquidationMode();
        }
      }
    }

    // ========== 步骤3: 处理抵押品变化 ==========
    
    uint256 protocolFees;
    
    if (newRawColl > 0) {
      // 存入抵押品
      // 先扣除协议费用
      protocolFees = _deductProtocolFees(newRawColl);
      newRawColl -= int256(protocolFees);
      // 转换为份额（向下取整，对协议有利）
      op.newColl = int256(_convertToCollShares(uint256(newRawColl), op.collIndex, Math.Rounding.Down));
      // 增加仓位和全局份额
      op.positionColl += uint256(op.newColl);
      op.globalColl += uint256(op.newColl);
    } else if (newRawColl < 0) {
      // 取出抵押品
      if (newRawColl == type(int256).min) {
        // type(int256).min 表示全部取出
        newRawColl = -int256(_convertToRawColl(op.positionColl, op.collIndex, Math.Rounding.Down));
        op.newColl = -int256(op.positionColl);
      } else {
        // 部分取出（向上取整，确保用户不会多取）
        op.newColl = -int256(_convertToCollShares(uint256(-newRawColl), op.collIndex, Math.Rounding.Up));
        if (uint256(-op.newColl) > op.positionColl) revert ErrorWithdrawExceedSupply();
      }
      unchecked {
        // 减少仓位和全局份额
        op.positionColl -= uint256(-op.newColl);
        op.globalColl -= uint256(-op.newColl);
      }
      // 取出时也扣除协议费用
      protocolFees = _deductProtocolFees(newRawColl);
      newRawColl += int256(protocolFees);  // 负数加正数，减少取出量
    }

    // ========== 步骤4: 处理债务变化 ==========
    
    if (newRawDebt > 0) {
      // 借入债务（向上取整，对协议有利）
      op.newDebt = int256(_convertToDebtShares(uint256(newRawDebt), op.debtIndex, Math.Rounding.Up));
      op.positionDebt += uint256(op.newDebt);
      op.globalDebt += uint256(op.newDebt);
    } else if (newRawDebt < 0) {
      // 偿还债务
      if (newRawDebt == type(int256).min) {
        // type(int256).min 表示全部偿还
        // 向上取整，确保完全还清
        newRawDebt = -int256(_convertToRawDebt(op.positionDebt, op.debtIndex, Math.Rounding.Up));
        op.newDebt = -int256(op.positionDebt);
      } else {
        // 部分偿还（向上取整份额，减少实际偿还量）
        op.newDebt = -int256(_convertToDebtShares(uint256(-newRawDebt), op.debtIndex, Math.Rounding.Up));
      }
      op.positionDebt -= uint256(-op.newDebt);
      op.globalDebt -= uint256(-op.newDebt);
    }

    // ========== 步骤5: 最终债务比率检查 ==========
    {
      // 检查仓位债务比率是否在 [minDebtRatio, maxDebtRatio] 范围内
      uint256 rawColls = _convertToRawColl(op.positionColl, op.collIndex, Math.Rounding.Down);
      uint256 rawDebts = _convertToRawDebt(op.positionDebt, op.debtIndex, Math.Rounding.Down);
      (uint256 minDebtRatio, uint256 maxDebtRatio) = _getDebtRatioRange();
      
      // 债务比率 = rawDebts / (rawColls × price)
      // 检查: rawDebts × PRECISION² > maxDebtRatio × rawColls × price
      if (rawDebts * PRECISION * PRECISION > maxDebtRatio * rawColls * op.price) {
        revert ErrorDebtRatioTooLarge();
      }
      // 检查: rawDebts × PRECISION² < minDebtRatio × rawColls × price
      if (rawDebts * PRECISION * PRECISION < minDebtRatio * rawColls * op.price) {
        revert ErrorDebtRatioTooSmall();
      }
    }

    // ========== 步骤6: 更新状态 ==========
    
    // 将仓位添加到新的 tick
    (op.tick, op.node) = _addPositionToTick(op.positionColl, op.positionDebt, true);

    // 检查溢出
    if (op.positionColl > type(uint96).max) revert ErrorOverflow();
    if (op.positionDebt > type(uint96).max) revert ErrorOverflow();
    
    // 保存仓位数据
    positionData[positionId] = PositionInfo(int16(op.tick), op.node, uint96(op.positionColl), uint96(op.positionDebt));

    // 更新全局份额
    _updateDebtAndCollateralShares(op.globalDebt, op.globalColl);

    // 发出事件
    emit PositionSnapshot(positionId, int16(op.tick), op.positionColl, op.positionDebt, op.price);

    return (positionId, newRawColl, newRawDebt, protocolFees);
  }

  /// @inheritdoc IPool
  /// @notice 赎回 - 用 fxUSD 换取抵押品
  /// @param rawDebts 要赎回的 fxUSD 数量
  /// @return actualRawDebts 实际赎回的 fxUSD 数量
  /// @return rawColls 获得的抵押品数量
  function redeem(uint256 rawDebts) external onlyPoolManager returns (uint256 actualRawDebts, uint256 rawColls) {
    return redeem(rawDebts, false);
  }

  /// @inheritdoc IPool
  /// @notice 赎回 - 带 tick 移动检查选项
  /// @dev 赎回机制:
  ///   1. 从最高 tick 开始赎回
  ///   2. 每个 tick 最多赎回 maxRedeemRatioPerTick 比例
  ///   3. 赎回价格由预言机提供
  ///
  /// @param rawDebts 要赎回的 fxUSD 数量
  /// @param allowTickNotMoved 是否允许 tick 不移动（用于信用票据赎回）
  /// @return actualRawDebts 实际赎回的 fxUSD 数量
  /// @return rawColls 获得的抵押品数量
  function redeem(uint256 rawDebts, bool allowTickNotMoved) public onlyPoolManager returns (uint256 actualRawDebts, uint256 rawColls) {
    if (_isRedeemPaused()) revert ErrorRedeemPaused();

    (actualRawDebts, rawColls) = _redeem(rawDebts, allowTickNotMoved);
  }

  /// @inheritdoc IPool
  /// @notice 单 tick 再平衡
  /// @dev 再平衡机制:
  ///   - 当 tick 的债务比率 >= rebalanceDebtRatio 且 < liquidateDebtRatio 时可再平衡
  ///   - 再平衡者支付 fxUSD，获得抵押品 + 奖励
  ///   - 再平衡后 tick 的债务比率降低到 rebalanceDebtRatio
  ///
  /// @param tick 要再平衡的 tick
  /// @param maxRawDebts 最大愿意支付的 fxUSD 数量
  /// @return result 再平衡结果
  function rebalance(int16 tick, uint256 maxRawDebts) external onlyPoolManager returns (RebalanceResult memory result) {
    // 更新索引
    (uint256 cachedCollIndex, uint256 cachedDebtIndex) = _updateCollAndDebtIndex();
    // 获取价格（使用最小价格，对协议有利）
    (, uint256 price, ) = IPriceOracle(priceOracle).getPrice();
    
    // 获取 tick 的当前状态
    uint256 node = tickData[tick];
    bytes32 value = tickTreeData[node].value;
    uint256 tickRawColl = _convertToRawColl(
      value.decodeUint(COLL_SHARE_OFFSET, 128),
      cachedCollIndex,
      Math.Rounding.Down
    );
    uint256 tickRawDebt = _convertToRawDebt(
      value.decodeUint(DEBT_SHARE_OFFSET, 128),
      cachedDebtIndex,
      Math.Rounding.Down
    );
    
    // 获取再平衡和清算参数
    (uint256 rebalanceDebtRatio, uint256 rebalanceBonusRatio) = _getRebalanceRatios();
    (uint256 liquidateDebtRatio, ) = _getLiquidateRatios();
    
    // 检查: 债务比率必须 >= rebalanceDebtRatio
    if (tickRawDebt * PRECISION * PRECISION < rebalanceDebtRatio * tickRawColl * price) {
      revert ErrorRebalanceDebtRatioNotReached();
    }
    // 检查: 债务比率必须 < liquidateDebtRatio（否则应该清算而不是再平衡）
    if (tickRawDebt * PRECISION * PRECISION >= liquidateDebtRatio * tickRawColl * price) {
      revert ErrorRebalanceOnLiquidatableTick();
    }

    // 计算需要再平衡的债务量，使债务比率降到 rebalanceDebtRatio
    result.rawDebts = _getRawDebtToRebalance(tickRawColl, tickRawDebt, price, rebalanceDebtRatio, rebalanceBonusRatio);
    // 不超过用户指定的最大值
    if (maxRawDebts < result.rawDebts) result.rawDebts = maxRawDebts;

    // 计算份额和抵押品
    uint256 debtShareToRebalance = _convertToDebtShares(result.rawDebts, cachedDebtIndex, Math.Rounding.Down);
    // 抵押品 = 债务 / 价格
    result.rawColls = (result.rawDebts * PRECISION) / price;
    // 奖励 = 抵押品 × 奖励比率
    result.bonusRawColls = (result.rawColls * rebalanceBonusRatio) / FEE_PRECISION;
    // 奖励不能超过剩余抵押品
    if (result.bonusRawColls > tickRawColl - result.rawColls) {
      result.bonusRawColls = tickRawColl - result.rawColls;
    }
    uint256 collShareToRebalance = _convertToCollShares(
      result.rawColls + result.bonusRawColls,
      cachedCollIndex,
      Math.Rounding.Down
    );

    // 执行清算（更新树节点）
    _liquidateTick(tick, collShareToRebalance, debtShareToRebalance, price);
    
    // 更新全局份额
    unchecked {
      (uint256 totalDebts, uint256 totalColls) = _getDebtAndCollateralShares();
      _updateDebtAndCollateralShares(totalDebts - debtShareToRebalance, totalColls - collShareToRebalance);
    }
  }

  /// @dev 批量再平衡使用的内存变量
  struct RebalanceVars {
    uint256 tickCollShares;      // 当前 tick 的抵押品份额
    uint256 tickDebtShares;      // 当前 tick 的债务份额
    uint256 tickRawColls;        // 当前 tick 的原始抵押品
    uint256 tickRawDebts;        // 当前 tick 的原始债务
    uint256 maxRawDebts;         // 剩余可用的最大债务量
    uint256 rebalanceDebtRatio;  // 再平衡触发债务比率
    uint256 rebalanceBonusRatio; // 再平衡奖励比率
    uint256 price;               // 当前价格
    uint256 collIndex;           // 抵押品索引
    uint256 debtIndex;           // 债务索引
    uint256 totalCollShares;     // 全局抵押品份额
    uint256 totalDebtShares;     // 全局债务份额
  }

  /// @inheritdoc IPool
  /// @notice 批量再平衡 - 自动遍历所有可再平衡的 tick
  /// @dev 从最高 tick 开始，依次再平衡直到:
  ///   - 用完 maxRawDebts
  ///   - 或没有更多可再平衡的 tick
  ///
  /// 跳过条件:
  ///   - 坏账仓位（债务比率 >= 清算比率）
  ///   - 粉尘仓位（债务 < MIN_DEBT）
  ///   - 健康仓位（债务比率 < 再平衡比率）
  ///
  /// @param maxRawDebts 最大愿意支付的 fxUSD 数量
  /// @return result 再平衡结果（累计）
  function rebalance(uint256 maxRawDebts) external onlyPoolManager returns (RebalanceResult memory result) {
    RebalanceVars memory vars;
    vars.maxRawDebts = maxRawDebts;
    
    // 获取参数
    (vars.rebalanceDebtRatio, vars.rebalanceBonusRatio) = _getRebalanceRatios();
    (, vars.price, ) = IPriceOracle(priceOracle).getPrice();
    (vars.collIndex, vars.debtIndex) = _updateCollAndDebtIndex();
    (vars.totalDebtShares, vars.totalCollShares) = _getDebtAndCollateralShares();
    (uint256 liquidateDebtRatio, ) = _getLiquidateRatios();

    // 从顶部 tick 开始遍历
    int16 tick = _getTopTick();
    bool hasDebt = true;
    
    while (vars.maxRawDebts > 0) {
      if (!hasDebt) {
        // 当前 tick 无债务，查找下一个有债务的 tick
        (tick, hasDebt) = tickBitmap.nextDebtPositionWithinOneWord(tick - 1);
      } else {
        // 获取 tick 的数据
        (vars.tickCollShares, vars.tickDebtShares, vars.tickRawColls, vars.tickRawDebts) = _getTickRawCollAndDebts(
          tick,
          vars.collIndex,
          vars.debtIndex
        );
        
        // 跳过坏账和可清算仓位: coll × price × liquidateDebtRatio <= debts
        if (vars.tickRawColls * vars.price * liquidateDebtRatio <= vars.tickRawDebts * PRECISION * PRECISION) {
          hasDebt = false;
          tick = tick;
          continue;
        }
        
        // 跳过粉尘仓位
        if (vars.tickRawDebts < uint256(MIN_DEBT)) {
          hasDebt = false;
          tick = tick;
          continue;
        }
        
        // 如果债务比率 < 再平衡比率，说明没有更多可再平衡的 tick
        if (vars.tickRawColls * vars.price * vars.rebalanceDebtRatio > vars.tickRawDebts * PRECISION * PRECISION) {
          break;
        }
        
        // 再平衡此 tick
        (uint256 rawDebts, uint256 rawColls, uint256 bonusRawColls) = _rebalanceTick(tick, vars);
        result.rawDebts += rawDebts;
        result.rawColls += rawColls;
        result.bonusRawColls += bonusRawColls;

        // 移动到下一个 tick
        (tick, hasDebt) = tickBitmap.nextDebtPositionWithinOneWord(tick - 1);
      }
      
      // 如果已经到达最小 tick，退出循环
      if (tick == type(int16).min) break;
    }

    // 更新全局份额
    _updateDebtAndCollateralShares(vars.totalDebtShares, vars.totalCollShares);
  }

  /// @dev 清算使用的内存变量
  struct LiquidateVars {
    uint256 tickCollShares;      // 当前 tick 的抵押品份额
    uint256 tickDebtShares;      // 当前 tick 的债务份额
    uint256 tickRawColls;        // 当前 tick 的原始抵押品
    uint256 tickRawDebts;        // 当前 tick 的原始债务
    uint256 maxRawDebts;         // 剩余可用的最大债务量
    uint256 reservedRawColls;    // 储备金（用于补贴清算奖励）
    uint256 liquidateDebtRatio;  // 清算触发债务比率
    uint256 liquidateBonusRatio; // 清算奖励比率
    uint256 price;               // 清算价格
    uint256 collIndex;           // 抵押品索引
    uint256 debtIndex;           // 债务索引（可能因坏账重分配而变化）
    uint256 totalCollShares;     // 全局抵押品份额
    uint256 totalDebtShares;     // 全局债务份额
  }

  /// @inheritdoc IPool
  /// @notice 清算 - 清算超过清算阈值的仓位
  /// @dev 清算机制:
  ///   - 当 tick 的债务比率 >= liquidateDebtRatio 时可清算
  ///   - 清算者支付 fxUSD，获得抵押品 + 奖励
  ///   - 奖励优先从 tick 的抵押品中扣除，不足时从储备金补贴
  ///   - 如果抵押品不足以覆盖债务（坏账），触发坏账重分配
  ///
  /// 坏账重分配:
  ///   - 坏账 = 无法偿还的债务
  ///   - 通过增加 debtIndex 将坏账分摊给所有债务持有者
  ///
  /// @param maxRawDebts 最大愿意支付的 fxUSD 数量
  /// @param reservedRawColls 储备金数量（用于补贴清算奖励）
  /// @return result 清算结果
  function liquidate(
    uint256 maxRawDebts,
    uint256 reservedRawColls
  ) external onlyPoolManager returns (LiquidateResult memory result) {
    LiquidateVars memory vars;
    vars.maxRawDebts = maxRawDebts;
    vars.reservedRawColls = reservedRawColls;
    
    // 获取清算参数
    (vars.liquidateDebtRatio, vars.liquidateBonusRatio) = _getLiquidateRatios();
    // 使用清算价格（可能与交换价格不同）
    vars.price = IPriceOracle(priceOracle).getLiquidatePrice();
    (vars.collIndex, vars.debtIndex) = _updateCollAndDebtIndex();
    (vars.totalDebtShares, vars.totalCollShares) = _getDebtAndCollateralShares();

    // 从顶部 tick 开始遍历
    int16 tick = _getTopTick();
    bool hasDebt = true;
    
    while (vars.maxRawDebts > 0) {
      if (!hasDebt) {
        // 查找下一个有债务的 tick
        (tick, hasDebt) = tickBitmap.nextDebtPositionWithinOneWord(tick - 1);
      } else {
        // 获取 tick 的数据
        (vars.tickCollShares, vars.tickDebtShares, vars.tickRawColls, vars.tickRawDebts) = _getTickRawCollAndDebts(
          tick,
          vars.collIndex,
          vars.debtIndex
        );
        
        // 如果债务比率 < 清算比率，说明没有更多可清算的 tick
        if (vars.tickRawColls * vars.price * vars.liquidateDebtRatio > vars.tickRawDebts * PRECISION * PRECISION) {
          // 跳过粉尘仓位（结果可能不准确）
          if (vars.tickRawDebts < uint256(MIN_DEBT)) {
            hasDebt = false;
            tick = tick;
            continue;
          }
          break;
        }
        
        // 清算此 tick
        (uint256 rawDebts, uint256 rawColls, uint256 bonusRawColls, uint256 bonusFromReserve) = _liquidateTick(
          tick,
          vars
        );
        result.rawDebts += rawDebts;
        result.rawColls += rawColls;
        result.bonusRawColls += bonusRawColls;
        result.bonusFromReserve += bonusFromReserve;

        // 移动到下一个 tick
        (tick, hasDebt) = tickBitmap.nextDebtPositionWithinOneWord(tick - 1);
      }
      
      // 如果已经到达最小 tick，退出循环
      if (tick == type(int16).min) break;
    }

    // 更新全局状态
    _updateDebtAndCollateralShares(vars.totalDebtShares, vars.totalCollShares);
    // 更新债务索引（可能因坏账重分配而变化）
    _updateDebtIndex(vars.debtIndex);
  }

  /// @inheritdoc IPool
  /// @notice 减少债务 - 通过降低债务索引来减少所有仓位的债务
  /// @dev 这是一种特殊操作，用于:
  ///   - 分发协议收益给债务持有者
  ///   - 或其他需要减少总债务的场景
  ///
  /// 原理:
  ///   - 实际债务 = 债务份额 × 债务索引 / E96
  ///   - 降低债务索引 -> 所有仓位的实际债务同比例减少
  ///
  /// 限制: 单次最多减少 10% 的总债务，避免精度损失
  ///
  /// @param rawAmount 要减少的债务数量
  function reduceDebt(uint256 rawAmount) external onlyPoolManager {
    (, uint256 debtIndex) = _updateCollAndDebtIndex();
    (uint256 totalDebtShares, ) = _getDebtAndCollateralShares();
    uint256 totalRawDebts = _convertToRawDebt(totalDebtShares, debtIndex, Math.Rounding.Down);
    
    // 限制: 单次最多减少 10% 的总债务
    if (rawAmount * 10 > totalRawDebts) {
      revert ErrorReduceTooMuchDebt();
    }

    // 计算新的债务索引
    // newIndex = oldIndex - (rawAmount × E96 / totalDebtShares)
    debtIndex -= (rawAmount * E96) / totalDebtShares;
    _updateDebtIndex(debtIndex);
  }

  /************************
   * 管理函数 *
   ************************/

  /// @notice 更新借款和赎回状态
  /// @dev 仅 EMERGENCY_ROLE 可调用，用于紧急情况
  /// @param borrowStatus 新的借款暂停状态（true=暂停）
  /// @param redeemStatus 新的赎回暂停状态（true=暂停）
  function updateBorrowAndRedeemStatus(bool borrowStatus, bool redeemStatus) external onlyRole(EMERGENCY_ROLE) {
    _updateBorrowStatus(borrowStatus);
    _updateRedeemStatus(redeemStatus);
  }

  /// @notice 更新债务比率范围
  /// @dev 仅管理员可调用
  /// @param minRatio 最小允许债务比率（×1e18）
  /// @param maxRatio 最大允许债务比率（×1e18）
  function updateDebtRatioRange(uint256 minRatio, uint256 maxRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateDebtRatioRange(minRatio, maxRatio);
  }

  /// @notice 更新每个 tick 的最大赎回比例
  /// @dev 仅管理员可调用
  /// @param ratio 最大赎回比例（×1e9）
  function updateMaxRedeemRatioPerTick(uint256 ratio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateMaxRedeemRatioPerTick(ratio);
  }

  /// @notice 更新再平衡参数
  /// @dev 仅管理员可调用
  /// @param debtRatio 触发再平衡的最小债务比率（×1e18）
  /// @param bonusRatio 再平衡奖励比率（×1e9）
  function updateRebalanceRatios(uint256 debtRatio, uint256 bonusRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateRebalanceRatios(debtRatio, bonusRatio);
  }

  /// @notice 更新清算参数
  /// @dev 仅管理员可调用
  /// @param debtRatio 触发清算的最小债务比率（×1e18）
  /// @param bonusRatio 清算奖励比率（×1e9）
  function updateLiquidateRatios(uint256 debtRatio, uint256 bonusRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateLiquidateRatios(debtRatio, bonusRatio);
  }

  /// @notice 更新价格预言机地址
  /// @dev 仅管理员可调用
  /// @param newOracle 新的价格预言机地址
  function updatePriceOracle(address newOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updatePriceOracle(newOracle);
  }

  /// @notice 更新对手方池地址
  /// @dev 仅管理员可调用，用于多空池配对
  /// @param newCounterparty 新的对手方池地址
  function updateCounterparty(address newCounterparty) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateCounterparty(newCounterparty);
  }

  /**********************
   * 内部函数 *
   **********************/

  /// @dev 内部赎回函数
  /// @notice 用 fxUSD 换取抵押品
  ///
  /// ==================== 赎回流程 ====================
  ///
  /// 1. 检查全局债务比率 < 1（否则池子抵押不足）
  /// 2. 从最高 tick 开始遍历
  /// 3. 每个 tick 最多赎回 maxRedeemRatioPerTick 比例
  /// 4. 跳过坏账和粉尘仓位
  /// 5. 如果 tick 不会移动，停止赎回（除非 allowTickNotMoved）
  ///
  /// @param rawDebts 要赎回的 fxUSD 数量
  /// @param allowTickNotMoved 是否允许 tick 不移动
  /// @return actualRawDebts 实际赎回的 fxUSD 数量
  /// @return rawColls 获得的抵押品数量
  function _redeem(
    uint256 rawDebts,
    bool allowTickNotMoved
  ) internal returns (uint256 actualRawDebts, uint256 rawColls) {
    // 更新索引
    (uint256 cachedCollIndex, uint256 cachedDebtIndex) = _updateCollAndDebtIndex();
    (uint256 cachedTotalDebts, uint256 cachedTotalColls) = _getDebtAndCollateralShares();
    // 获取赎回价格
    uint256 price = IPriceOracle(priceOracle).getRedeemPrice();
    
    // 检查全局债务比率 < 1
    // 如果 totalDebts >= totalColls × price，说明池子抵押不足，禁止赎回
    {
      uint256 totalRawColls = _convertToRawColl(cachedTotalColls, cachedCollIndex, Math.Rounding.Down);
      uint256 totalRawDebts = _convertToRawDebt(cachedTotalDebts, cachedDebtIndex, Math.Rounding.Down);
      if (totalRawDebts * PRECISION >= totalRawColls * price) revert ErrorPoolUnderCollateral();
    }

    // 从顶部 tick 开始遍历
    int16 tick = _getTopTick();
    bool hasDebt = true;
    // 将原始债务转换为份额
    uint256 debtShare = _convertToDebtShares(rawDebts, cachedDebtIndex, Math.Rounding.Down);
    
    while (debtShare > 0) {
      if (!hasDebt) {
        // 查找下一个有债务的 tick
        (tick, hasDebt) = tickBitmap.nextDebtPositionWithinOneWord(tick - 1);
      } else {
        uint256 tickDebtShare;
        {
          uint256 node = tickData[tick];
          bytes32 value = tickTreeData[node].value;
          tickDebtShare = value.decodeUint(DEBT_SHARE_OFFSET, 128);
          
          // 跳过坏账: 债务 > 抵押品 × 价格
          {
            uint256 tickCollShare = value.decodeUint(COLL_SHARE_OFFSET, 128);
            if (
              _convertToRawDebt(tickDebtShare, cachedDebtIndex, Math.Rounding.Down) * PRECISION >
              _convertToRawColl(tickCollShare, cachedCollIndex, Math.Rounding.Down) * price
            ) {
              hasDebt = false;
              tick = tick;
              continue;
            }
          }
          
          // 跳过粉尘仓位
          if (tickDebtShare < uint256(MIN_DEBT)) {
            hasDebt = false;
            tick = tick;
            continue;
          }
        }

        // 计算此 tick 可赎回的最大份额（不超过 maxRedeemRatioPerTick）
        uint256 debtShareToRedeem = (tickDebtShare * _getMaxRedeemRatioPerTick()) / FEE_PRECISION;
        if (debtShareToRedeem > debtShare) debtShareToRedeem = debtShare;
        
        // 转换为原始数量
        uint256 rawDebtsToRedeem = _convertToRawDebt(debtShareToRedeem, cachedDebtIndex, Math.Rounding.Down);
        uint256 rawCollRedeemed = (rawDebtsToRedeem * PRECISION) / price;
        uint256 collShareRedeemed = _convertToCollShares(rawCollRedeemed, cachedCollIndex, Math.Rounding.Down);

        // 检查 tick 是否会移动
        // 如果不允许 tick 不移动，且 tick 不会移动，则停止赎回
        if (!allowTickNotMoved && !_tickWillMove(tick, collShareRedeemed, debtShareToRedeem)) break;

        // 执行清算（更新树节点）
        _liquidateTick(tick, collShareRedeemed, debtShareToRedeem, price);
        
        // 更新累计值
        debtShare -= debtShareToRedeem;
        actualRawDebts += rawDebtsToRedeem;
        rawColls += rawCollRedeemed;

        cachedTotalColls -= collShareRedeemed;
        cachedTotalDebts -= debtShareToRedeem;

        // 移动到下一个 tick
        (tick, hasDebt) = tickBitmap.nextDebtPositionWithinOneWord(tick - 1);
      }
      
      // 如果已经到达最小 tick，退出循环
      if (tick == type(int16).min) break;
    }
    
    // 更新全局份额
    _updateDebtAndCollateralShares(cachedTotalDebts, cachedTotalColls);
  }

  /// @dev 计算达到目标债务比率需要再平衡的债务量
  /// @notice 数学推导:
  ///
  /// 设:
  ///   - x = 需要再平衡的债务量
  ///   - y = 需要移除的抵押品量 = x / price
  ///   - incentive = 奖励比率
  ///   - target = 目标债务比率
  ///
  /// 约束条件:
  ///   1. 再平衡后债务比率 <= target
  ///      (debt - x) / (price × (coll - y × (1 + incentive))) <= target
  ///   2. 当前债务比率 >= target
  ///      debt / (price × coll) >= target
  ///
  /// 推导:
  ///   debt - x <= target × price × (coll - y × (1 + incentive))
  ///   其中 y = x / price
  ///   => debt - x <= target × price × coll - target × (1 + incentive) × x
  ///   => debt - target × price × coll <= x × (1 - target × (1 + incentive))
  ///   => x >= (debt - target × price × coll) / (1 - target × (1 + incentive))
  ///
  /// @param coll 抵押品数量
  /// @param debt 债务数量
  /// @param price 价格
  /// @param targetDebtRatio 目标债务比率（×1e18）
  /// @param incentiveRatio 奖励比率（×1e9）
  /// @return rawDebts 需要再平衡的债务量
  function _getRawDebtToRebalance(
    uint256 coll,
    uint256 debt,
    uint256 price,
    uint256 targetDebtRatio,
    uint256 incentiveRatio
  ) internal pure returns (uint256 rawDebts) {
    // 分子: debt × PRECISION² - targetDebtRatio × price × coll
    // 分母: PRECISION² - PRECISION × targetDebtRatio × (1 + incentiveRatio)
    rawDebts =
      (debt * PRECISION * PRECISION - targetDebtRatio * price * coll) /
      (PRECISION * PRECISION - (PRECISION * targetDebtRatio * (FEE_PRECISION + incentiveRatio)) / FEE_PRECISION);
  }

  /// @dev 获取 tick 的原始抵押品和债务数量
  /// @param tick 目标 tick
  /// @param collIndex 抵押品索引
  /// @param debtIndex 债务索引
  /// @return colls 抵押品份额
  /// @return debts 债务份额
  /// @return rawColls 原始抵押品数量
  /// @return rawDebts 原始债务数量
  function _getTickRawCollAndDebts(
    int16 tick,
    uint256 collIndex,
    uint256 debtIndex
  ) internal view returns (uint256 colls, uint256 debts, uint256 rawColls, uint256 rawDebts) {
    uint256 node = tickData[tick];
    bytes32 value = tickTreeData[node].value;
    colls = value.decodeUint(COLL_SHARE_OFFSET, 128);
    debts = value.decodeUint(DEBT_SHARE_OFFSET, 128);
    rawColls = _convertToRawColl(colls, collIndex, Math.Rounding.Down);
    rawDebts = _convertToRawDebt(debts, debtIndex, Math.Rounding.Down);
  }

  /// @dev 再平衡单个 tick
  /// @notice 执行再平衡操作，更新状态
  ///
  /// 步骤:
  /// 1. 计算需要再平衡的债务量
  /// 2. 计算对应的抵押品和奖励
  /// 3. 执行清算（更新树节点）
  /// 4. 更新全局份额
  ///
  /// @param tick 要再平衡的 tick
  /// @param vars 再平衡变量（会被修改）
  /// @return rawDebts 再平衡的债务量
  /// @return rawColls 获得的抵押品量
  /// @return bonusRawColls 奖励的抵押品量
  function _rebalanceTick(
    int16 tick,
    RebalanceVars memory vars
  ) internal returns (uint256 rawDebts, uint256 rawColls, uint256 bonusRawColls) {
    // 步骤1: 计算需要再平衡的债务量
    rawDebts = _getRawDebtToRebalance(
      vars.tickRawColls,
      vars.tickRawDebts,
      vars.price,
      vars.rebalanceDebtRatio,
      vars.rebalanceBonusRatio
    );
    // 不超过用户指定的最大值
    if (vars.maxRawDebts < rawDebts) rawDebts = vars.maxRawDebts;

    // 步骤2: 计算抵押品和奖励
    uint256 debtShares = _convertToDebtShares(rawDebts, vars.debtIndex, Math.Rounding.Down);
    rawColls = (rawDebts * PRECISION) / vars.price;
    bonusRawColls = (rawColls * vars.rebalanceBonusRatio) / FEE_PRECISION;
    // 奖励不能超过剩余抵押品
    if (bonusRawColls > vars.tickRawColls - rawColls) {
      bonusRawColls = vars.tickRawColls - rawColls;
    }
    uint256 collShares = _convertToCollShares(rawColls + bonusRawColls, vars.collIndex, Math.Rounding.Down);

    // 步骤3: 执行清算
    _liquidateTick(tick, collShares, debtShares, vars.price);
    
    // 步骤4: 更新全局份额（在 vars 中累积）
    vars.totalCollShares -= collShares;
    vars.totalDebtShares -= debtShares;
    vars.maxRawDebts -= rawDebts;
  }

  /// @dev 清算单个 tick（带坏账处理）
  /// @notice 执行清算操作，处理奖励和坏账
  ///
  /// ==================== 清算场景 ====================
  ///
  /// 场景1: 正常清算
  ///   - 抵押品足够覆盖债务和奖励
  ///   - 奖励从 tick 的抵押品中扣除
  ///
  /// 场景2: 需要储备金补贴
  ///   - tick 的抵押品不足以支付奖励
  ///   - 从储备金中补贴差额
  ///
  /// 场景3: 坏账
  ///   - 即使加上储备金，抵押品仍不足以覆盖债务
  ///   - 触发坏账重分配：增加 debtIndex，将坏账分摊给所有债务持有者
  ///
  /// @param tick 要清算的 tick
  /// @param vars 清算变量（会被修改）
  /// @return rawDebts 清算的债务量
  /// @return rawColls 获得的抵押品量
  /// @return bonusRawColls 奖励的抵押品量
  /// @return bonusFromReserve 从储备金补贴的奖励量
  function _liquidateTick(
    int16 tick,
    LiquidateVars memory vars
  ) internal virtual returns (uint256 rawDebts, uint256 rawColls, uint256 bonusRawColls, uint256 bonusFromReserve) {
    // 虚拟抵押品 = tick 抵押品 + 储备金
    uint256 virtualTickRawColls = vars.tickRawColls + vars.reservedRawColls;
    
    // 计算要清算的债务量
    rawDebts = vars.tickRawDebts;
    if (rawDebts > vars.maxRawDebts) rawDebts = vars.maxRawDebts;
    
    // 计算对应的抵押品量
    rawColls = (rawDebts * PRECISION) / vars.price;
    
    uint256 debtShares;
    uint256 collShares;
    
    if (rawDebts == vars.tickRawDebts) {
      // 完全清算: 使用全部债务份额
      debtShares = vars.tickDebtShares;
    } else {
      // 部分清算: 转换为份额
      debtShares = _convertToDebtShares(rawDebts, vars.debtIndex, Math.Rounding.Down);
    }
    
    if (virtualTickRawColls <= rawColls) {
      // ========== 场景3: 坏账 ==========
      // 即使加上储备金，抵押品仍不足以覆盖债务
      // 没有奖励，将触发坏账重分配
      rawColls = virtualTickRawColls;
      bonusFromReserve = vars.reservedRawColls;
      // 重新计算可清算的债务量
      rawDebts = (virtualTickRawColls * vars.price) / PRECISION;
      debtShares = _convertToDebtShares(rawDebts, vars.debtIndex, Math.Rounding.Down);
      collShares = vars.tickCollShares;
    } else {
      // ========== 场景1 或 场景2 ==========
      // 计算奖励
      bonusRawColls = (rawColls * vars.liquidateBonusRatio) / FEE_PRECISION;
      uint256 rawCollWithBonus = bonusRawColls + rawColls;
      
      // 如果总量超过虚拟抵押品，截断
      if (rawCollWithBonus > virtualTickRawColls) {
        rawCollWithBonus = virtualTickRawColls;
        bonusRawColls = rawCollWithBonus - rawColls;
      }
      
      // 判断是否需要储备金补贴
      if (rawCollWithBonus >= vars.tickRawColls) {
        // 场景2: 需要储备金补贴
        bonusFromReserve = rawCollWithBonus - vars.tickRawColls;
        collShares = vars.tickCollShares;
      } else {
        // 场景1: 正常清算
        collShares = _convertToCollShares(rawCollWithBonus, vars.collIndex, Math.Rounding.Down);
      }
    }

    // 扣除储备金
    vars.reservedRawColls -= bonusFromReserve;
    
    // 检查是否需要坏账重分配
    if (collShares == vars.tickCollShares && debtShares < vars.tickDebtShares) {
      // ========== 坏账重分配 ==========
      // 抵押品已全部清算，但债务未完全清算
      // 剩余债务 = 坏账，需要分摊给所有债务持有者
      uint256 rawBadDebt = _convertToRawDebt(vars.tickDebtShares - debtShares, vars.debtIndex, Math.Rounding.Down);
      debtShares = vars.tickDebtShares;  // 清算全部债务份额
      
      // 更新全局份额
      vars.totalCollShares -= collShares;
      vars.totalDebtShares -= debtShares;
      
      // 增加债务索引，将坏账分摊给所有债务持有者
      // 新索引 = 旧索引 + (坏账 × E96 / 剩余债务份额)
      vars.debtIndex += (rawBadDebt * E96) / vars.totalDebtShares;
    } else {
      // 正常更新全局份额
      vars.totalCollShares -= collShares;
      vars.totalDebtShares -= debtShares;
    }
    
    // 更新剩余可用债务量
    vars.maxRawDebts -= rawDebts;
    
    // 执行清算（更新树节点）
    _liquidateTick(tick, collShares, debtShares, vars.price);
  }

  /// @dev 更新抵押品和债务索引（抽象函数）
  /// @notice 子合约必须实现此函数
  /// @return newCollIndex 更新后的抵押品索引
  /// @return newDebtIndex 更新后的债务索引
  function _updateCollAndDebtIndex() internal virtual returns (uint256 newCollIndex, uint256 newDebtIndex);

  /// @dev 计算协议费用（抽象函数）
  /// @notice 子合约必须实现此函数
  /// @param rawColl 涉及的抵押品数量
  /// @return fees 协议费用
  function _deductProtocolFees(int256 rawColl) internal view virtual returns (uint256 fees);

  /// @dev 预留存储空间，允许未来版本添加新变量
  uint256[50] private __gap;
}
