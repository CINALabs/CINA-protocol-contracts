// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { IPool } from "../../interfaces/IPool.sol";
import { IPriceOracle } from "../../price-oracle/interfaces/IPriceOracle.sol";

import { WordCodec } from "../../common/codec/WordCodec.sol";
import { Math } from "../../libraries/Math.sol";
import { TickLogic } from "./TickLogic.sol";

/// @title PositionLogic - 仓位逻辑合约
/// @notice 实现仓位管理的核心逻辑，包括仓位创建、查询和份额转换
/// @dev 仓位是用户在池中的借贷状态，包含抵押品份额和债务份额
///
/// 核心概念:
/// - 原始数量 (raw): 实际的代币数量
/// - 份额 (shares): 用于内部计算的标准化数量
/// - 索引 (index): 份额与原始数量之间的转换系数
///
/// 转换公式:
/// - 抵押品: rawColl = collShares * E96 / collIndex
/// - 债务: rawDebt = debtShares * debtIndex / E96
abstract contract PositionLogic is TickLogic {
  using WordCodec for bytes32;

  /***************
   * 构造函数 *
   ***************/

  /// @dev 初始化仓位逻辑层
  /// @notice 设置初始仓位 ID 为 1
  function __PositionLogic_init() internal onlyInitializing {
    _updateNextPositionId(1);
  }

  /*************************
   * 公共视图函数 *
   *************************/

  /// @inheritdoc IPool
  /// @notice 获取仓位的实际抵押品和债务数量
  /// @param tokenId 仓位 ID（NFT token ID）
  /// @return rawColls 实际抵押品数量
  /// @return rawDebts 实际债务数量
  ///
  /// 计算步骤:
  /// 1. 获取仓位的份额数据
  /// 2. 如果仓位有债务（nodeId > 0），应用树节点的比率调整
  /// 3. 使用索引将份额转换为实际数量
  function getPosition(uint256 tokenId) public view returns (uint256 rawColls, uint256 rawDebts) {
    // 步骤1: 获取仓位的份额数据
    PositionInfo memory position = positionData[tokenId];
    rawColls = position.colls;
    rawDebts = position.debts;
    
    // 步骤2: 如果仓位有债务，应用树节点比率
    // 这是因为再平衡/清算可能改变了仓位的实际份额
    if (position.nodeId > 0) {
      (, uint256 collRatio, uint256 debtRatio) = _getRootNode(position.nodeId);
      rawColls = (rawColls * collRatio) >> 60;  // 应用抵押品比率
      rawDebts = (rawDebts * debtRatio) >> 60;  // 应用债务比率
    }

    // 步骤3: 将份额转换为实际数量
    (uint256 debtIndex, uint256 collIndex) = _getDebtAndCollateralIndex();
    rawColls = _convertToRawColl(rawColls, collIndex, Math.Rounding.Down);
    rawDebts = _convertToRawDebt(rawDebts, debtIndex, Math.Rounding.Down);
  }

  /// @inheritdoc IPool
  /// @notice 获取仓位的债务比率
  /// @param tokenId 仓位 ID
  /// @return debtRatio 债务比率（×1e18）
  ///
  /// 计算公式: debtRatio = rawDebts / (rawColls * price)
  /// 其中 price 是抵押品相对于 fxUSD 的价格
  function getPositionDebtRatio(uint256 tokenId) external view returns (uint256 debtRatio) {
    (uint256 rawColls, uint256 rawDebts) = getPosition(tokenId);
    // 获取锚定价格（price 精度和 ratio 精度都是 1e18）
    (uint256 price, , ) = IPriceOracle(priceOracle).getPrice();
    if (rawColls == 0) return 0;
    // debtRatio = rawDebts * 1e18 * 1e18 / (price * rawColls)
    return (rawDebts * PRECISION * PRECISION) / (price * rawColls);
  }

  /// @inheritdoc IPool
  /// @notice 获取池的总抵押品数量
  /// @return 总抵押品的原始数量
  function getTotalRawCollaterals() external view returns (uint256) {
    (, uint256 totalColls) = _getDebtAndCollateralShares();
    (, uint256 collIndex) = _getDebtAndCollateralIndex();
    return _convertToRawColl(totalColls, collIndex, Math.Rounding.Down);
  }

  /// @inheritdoc IPool
  /// @notice 获取池的总债务数量
  /// @return 总债务的原始数量
  function getTotalRawDebts() external view returns (uint256) {
    (uint256 totalDebts, ) = _getDebtAndCollateralShares();
    (uint256 debtIndex, ) = _getDebtAndCollateralIndex();
    return _convertToRawDebt(totalDebts, debtIndex, Math.Rounding.Down);
  }

  /**********************
   * 内部函数 *
   **********************/

  /// @dev 铸造新仓位
  /// @param owner 仓位所有者地址
  /// @return positionId 新仓位的 ID
  ///
  /// 操作:
  /// 1. 获取并递增下一个仓位 ID
  /// 2. 记录开仓时间戳
  /// 3. 铸造 NFT 给所有者
  function _mintPosition(address owner) internal returns (uint32 positionId) {
    unchecked {
      positionId = _getNextPositionId();
      _updateNextPositionId(positionId + 1);
    }

    // 记录开仓时间戳（存储在低 40 位）
    positionMetadata[positionId] = bytes32(0).insertUint(block.timestamp, 0, 40);
    // 铸造 NFT
    _mint(owner, positionId);
  }

  /// @dev 获取并更新仓位数据
  /// @param tokenId 仓位 ID
  /// @return position 更新后的仓位信息
  ///
  /// 此函数会:
  /// 1. 读取仓位数据
  /// 2. 如果仓位有债务，压缩树节点路径并更新份额
  /// 3. 将更新后的数据写回存储
  ///
  /// 这是一个"懒更新"机制，只在需要时才更新仓位数据
  function _getAndUpdatePosition(uint256 tokenId) internal returns (PositionInfo memory position) {
    position = positionData[tokenId];
    if (position.nodeId > 0) {
      // 获取根节点并压缩路径
      (uint256 root, uint256 collRatio, uint256 debtRatio) = _getRootNodeAndCompress(position.nodeId);
      // 应用比率更新份额
      position.colls = uint96((position.colls * collRatio) >> 60);
      position.debts = uint96((position.debts * debtRatio) >> 60);
      position.nodeId = uint32(root);
      // 写回存储
      positionData[tokenId] = position;
    }
  }

  /// @dev 将原始抵押品数量转换为抵押品份额
  /// @param raw 原始抵押品数量
  /// @param index 抵押品索引
  /// @param rounding 舍入方式
  /// @return shares 抵押品份额
  ///
  /// 公式: shares = raw * index / E96
  function _convertToCollShares(
    uint256 raw,
    uint256 index,
    Math.Rounding rounding
  ) internal pure returns (uint256 shares) {
    shares = Math.mulDiv(raw, index, E96, rounding);
  }

  /// @dev 将原始债务数量转换为债务份额
  /// @param raw 原始债务数量
  /// @param index 债务索引
  /// @param rounding 舍入方式
  /// @return shares 债务份额
  ///
  /// 公式: shares = raw * E96 / index
  function _convertToDebtShares(
    uint256 raw,
    uint256 index,
    Math.Rounding rounding
  ) internal pure returns (uint256 shares) {
    shares = Math.mulDiv(raw, E96, index, rounding);
  }

  /// @dev 将抵押品份额转换为原始抵押品数量
  /// @param shares 抵押品份额
  /// @param index 抵押品索引
  /// @param rounding 舍入方式
  /// @return raw 原始抵押品数量
  ///
  /// 公式: raw = shares * E96 / index
  function _convertToRawColl(
    uint256 shares,
    uint256 index,
    Math.Rounding rounding
  ) internal pure returns (uint256 raw) {
    raw = Math.mulDiv(shares, E96, index, rounding);
  }

  /// @dev 将债务份额转换为原始债务数量
  /// @param shares 债务份额
  /// @param index 债务索引
  /// @param rounding 舍入方式
  /// @return raw 原始债务数量
  ///
  /// 公式: raw = shares * index / E96
  function _convertToRawDebt(
    uint256 shares,
    uint256 index,
    Math.Rounding rounding
  ) internal pure returns (uint256 raw) {
    raw = Math.mulDiv(shares, index, E96, rounding);
  }

  /**
   * @dev 预留存储空间，允许未来版本添加新变量
   */
  uint256[50] private __gap;
}
