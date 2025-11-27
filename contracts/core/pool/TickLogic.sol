// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { WordCodec } from "../../common/codec/WordCodec.sol";
import { TickBitmap } from "../../libraries/TickBitmap.sol";
import { TickMath } from "../../libraries/TickMath.sol";
import { PoolStorage } from "./PoolStorage.sol";

/// @title TickLogic - Tick 逻辑合约
/// @notice 实现 Tick 系统的核心逻辑，包括树节点管理、仓位分配和清算
/// @dev Tick 系统用于按债务比率对仓位进行分组，便于高效的再平衡和清算操作
///
/// ==================== Tick 系统概述 ====================
///
/// Tick 是什么？
/// - Tick 是债务比率的离散化表示，类似于 Uniswap V3 的价格刻度
/// - 每个 tick 对应一个债务比率范围
/// - 仓位根据其债务比率被分配到对应的 tick
///
/// 为什么需要 Tick？
/// - 高效的再平衡: 可以批量处理同一 tick 的所有仓位
/// - 高效的清算: 从最高 tick（最高风险）开始清算
/// - 节省 gas: 不需要遍历所有仓位
///
/// 树节点 (TickTreeNode) 的作用:
/// - 追踪再平衡/清算后仓位的变化
/// - 使用"懒更新"机制，只在需要时才更新仓位数据
/// - 通过比率链（ratio chain）计算仓位的实际份额
///
/// ==================== 数据结构 ====================
///
/// tickBitmap: 位图，标记哪些 tick 有债务
/// tickData: tick -> 当前树节点 ID
/// tickTreeData: 节点 ID -> 节点数据 (metadata + value)
///
/// 树节点的 metadata 布局:
/// | parent (48) | tick (16) | collRatio (64) | debtRatio (64) |
///
/// 树节点的 value 布局:
/// | collShare (128) | debtShare (128) |
///
abstract contract TickLogic is PoolStorage {
  using TickBitmap for mapping(int8 => uint256);
  using WordCodec for bytes32;

  /*************
   * 常量定义 *
   *************/

  /// @dev TickTreeNode.metadata 中各字段的位偏移量
  /// metadata 用于存储节点的元信息和比率
  uint256 private constant PARENT_OFFSET = 0;       // 父节点 ID (48 bits) - 指向上一个节点
  uint256 private constant TICK_OFFSET = 48;        // tick 值 (16 bits) - 此节点的原始 tick
  uint256 private constant COLL_RATIO_OFFSET = 64;  // 抵押品比率 (64 bits) - 相对父节点的比率 (×2^60)
  uint256 private constant DEBT_RATIO_OFFSET = 128; // 债务比率 (64 bits) - 相对父节点的比率 (×2^60)

  /// @dev TickTreeNode.value 中各字段的位偏移量
  /// value 用于存储节点的份额数据
  uint256 internal constant COLL_SHARE_OFFSET = 0;   // 抵押品份额 (128 bits)
  uint256 internal constant DEBT_SHARE_OFFSET = 128; // 债务份额 (128 bits)

  /// @dev 树压缩角色标识符
  /// 拥有此角色的地址可以调用 getRootNodeAndCompress 来压缩过长的节点链
  bytes32 public constant TREE_COMPRESS_ROLE = keccak256("TREE_COMPRESS_ROLE");

  /***************
   * 构造函数 *
   ***************/

  /// @dev 初始化 Tick 逻辑层
  /// @notice 设置初始状态:
  ///   - 下一个树节点 ID 从 1 开始（0 表示无节点）
  ///   - 顶部 tick 设为最小值（表示没有债务）
  function __TickLogic_init() internal onlyInitializing {
    _updateNextTreeNodeId(1);           // 节点 ID 从 1 开始
    _updateTopTick(type(int16).min);    // 初始无债务，顶部 tick 为最小值
  }

  /************************
   * 受限函数 *
   ************************/

  /// @notice 获取根节点并压缩路径（外部接口）
  /// @dev 仅 TREE_COMPRESS_ROLE 角色可调用
  /// 
  /// 用途: 当节点链过长时，可以调用此函数压缩路径
  /// 压缩后，所有中间节点都直接指向根节点，减少后续查询的 gas 消耗
  ///
  /// @param node 起始节点 ID
  /// @return root 根节点 ID
  /// @return collRatio 累积抵押品比率（×2^60）
  /// @return debtRatio 累积债务比率（×2^60）
  function getRootNodeAndCompress(
    uint256 node
  ) external onlyRole(TREE_COMPRESS_ROLE) returns (uint256 root, uint256 collRatio, uint256 debtRatio) {
    (root, collRatio, debtRatio) = _getRootNodeAndCompress(node);
  }

  /**********************
   * 内部函数 *
   **********************/

  /// @dev 获取给定树节点的根节点（只读版本）
  /// @notice 沿着父节点链向上遍历，累积比率，直到找到根节点（parent == 0）
  ///
  /// 比率累积原理:
  /// - 每个节点存储相对于父节点的比率
  /// - 实际比率 = 节点比率 × 父节点比率 × 祖父节点比率 × ...
  /// - 使用定点数运算，比率以 2^60 为基准
  ///
  /// 示例:
  /// - 节点 A 的 collRatio = 0.8 × 2^60
  /// - 节点 B (A的父节点) 的 collRatio = 0.9 × 2^60
  /// - A 的实际 collRatio = 0.8 × 0.9 = 0.72 × 2^60
  ///
  /// @param node 给定树节点的 ID
  /// @return root 根节点 ID
  /// @return collRatio 累积抵押品比率（×2^60）
  /// @return debtRatio 累积债务比率（×2^60）
  function _getRootNode(uint256 node) internal view returns (uint256 root, uint256 collRatio, uint256 debtRatio) {
    // 初始化比率为 1.0 (= 2^60)
    collRatio = E60;
    debtRatio = E60;
    
    // 沿父节点链向上遍历
    while (true) {
      bytes32 metadata = tickTreeData[node].metadata;
      uint256 parent = metadata.decodeUint(PARENT_OFFSET, 48);
      
      // 累积比率: newRatio = currentRatio × nodeRatio / 2^60
      collRatio = (collRatio * metadata.decodeUint(COLL_RATIO_OFFSET, 64)) >> 60;
      debtRatio = (debtRatio * metadata.decodeUint(DEBT_RATIO_OFFSET, 64)) >> 60;
      
      // 如果没有父节点，说明已到达根节点
      if (parent == 0) break;
      node = parent;
    }
    root = node;
  }

  /// @dev 获取根节点并压缩路径（带状态修改）
  /// @notice 此函数不仅返回根节点和比率，还会压缩节点链
  ///
  /// 路径压缩原理:
  /// 压缩前: A -> B -> C -> D (根节点)
  /// 压缩后: A -> D, B -> D, C -> D
  ///
  /// 压缩后每个节点直接指向根节点，并存储累积比率
  /// 这样后续查询只需要一次跳转，大大减少 gas 消耗
  ///
  /// 实现步骤:
  /// 1. 第一次遍历: 找到根节点，使用 transient storage 记录路径
  /// 2. 第二次遍历: 从根节点向下，更新每个节点的父指针和累积比率
  ///
  /// @param node 起始节点 ID
  /// @return root 根节点 ID
  /// @return collRatio 累积抵押品比率（×2^60）
  /// @return debtRatio 累积债务比率（×2^60）
  function _getRootNodeAndCompress(uint256 node) internal returns (uint256 root, uint256 collRatio, uint256 debtRatio) {
    uint256 depth;
    bytes32 metadata;
    root = node;
    
    // 第一阶段: 向上遍历找到根节点，同时记录路径
    while (true) {
      // 使用 transient storage (EIP-1153) 临时存储路径
      // tstore(key, value) - 存储到 transient storage
      // 这里用 depth 作为 key，root 作为 value
      assembly {
        tstore(depth, root)
        depth := add(depth, 1)
      }
      metadata = tickTreeData[root].metadata;
      uint256 parent = metadata.decodeUint(PARENT_OFFSET, 48);
      if (parent == 0) break;  // 找到根节点
      root = parent;
    }
    
    // 获取根节点的比率作为起始值
    metadata = tickTreeData[root].metadata;
    collRatio = metadata.decodeUint(COLL_RATIO_OFFSET, 64);
    debtRatio = metadata.decodeUint(DEBT_RATIO_OFFSET, 64);
    
    // 第二阶段: 从根节点向下，更新每个节点
    if (depth > 1) {
      for (uint256 i = depth - 2; ; --i) {
        // 从 transient storage 读取节点 ID
        // tload(key) - 从 transient storage 读取
        assembly {
          node := tload(i)
        }
        metadata = tickTreeData[node].metadata;
        
        // 累积比率
        collRatio = (collRatio * metadata.decodeUint(COLL_RATIO_OFFSET, 64)) >> 60;
        debtRatio = (debtRatio * metadata.decodeUint(DEBT_RATIO_OFFSET, 64)) >> 60;
        
        // 更新节点: 直接指向根节点，存储累积比率
        metadata = metadata.insertUint(root, PARENT_OFFSET, 48);
        metadata = metadata.insertUint(collRatio, COLL_RATIO_OFFSET, 64);
        metadata = metadata.insertUint(debtRatio, DEBT_RATIO_OFFSET, 64);
        tickTreeData[node].metadata = metadata;
        
        if (i == 0) break;
      }
    }
  }

  /// @dev 创建新的树节点
  /// @notice 为指定的 tick 创建一个新的树节点
  ///
  /// 新节点的初始状态:
  /// - parent = 0 (无父节点，自己就是根节点)
  /// - tick = 传入的 tick 值
  /// - collRatio = 1.0 (= 2^60)
  /// - debtRatio = 1.0 (= 2^60)
  /// - collShare = 0
  /// - debtShare = 0
  ///
  /// @param tick 此树节点所属的 tick
  /// @return node 创建的树节点 ID
  function _newTickTreeNode(int16 tick) internal returns (uint48 node) {
    unchecked {
      // 分配新的节点 ID
      node = _getNextTreeNodeId();
      _updateNextTreeNodeId(node + 1);
    }
    // 将此节点设为该 tick 的当前节点
    tickData[tick] = node;

    // 初始化节点元数据
    bytes32 metadata = bytes32(0);
    metadata = metadata.insertInt(tick, TICK_OFFSET, 16);      // 记录 tick 值
    metadata = metadata.insertUint(E60, COLL_RATIO_OFFSET, 64); // 抵押品比率 = 1.0
    metadata = metadata.insertUint(E60, DEBT_RATIO_OFFSET, 64); // 债务比率 = 1.0
    tickTreeData[node].metadata = metadata;
    // value 默认为 0，表示 collShare = 0, debtShare = 0
  }

  /// @dev 计算给定抵押品和债务对应的 tick
  /// @notice 根据债务比率 (debts/colls) 计算对应的 tick
  ///
  /// Tick 与债务比率的关系:
  /// - tick 越大，对应的债务比率越高
  /// - tick 越小，对应的债务比率越低
  /// - tick = 0 对应某个基准比率 (ZERO_TICK_SCALED_RATIO)
  ///
  /// 计算逻辑:
  /// 1. 计算缩放后的比率: ratio = debts × ZERO_TICK_SCALED_RATIO / colls
  /// 2. 使用 TickMath 库找到对应的 tick
  /// 3. 确保 tick 在有效范围内 [MIN_TICK, MAX_TICK]
  /// 4. 向上取整: 如果 getRatioAtTick(tick) < ratio，则 tick++
  ///
  /// @param colls 抵押品份额
  /// @param debts 债务份额
  /// @return tick 满足 getRatioAtTick(tick) >= debts/colls 的最小 tick
  function _getTick(uint256 colls, uint256 debts) internal pure returns (int256 tick) {
    // 计算缩放后的比率
    uint256 ratio = (debts * TickMath.ZERO_TICK_SCALED_RATIO) / colls;
    
    // 获取对应的 tick（可能略小于实际需要的 tick）
    (tick, ) = TickMath.getTickAtRatio(ratio);
    
    // 确保 tick 不小于最小值
    if (tick < TickMath.MIN_TICK) {
      tick = TickMath.MIN_TICK;
    }
    
    // 向上取整: 确保 getRatioAtTick(tick) >= ratio
    uint256 ratioAtTick = TickMath.getRatioAtTick(tick);
    unchecked {
      if (ratioAtTick < ratio) tick++;
    }
    
    // 确保 tick 不大于最大值
    if (tick > TickMath.MAX_TICK) {
      tick = TickMath.MAX_TICK;
    }
  }

  /// @dev 获取或创建 tick 对应的树节点
  /// @notice 如果 tick 已有节点则返回，否则创建新节点
  /// @param tick 目标 tick
  /// @return node 树节点 ID
  function _getOrCreateTickNode(int256 tick) internal returns (uint48 node) {
    node = tickData[tick];
    if (node == 0) {
      // tick 还没有节点，创建一个新的
      node = _newTickTreeNode(int16(tick));
    }
  }

  /// @dev 将仓位添加到对应的 tick
  /// @notice 根据仓位的债务比率，将其分配到合适的 tick
  ///
  /// 操作步骤:
  /// 1. 检查债务是否满足最小要求
  /// 2. 计算仓位应该属于哪个 tick
  /// 3. 获取或创建该 tick 的树节点
  /// 4. 更新节点的份额数据
  /// 5. 如果是该 tick 的第一笔债务，在位图中标记
  /// 6. 如果新 tick 大于当前顶部 tick，更新顶部 tick
  ///
  /// @param colls 抵押品份额
  /// @param debts 债务份额
  /// @param checkDebts 是否检查债务最小值（内部调用时可能跳过检查）
  /// @return tick 仓位所属的 tick
  /// @return node 对应的树节点 ID
  function _addPositionToTick(
    uint256 colls,
    uint256 debts,
    bool checkDebts
  ) internal returns (int256 tick, uint48 node) {
    // 只有有债务的仓位才需要分配到 tick
    if (debts > 0) {
      // 步骤1: 检查债务最小值
      if (checkDebts && int256(debts) < MIN_DEBT) {
        revert ErrorDebtTooSmall();
      }

      // 步骤2: 计算目标 tick
      tick = _getTick(colls, debts);
      
      // 步骤3: 获取或创建树节点
      node = _getOrCreateTickNode(tick);
      
      // 步骤4: 更新节点的份额数据
      bytes32 value = tickTreeData[node].value;
      uint256 newColls = value.decodeUint(COLL_SHARE_OFFSET, 128) + colls;
      uint256 newDebts = value.decodeUint(DEBT_SHARE_OFFSET, 128) + debts;
      value = value.insertUint(newColls, COLL_SHARE_OFFSET, 128);
      value = value.insertUint(newDebts, DEBT_SHARE_OFFSET, 128);
      tickTreeData[node].value = value;

      // 步骤5: 如果是 tick 的第一笔债务，在位图中标记
      // newDebts == debts 说明之前 tick 的债务为 0
      if (newDebts == debts) {
        tickBitmap.flipTick(int16(tick));  // 0 -> 1，标记此 tick 有债务
      }

      // 步骤6: 更新顶部 tick（如果需要）
      // 顶部 tick 是有债务的最大 tick，用于快速定位高风险仓位
      if (tick > _getTopTick()) {
        _updateTopTick(int16(tick));
      }
    }
    // 如果 debts == 0，返回默认值 tick = 0, node = 0
  }

  /// @dev 从 tick 中移除仓位
  /// @notice 当仓位被修改或关闭时，需要从原来的 tick 中移除
  ///
  /// 操作步骤:
  /// 1. 从节点的份额中减去仓位的份额
  /// 2. 如果 tick 的债务变为 0，在位图中取消标记
  /// 3. 如果被移除的是顶部 tick，重新计算顶部 tick
  ///
  /// @param position 要移除的仓位信息
  function _removePositionFromTick(PositionInfo memory position) internal {
    // nodeId == 0 表示仓位没有债务，不在任何 tick 中
    if (position.nodeId == 0) return;

    // 步骤1: 更新节点份额
    bytes32 value = tickTreeData[position.nodeId].value;
    uint256 oldDebts = value.decodeUint(DEBT_SHARE_OFFSET, 128);
    uint256 newColls = value.decodeUint(COLL_SHARE_OFFSET, 128) - position.colls;
    uint256 newDebts = oldDebts - position.debts;
    value = value.insertUint(newColls, COLL_SHARE_OFFSET, 128);
    value = value.insertUint(newDebts, DEBT_SHARE_OFFSET, 128);
    tickTreeData[position.nodeId].value = value;

    // 步骤2 & 3: 如果 tick 的债务变为 0
    if (newDebts == 0 && oldDebts > 0) {
      // 从节点元数据中获取 tick 值
      int16 tick = int16(tickTreeData[position.nodeId].metadata.decodeInt(TICK_OFFSET, 16));
      // 在位图中取消标记（1 -> 0）
      tickBitmap.flipTick(tick);

      // 如果这是顶部 tick，需要重新计算
      int16 topTick = _getTopTick();
      if (topTick == tick) {
        _resetTopTick(topTick);
      }
    }
  }

  /// @dev 检查清算/赎回后 tick 是否会移动
  /// @notice 用于赎回操作，确保赎回会改变 tick 的状态
  ///
  /// 移动条件:
  /// - tick 的债务变为 0（完全清空）
  /// - 或者剩余的债务比率对应不同的 tick
  ///
  /// @param tick 目标 tick
  /// @param liquidatedColl 将被清算的抵押品份额
  /// @param liquidatedDebt 将被清算的债务份额
  /// @return 如果 tick 会移动返回 true
  function _tickWillMove(int16 tick, uint256 liquidatedColl, uint256 liquidatedDebt) internal view returns (bool) {
    uint48 node = tickData[tick];
    bytes32 value = tickTreeData[node].value;
    uint256 tickColl = value.decodeUint(COLL_SHARE_OFFSET, 128);
    uint256 tickDebt = value.decodeUint(DEBT_SHARE_OFFSET, 128);
    
    // 计算清算后的剩余份额
    uint256 tickCollAfter = tickColl - liquidatedColl;
    uint256 tickDebtAfter = tickDebt - liquidatedDebt;
    
    // 如果债务变为 0，tick 一定会移动（被清空）
    if (tickDebtAfter == 0) return true;

    // 检查剩余份额是否对应不同的 tick
    int256 newTick = _getTick(tickCollAfter, tickDebtAfter);
    return newTick != int256(tick);
  }

  /// @dev 清算一个 tick（核心函数）
  /// @notice 处理 tick 的清算/再平衡/赎回操作
  ///
  /// ==================== 清算流程详解 ====================
  ///
  /// 背景: 当 tick 中的部分资金被清算时，需要:
  /// 1. 记录清算前后的比率变化（用于后续计算仓位的实际份额）
  /// 2. 将剩余资金移动到新的 tick（如果有剩余）
  /// 3. 更新位图和顶部 tick
  ///
  /// 树节点机制:
  /// - 清算前: tick -> nodeA (包含所有仓位的份额)
  /// - 清算后: tick -> nodeB (新节点，用于新仓位)
  ///           nodeA.parent -> nodeB 或新 tick 的节点
  ///           nodeA.ratio = 清算后/清算前 的比率
  ///
  /// 这样，旧仓位查询时会通过 nodeA 的比率自动计算出清算后的实际份额
  ///
  /// @param tick 要清算的 tick
  /// @param liquidatedColl 清算的抵押品份额
  /// @param liquidatedDebt 清算的债务份额
  /// @param price 当前价格（用于事件记录）
  function _liquidateTick(
    int16 tick,
    uint256 liquidatedColl,
    uint256 liquidatedDebt,
    uint256 price
  ) internal {
    uint48 node = tickData[tick];
    
    // 步骤1: 为此 tick 创建新的树节点
    // 新仓位将使用新节点，旧仓位仍然引用旧节点
    _newTickTreeNode(tick);
    
    // 步骤2: 先清除位图标记（稍后根据需要重新设置）
    tickBitmap.flipTick(tick);

    // 步骤3: 读取当前份额，计算清算后的剩余份额
    bytes32 value = tickTreeData[node].value;
    bytes32 metadata = tickTreeData[node].metadata;
    uint256 tickColl = value.decodeUint(COLL_SHARE_OFFSET, 128);
    uint256 tickDebt = value.decodeUint(DEBT_SHARE_OFFSET, 128);
    uint256 tickCollAfter = tickColl - liquidatedColl;
    uint256 tickDebtAfter = tickDebt - liquidatedDebt;

    // 步骤4: 计算并存储比率
    // 比率 = 清算后份额 / 清算前份额
    // 旧仓位的实际份额 = 原始份额 × 比率
    {
      uint256 collRatio = (tickCollAfter * E60) / tickColl;  // 抵押品比率
      uint256 debtRatio = (tickDebtAfter * E60) / tickDebt;  // 债务比率
      metadata = metadata.insertUint(collRatio, COLL_RATIO_OFFSET, 64);
      metadata = metadata.insertUint(debtRatio, DEBT_RATIO_OFFSET, 64);
    }

    // 步骤5: 处理剩余资金
    int256 newTick = type(int256).min;
    if (tickDebtAfter > 0) {
      // 部分清算: 剩余资金需要移动到新的 tick
      // 新 tick 可能与原 tick 相同或不同，取决于新的债务比率
      uint48 parentNode;
      (newTick, parentNode) = _addPositionToTick(tickCollAfter, tickDebtAfter, false);
      // 设置父节点，形成树结构
      metadata = metadata.insertUint(parentNode, PARENT_OFFSET, 48);
    }
    // 如果 tickDebtAfter == 0，说明完全清算，不需要设置父节点
    
    // 步骤6: 发出事件
    if (newTick == type(int256).min) {
      // 完全清算，新 tick 为最小值表示无债务
      emit TickMovement(tick, type(int16).min, tickCollAfter, tickDebtAfter, price);
    } else {
      emit TickMovement(tick, int16(newTick), tickCollAfter, tickDebtAfter, price);
    }

    // 步骤7: 更新顶部 tick（如果需要）
    int16 topTick = _getTopTick();
    if (topTick == tick && newTick != int256(tick)) {
      // 原顶部 tick 被清算且移动到了其他 tick，需要重新计算顶部 tick
      _resetTopTick(topTick);
    }
    
    // 步骤8: 保存更新后的元数据
    tickTreeData[node].metadata = metadata;
  }

  /// @dev 重置顶部 tick
  /// @notice 当顶部 tick 被清空时，需要找到新的顶部 tick
  ///
  /// 查找逻辑:
  /// - 从 oldTopTick - 1 开始向下搜索
  /// - 使用位图快速定位下一个有债务的 tick
  /// - 如果找不到，顶部 tick 设为最小值
  ///
  /// @param oldTopTick 之前的顶部 tick 值
  function _resetTopTick(int16 oldTopTick) internal {
    while (oldTopTick > type(int16).min) {
      bool hasDebt;
      // 在位图中查找下一个有债务的 tick
      (oldTopTick, hasDebt) = tickBitmap.nextDebtPositionWithinOneWord(oldTopTick - 1);
      if (hasDebt) break;  // 找到了
    }
    _updateTopTick(oldTopTick);
  }

  /// @dev 预留存储空间，允许未来版本添加新变量
  uint256[50] private __gap;
}
