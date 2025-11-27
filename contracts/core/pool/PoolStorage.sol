// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ERC721Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import { IPool } from "../../interfaces/IPool.sol";

import { WordCodec } from "../../common/codec/WordCodec.sol";
import { PoolConstant } from "./PoolConstant.sol";
import { PoolErrors } from "./PoolErrors.sol";

/// @title PoolStorage - 池存储合约
/// @notice 定义资金池的所有状态变量和基础操作函数
/// @dev 使用位打包技术将多个变量存储在单个 storage slot 中，节省 gas
abstract contract PoolStorage is ERC721Upgradeable, AccessControlUpgradeable, PoolConstant, PoolErrors {
  using WordCodec for bytes32;

  /*************
   * 常量定义 - miscData 字段偏移量 *
   *************/

  /// @dev miscData 中各字段的位偏移量
  /// miscData 布局: [借款标志|赎回标志|顶部tick|下一仓位ID|下一节点ID|最小债务比率|最大债务比率|最大赎回比率|保留]
  uint256 private constant BORROW_FLAG_OFFSET = 0;      // 借款暂停标志 (1 bit)
  uint256 private constant REDEEM_FLAG_OFFSET = 1;      // 赎回暂停标志 (1 bit)
  uint256 private constant TOP_TICK_OFFSET = 2;         // 顶部 tick (16 bits)
  uint256 private constant NEXT_POSITION_OFFSET = 18;   // 下一个仓位 ID (32 bits)
  uint256 private constant NEXT_NODE_OFFSET = 50;       // 下一个树节点 ID (48 bits)
  uint256 private constant MIN_DEBT_RATIO_OFFSET = 98;  // 最小债务比率 (60 bits)
  uint256 private constant MAX_DEBT_RATIO_OFFSET = 158; // 最大债务比率 (60 bits)
  uint256 private constant MAX_REDEEM_RATIO_OFFSET = 218; // 最大赎回比率 (30 bits)

  /// @dev rebalanceRatioData 中各字段的位偏移量
  /// 布局: [再平衡债务比率|再平衡奖励比率|清算债务比率|清算奖励比率|保留]
  uint256 private constant REBALANCE_DEBT_RATIO_OFFSET = 0;    // 再平衡触发债务比率 (60 bits)
  uint256 private constant REBALANCE_BONUS_RATIO_OFFSET = 60;  // 再平衡奖励比率 (30 bits)
  uint256 private constant LIQUIDATE_DEBT_RATIO_OFFSET = 90;   // 清算触发债务比率 (60 bits)
  uint256 private constant LIQUIDATE_BONUS_RATIO_OFFSET = 150; // 清算奖励比率 (30 bits)

  /// @dev indexData 中各字段的位偏移量
  /// 布局: [债务索引|抵押品索引]
  uint256 private constant DEBT_INDEX_OFFSET = 0;        // 债务索引 (128 bits)
  uint256 private constant COLLATERAL_INDEX_OFFSET = 128; // 抵押品索引 (128 bits)

  /// @dev sharesData 中各字段的位偏移量
  /// 布局: [债务份额|抵押品份额]
  uint256 private constant DEBT_SHARES_OFFSET = 0;        // 债务份额 (128 bits)
  uint256 private constant COLLATERAL_SHARES_OFFSET = 128; // 抵押品份额 (128 bits)

  /***********
   * 结构体定义 *
   ***********/

  /// @dev 仓位信息结构体
  /// @notice 存储单个仓位的核心数据
  /// @param tick 仓位初始所属的 tick（债务比率档位）
  /// @param nodeId 仓位初始所属的树节点 ID（如果为0，表示仓位只有抵押品没有债务）
  /// @param colls 仓位的抵押品份额
  /// @param debts 仓位的债务份额
  struct PositionInfo {
    int16 tick;      // 债务比率档位 (-32768 到 32767)
    uint48 nodeId;   // 树节点 ID（用于追踪再平衡/清算后的变化）
    uint96 colls;    // 抵押品份额（足够存储 86 bits）
    uint96 debts;    // 债务份额（足够存储 96 bits）
  }

  /// @dev Tick 树节点结构体
  /// @notice 用于追踪再平衡和赎回操作后仓位的变化
  /// @dev 编译器会将其打包成两个 uint256
  ///
  /// metadata 字段布局:
  /// | 字段       | 位数 | 起始位 | 说明                                    |
  /// |------------|------|--------|----------------------------------------|
  /// | parent     | 48   | 0      | 父节点 ID                               |
  /// | tick       | 16   | 48     | 此节点的原始 tick                        |
  /// | coll ratio | 64   | 64     | 相对父节点的抵押品份额比率 (实际比率 * 2^60) |
  /// | debt ratio | 64   | 128    | 相对父节点的债务份额比率 (实际比率 * 2^60)   |
  ///
  /// value 字段布局:
  /// | 字段       | 位数 | 起始位 | 说明                          |
  /// |------------|------|--------|------------------------------|
  /// | coll share | 128  | 0      | 再平衡/赎回前的原始抵押品份额   |
  /// | debt share | 128  | 128    | 再平衡/赎回前的原始债务份额     |
  struct TickTreeNode {
    bytes32 metadata;  // 节点元数据（父节点、tick、比率）
    bytes32 value;     // 节点值（原始份额）
  }

  /*********************
   * 状态变量 *
   *********************/

  /// @inheritdoc IPool
  /// @notice 抵押品代币地址
  /// @dev 用户存入的资产类型（如 WETH、WBTC 等）
  address public collateralToken;

  /// @inheritdoc IPool
  /// @notice 价格预言机地址
  /// @dev 用于获取抵押品相对于 fxUSD 的价格
  address public priceOracle;

  /// @dev miscData - 杂项数据存储槽
  /// @notice 使用位打包存储多个不相关的配置信息
  ///
  /// 字段布局 (从 LSB 到 MSB):
  /// | 字段           | 位数   | 说明                                    |
  /// |----------------|--------|----------------------------------------|
  /// | borrow flag    | 1 bit  | 借款暂停标志 (1=暂停)                    |
  /// | redeem flag    | 1 bit  | 赎回暂停标志 (1=暂停)                    |
  /// | top tick       | 16 bits| 有债务的最大 tick                        |
  /// | next position  | 32 bits| 下一个可用的仓位 ID                      |
  /// | next node      | 48 bits| 下一个可用的树节点 ID                    |
  /// | min debt ratio | 60 bits| 最小允许债务比率 (×1e18)                 |
  /// | max debt ratio | 60 bits| 最大允许债务比率 (×1e18)                 |
  /// | max redeem ratio| 30 bits| 每个 tick 的最大赎回比率 (×1e9)          |
  /// | reserved       | 8 bits | 保留位                                   |
  bytes32 private miscData;

  /// @dev rebalanceRatioData - 再平衡和清算比率数据
  /// @notice 存储再平衡和清算的触发条件和奖励参数
  ///
  /// 字段布局:
  /// | 字段                  | 位数   | 说明                           |
  /// |-----------------------|--------|-------------------------------|
  /// | rebalance debt ratio  | 60 bits| 触发再平衡的最小债务比率 (×1e18) |
  /// | rebalance bonus ratio | 30 bits| 再平衡奖励比率 (×1e9)           |
  /// | liquidate debt ratio  | 60 bits| 触发清算的最小债务比率 (×1e18)   |
  /// | liquidate bonus ratio | 30 bits| 清算奖励比率 (×1e9)             |
  /// | reserved              | 76 bits| 保留位                          |
  bytes32 private rebalanceRatioData;

  /// @dev indexData - 索引数据存储槽
  /// @notice 存储债务和抵押品的索引值，用于计算实际数量
  ///
  /// 索引机制说明:
  /// - 债务索引: 只增不减，初始值 2^96，最大 2^128-1
  ///   实际债务 = 债务份额 × 债务索引 / PRECISION
  /// - 抵押品索引: 只增不减，初始值 2^96，最大 2^128-1
  ///   实际抵押品 = 抵押品份额 × 抵押品索引 / PRECISION
  ///
  /// 字段布局:
  /// | 字段             | 位数    | 说明        |
  /// |------------------|---------|------------|
  /// | debt index       | 128 bits| 债务索引    |
  /// | collateral index | 128 bits| 抵押品索引  |
  bytes32 private indexData;

  /// @dev sharesData - 份额数据存储槽
  /// @notice 存储池的总债务份额和总抵押品份额
  ///
  /// 份额与实际数量的关系:
  /// - 总债务 = 债务份额 × 债务索引 / PRECISION
  /// - 总抵押品 = 抵押品份额 × 抵押品索引 / PRECISION
  ///
  /// 字段布局:
  /// | 字段              | 位数    | 说明         |
  /// |-------------------|---------|-------------|
  /// | debt shares       | 128 bits| 总债务份额   |
  /// | collateral shares | 128 bits| 总抵押品份额 |
  bytes32 private sharesData;

  /// @dev 仓位 ID 到仓位信息的映射
  /// @notice 存储每个仓位的详细信息
  mapping(uint256 => PositionInfo) public positionData;

  /// @dev 仓位 ID 到仓位元数据的映射
  /// @notice 存储仓位的额外信息（如开仓时间戳）
  /// 布局: [开仓时间戳 (40 bits) | 保留 (216 bits)]
  mapping(uint256 => bytes32) public positionMetadata;

  /// @dev Tick 位图
  /// @notice 高效存储哪些 tick 有债务
  /// @dev 使用位图可以快速查找有债务的 tick
  mapping(int8 => uint256) public tickBitmap;

  /// @dev Tick 到树节点 ID 的映射
  /// @notice 记录每个 tick 对应的当前树节点
  mapping(int256 => uint48) public tickData;

  /// @dev 树节点 ID 到树节点数据的映射
  /// @notice 存储树节点的完整信息
  mapping(uint256 => TickTreeNode) public tickTreeData;

  /// @notice 对手方池地址
  /// @dev 用于多空池配对（如 Long Pool 和 Short Pool）
  address public counterparty;

  /***************
   * 构造函数 *
   ***************/

  /// @dev 初始化存储层
  /// @param _collateralToken 抵押品代币地址
  /// @param _priceOracle 价格预言机地址
  function __PoolStorage_init(address _collateralToken, address _priceOracle) internal onlyInitializing {
    // _checkAddressNotZero(_collateralToken);

    collateralToken = _collateralToken;
    _updatePriceOracle(_priceOracle);
  }


  /*************************
   * 公共视图函数 *
   *************************/

  /// @inheritdoc AccessControlUpgradeable
  /// @notice 检查合约是否支持指定接口
  function supportsInterface(
    bytes4 interfaceId
  ) public view virtual override(AccessControlUpgradeable, ERC721Upgradeable) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  /// @inheritdoc IPool
  /// @notice 检查借款是否暂停
  /// @return 如果借款暂停返回 true
  function isBorrowPaused() external view returns (bool) {
    return _isBorrowPaused();
  }

  /// @inheritdoc IPool
  /// @notice 检查赎回是否暂停
  /// @return 如果赎回暂停返回 true
  function isRedeemPaused() external view returns (bool) {
    return _isRedeemPaused();
  }

  /// @inheritdoc IPool
  /// @notice 获取顶部 tick（有债务的最大 tick）
  /// @return 顶部 tick 值
  function getTopTick() external view returns (int16) {
    return _getTopTick();
  }

  /// @inheritdoc IPool
  /// @notice 获取下一个可用的仓位 ID
  /// @return 下一个仓位 ID
  function getNextPositionId() external view returns (uint32) {
    return _getNextPositionId();
  }

  /// @inheritdoc IPool
  /// @notice 获取下一个可用的树节点 ID
  /// @return 下一个树节点 ID
  function getNextTreeNodeId() external view returns (uint48) {
    return _getNextTreeNodeId();
  }

  /// @inheritdoc IPool
  /// @notice 获取债务比率范围
  /// @return 最小债务比率和最大债务比率（均乘以 1e18）
  function getDebtRatioRange() external view returns (uint256, uint256) {
    return _getDebtRatioRange();
  }

  /// @inheritdoc IPool
  /// @notice 获取每个 tick 的最大赎回比率
  /// @return 最大赎回比率（乘以 1e9）
  function getMaxRedeemRatioPerTick() external view returns (uint256) {
    return _getMaxRedeemRatioPerTick();
  }

  /// @inheritdoc IPool
  /// @notice 获取再平衡参数
  /// @return 再平衡触发债务比率和奖励比率
  function getRebalanceRatios() external view returns (uint256, uint256) {
    return _getRebalanceRatios();
  }

  /// @inheritdoc IPool
  /// @notice 获取清算参数
  /// @return 清算触发债务比率和奖励比率
  function getLiquidateRatios() external view returns (uint256, uint256) {
    return _getLiquidateRatios();
  }

  /// @inheritdoc IPool
  /// @notice 获取债务和抵押品索引
  /// @return 债务索引和抵押品索引
  function getDebtAndCollateralIndex() external view returns (uint256, uint256) {
    return _getDebtAndCollateralIndex();
  }

  /// @inheritdoc IPool
  /// @notice 获取债务和抵押品份额
  /// @return 总债务份额和总抵押品份额
  function getDebtAndCollateralShares() external view returns (uint256, uint256) {
    return _getDebtAndCollateralShares();
  }

  /**********************
   * 内部函数 *
   **********************/

  /// @dev 更新价格预言机地址
  /// @param newOracle 新的价格预言机地址
  function _updatePriceOracle(address newOracle) internal {
    // _checkAddressNotZero(newOracle);

    address oldOracle = priceOracle;
    priceOracle = newOracle;

    emit UpdatePriceOracle(oldOracle, newOracle);
  }

  /*************************************
   * miscData 操作函数 *
   *************************************/

  /// @dev 获取借款暂停状态
  /// @return 如果借款暂停返回 true
  function _isBorrowPaused() internal view returns (bool) {
    return miscData.decodeBool(BORROW_FLAG_OFFSET);
  }

  /// @dev 更新借款暂停状态
  /// @param status 新的暂停状态
  function _updateBorrowStatus(bool status) internal {
    miscData = miscData.insertBool(status, BORROW_FLAG_OFFSET);

    emit UpdateBorrowStatus(status);
  }

  /// @dev 获取赎回暂停状态
  /// @return 如果赎回暂停返回 true
  function _isRedeemPaused() internal view returns (bool) {
    return miscData.decodeBool(REDEEM_FLAG_OFFSET);
  }

  /// @dev 更新赎回暂停状态
  /// @param status 新的暂停状态
  function _updateRedeemStatus(bool status) internal {
    miscData = miscData.insertBool(status, REDEEM_FLAG_OFFSET);

    emit UpdateRedeemStatus(status);
  }

  /// @dev 获取顶部 tick 值
  /// @return 顶部 tick（有债务的最大 tick）
  function _getTopTick() internal view returns (int16) {
    return int16(miscData.decodeInt(TOP_TICK_OFFSET, 16));
  }

  /// @dev 更新顶部 tick
  /// @param tick 新的顶部 tick 值
  function _updateTopTick(int16 tick) internal {
    miscData = miscData.insertInt(tick, TOP_TICK_OFFSET, 16);
  }

  /// @dev 获取下一个可用的仓位 ID
  /// @return 下一个仓位 ID
  function _getNextPositionId() internal view returns (uint32) {
    return uint32(miscData.decodeUint(NEXT_POSITION_OFFSET, 32));
  }

  /// @dev 更新下一个仓位 ID
  /// @param id 新的仓位 ID
  function _updateNextPositionId(uint32 id) internal {
    miscData = miscData.insertUint(id, NEXT_POSITION_OFFSET, 32);
  }

  /// @dev 获取下一个可用的树节点 ID
  /// @return 下一个树节点 ID
  function _getNextTreeNodeId() internal view returns (uint48) {
    return uint48(miscData.decodeUint(NEXT_NODE_OFFSET, 48));
  }

  /// @dev 更新下一个树节点 ID
  /// @param id 新的树节点 ID
  function _updateNextTreeNodeId(uint48 id) internal {
    miscData = miscData.insertUint(id, NEXT_NODE_OFFSET, 48);
  }

  /// @dev 获取债务比率范围
  /// @return minDebtRatio 最小债务比率（×1e18）
  /// @return maxDebtRatio 最大债务比率（×1e18）
  function _getDebtRatioRange() internal view returns (uint256 minDebtRatio, uint256 maxDebtRatio) {
    bytes32 data = miscData;
    minDebtRatio = data.decodeUint(MIN_DEBT_RATIO_OFFSET, 60);
    maxDebtRatio = data.decodeUint(MAX_DEBT_RATIO_OFFSET, 60);
  }

  /// @dev 更新债务比率范围
  /// @param minDebtRatio 最小允许债务比率（×1e18）
  /// @param maxDebtRatio 最大允许债务比率（×1e18）
  function _updateDebtRatioRange(uint256 minDebtRatio, uint256 maxDebtRatio) internal {
    // _checkValueTooLarge(minDebtRatio, maxDebtRatio);
    // _checkValueTooLarge(maxDebtRatio, PRECISION);

    bytes32 data = miscData;
    data = data.insertUint(minDebtRatio, MIN_DEBT_RATIO_OFFSET, 60);
    miscData = data.insertUint(maxDebtRatio, MAX_DEBT_RATIO_OFFSET, 60);

    emit UpdateDebtRatioRange(minDebtRatio, maxDebtRatio);
  }

  /// @dev 获取每个 tick 的最大赎回比率
  /// @return 最大赎回比率（×1e9）
  function _getMaxRedeemRatioPerTick() internal view returns (uint256) {
    return miscData.decodeUint(MAX_REDEEM_RATIO_OFFSET, 30);
  }

  /// @dev 更新每个 tick 的最大赎回比率
  /// @param ratio 新的最大赎回比率（×1e9）
  function _updateMaxRedeemRatioPerTick(uint256 ratio) internal {
    // _checkValueTooLarge(ratio, FEE_PRECISION);

    miscData = miscData.insertUint(ratio, MAX_REDEEM_RATIO_OFFSET, 30);

    emit UpdateMaxRedeemRatioPerTick(ratio);
  }

  /***********************************************
   * rebalanceRatioData 操作函数 *
   ***********************************************/

  /// @dev 获取再平衡参数
  /// @return debtRatio 触发再平衡的最小债务比率（×1e18）
  /// @return bonusRatio 再平衡奖励比率（×1e9）
  function _getRebalanceRatios() internal view returns (uint256 debtRatio, uint256 bonusRatio) {
    bytes32 data = rebalanceRatioData;
    debtRatio = data.decodeUint(REBALANCE_DEBT_RATIO_OFFSET, 60);
    bonusRatio = data.decodeUint(REBALANCE_BONUS_RATIO_OFFSET, 30);
  }

  /// @dev 更新再平衡参数
  /// @param debtRatio 触发再平衡的最小债务比率（×1e18）
  /// @param bonusRatio 再平衡奖励比率（×1e9）
  function _updateRebalanceRatios(uint256 debtRatio, uint256 bonusRatio) internal {
    // _checkValueTooLarge(debtRatio, PRECISION);
    // _checkValueTooLarge(bonusRatio, FEE_PRECISION);

    bytes32 data = rebalanceRatioData;
    data = data.insertUint(debtRatio, REBALANCE_DEBT_RATIO_OFFSET, 60);
    rebalanceRatioData = data.insertUint(bonusRatio, REBALANCE_BONUS_RATIO_OFFSET, 30);

    emit UpdateRebalanceRatios(debtRatio, bonusRatio);
  }

  /// @dev 获取清算参数
  /// @return debtRatio 触发清算的最小债务比率（×1e18）
  /// @return bonusRatio 清算奖励比率（×1e9）
  function _getLiquidateRatios() internal view returns (uint256 debtRatio, uint256 bonusRatio) {
    bytes32 data = rebalanceRatioData;
    debtRatio = data.decodeUint(LIQUIDATE_DEBT_RATIO_OFFSET, 60);
    bonusRatio = data.decodeUint(LIQUIDATE_BONUS_RATIO_OFFSET, 30);
  }

  /// @dev 更新清算参数
  /// @param debtRatio 触发清算的最小债务比率（×1e18）
  /// @param bonusRatio 清算奖励比率（×1e9）
  function _updateLiquidateRatios(uint256 debtRatio, uint256 bonusRatio) internal {
    // _checkValueTooLarge(debtRatio, PRECISION);
    // _checkValueTooLarge(bonusRatio, FEE_PRECISION);

    bytes32 data = rebalanceRatioData;
    data = data.insertUint(debtRatio, LIQUIDATE_DEBT_RATIO_OFFSET, 60);
    rebalanceRatioData = data.insertUint(bonusRatio, LIQUIDATE_BONUS_RATIO_OFFSET, 30);

    emit UpdateLiquidateRatios(debtRatio, bonusRatio);
  }

  /**************************************
   * indexData 操作函数 *
   **************************************/

  /// @dev 获取债务和抵押品索引
  /// @return debtIndex 债务索引（用于计算实际债务）
  /// @return collIndex 抵押品索引（用于计算实际抵押品）
  function _getDebtAndCollateralIndex() internal view returns (uint256 debtIndex, uint256 collIndex) {
    bytes32 data = indexData;
    debtIndex = data.decodeUint(DEBT_INDEX_OFFSET, 128);
    collIndex = data.decodeUint(COLLATERAL_INDEX_OFFSET, 128);
  }

  /// @dev 更新债务索引
  /// @param index 新的债务索引
  function _updateDebtIndex(uint256 index) internal {
    indexData = indexData.insertUint(index, DEBT_INDEX_OFFSET, 128);

    emit DebtIndexSnapshot(index);
  }

  /// @dev 更新抵押品索引
  /// @param index 新的抵押品索引
  function _updateCollateralIndex(uint256 index) internal {
    indexData = indexData.insertUint(index, COLLATERAL_INDEX_OFFSET, 128);

    emit CollateralIndexSnapshot(index);
  }

  /**************************************
   * sharesData 操作函数 *
   **************************************/

  /// @dev 获取债务和抵押品份额
  /// @return debtShares 总债务份额
  /// @return collShares 总抵押品份额
  function _getDebtAndCollateralShares() internal view returns (uint256 debtShares, uint256 collShares) {
    bytes32 data = sharesData;
    debtShares = data.decodeUint(DEBT_SHARES_OFFSET, 128);
    collShares = data.decodeUint(COLLATERAL_SHARES_OFFSET, 128);
  }

  /// @dev 更新债务和抵押品份额
  /// @param debtShares 新的债务份额
  /// @param collShares 新的抵押品份额
  function _updateDebtAndCollateralShares(uint256 debtShares, uint256 collShares) internal {
    bytes32 data = sharesData;
    data = data.insertUint(debtShares, DEBT_SHARES_OFFSET, 128);
    sharesData = data.insertUint(collShares, COLLATERAL_SHARES_OFFSET, 128);
  }

  /// @dev 更新债务份额
  /// @param shares 新的债务份额
  function _updateDebtShares(uint256 shares) internal {
    sharesData = sharesData.insertUint(shares, DEBT_SHARES_OFFSET, 128);
  }

  /// @dev 更新抵押品份额
  /// @param shares 新的抵押品份额
  function _updateCollateralShares(uint256 shares) internal {
    sharesData = sharesData.insertUint(shares, COLLATERAL_SHARES_OFFSET, 128);
  }

  /*****************************************
   * counterparty 操作函数 *
   *****************************************/

  /// @dev 更新对手方池地址
  /// @param newCounterparty 新的对手方池地址
  function _updateCounterparty(address newCounterparty) internal {
    _checkAddressNotZero(newCounterparty);

    address oldCounterparty = counterparty;
    counterparty = newCounterparty;

    emit UpdateCounterparty(oldCounterparty, newCounterparty);
  }

  /**
   * @dev 预留存储空间，允许未来版本添加新变量而不影响继承链中的存储布局
   */
  uint256[39] private __gap;
}
