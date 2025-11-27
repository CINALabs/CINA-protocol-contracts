// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { IPriceOracle } from "../../price-oracle/interfaces/IPriceOracle.sol";
import { IPoolConfiguration } from "../../interfaces/IPoolConfiguration.sol";
import { IShortPool } from "../../interfaces/IShortPool.sol";
import { ILongPool } from "../../interfaces/ILongPool.sol";

import { Math } from "../../libraries/Math.sol";
import { BasePool } from "../pool/BasePool.sol";

/// @title ShortPool - 空头池合约
/// @notice 实现做空机制的核心池合约
/// @dev 继承自 BasePool，实现空头特有的资金费率和清算逻辑
///
/// ==================== 空头池概述 ====================
///
/// 空头池允许用户:
/// 1. 存入 fxUSD 作为抵押品
/// 2. 借出抵押品代币（如 ETH、wstETH）
/// 3. 通过做空获利（当抵押品价格下跌时）
///
/// 与多头池的区别:
/// - 多头池: 存入抵押品，借出 fxUSD
/// - 空头池: 存入 fxUSD，借出抵押品代币
///
/// 信用票据 (Credit Note):
/// - 代表用户在空头池中的借款凭证
/// - 可用于赎回抵押品
///
contract ShortPool is BasePool, IShortPool {
  /**********
   * 错误定义 *
   **********/

  /// @dev 当池已被终止时抛出
  /// @notice 池被终止后，所有操作都将失败
  error ErrorPoolKilled();

  /*********************
   * 存储变量 *
   *********************/

  /// @inheritdoc IShortPool
  /// @notice 债务代币地址（用户借出的代币）
  address public debtToken;

  /// @inheritdoc IShortPool
  /// @notice 信用票据合约地址
  /// @dev 信用票据代表用户的借款凭证
  address public creditNote;

  /// @notice 上次资金费率更新的时间戳
  /// @dev 用于计算资金费用的时间间隔
  uint256 public lastFundingTimestamp;

  /// @notice 池是否已被终止
  /// @dev 当池抵押不足时，可以被终止以保护系统
  bool public isKilled;

  /***************
   * 构造函数 *
   ***************/

  /// @notice 构造函数
  /// @param _poolManager PoolManager 合约地址
  /// @param _configuration PoolConfiguration 合约地址
  constructor(address _poolManager, address _configuration) BasePool(_poolManager, _configuration) {}

  /// @notice 初始化函数（代理模式）
  /// @dev 只能调用一次，设置初始状态
  /// @param admin 管理员地址
  /// @param name_ ERC721 代币名称（仓位 NFT）
  /// @param symbol_ ERC721 代币符号
  /// @param _priceOracle 价格预言机地址
  /// @param _debtToken 债务代币地址
  /// @param _creditNote 信用票据合约地址
  function initialize(
    address admin,
    string memory name_,
    string memory symbol_,
    address _priceOracle,
    address _debtToken,
    address _creditNote
  ) external initializer {
    __Context_init();
    __ERC165_init();
    __ERC721_init(name_, symbol_);
    __AccessControl_init();

    // 空头池的抵押品是 fxUSD
    __PoolStorage_init(fxUSD, _priceOracle);
    __TickLogic_init();
    __PositionLogic_init();
    __BasePool_init();

    _grantRole(DEFAULT_ADMIN_ROLE, admin);

    debtToken = _debtToken;
    creditNote = _creditNote;
  }

  /*************************
   * 公共视图函数 *
   *************************/

  /// @inheritdoc IShortPool
  /// @notice 检查池是否抵押不足
  /// @dev 当总债务价值 >= 总抵押品价值时，池处于抵押不足状态
  /// @return underCollateral 是否抵押不足
  /// @return shortfall 缺口金额（如果抵押不足）
  function isUnderCollateral() external onlyPoolManager returns (bool underCollateral, uint256 shortfall) {
    // 更新索引
    (uint256 debtIndex, uint256 collIndex) = _updateCollAndDebtIndex();

    // 获取总份额
    (uint256 totalDebtShares, uint256 totalColls) = _getDebtAndCollateralShares();
    // 使用清算价格
    uint256 price = IPriceOracle(priceOracle).getLiquidatePrice();

    // 转换为原始数量
    uint256 totalRawColls = _convertToRawColl(totalColls, collIndex, Math.Rounding.Down);
    uint256 totalRawDebts = _convertToRawDebt(totalDebtShares, debtIndex, Math.Rounding.Down);
    
    // 检查: 债务 × PRECISION >= 抵押品 × 价格
    underCollateral = totalRawDebts * PRECISION >= totalRawColls * price;
    // 计算缺口
    shortfall = underCollateral ? totalRawDebts - (totalRawColls * price) / PRECISION : 0;
  }

  /****************************
   * 公共状态修改函数 *
   ****************************/

  /// @inheritdoc IShortPool
  /// @notice 终止池
  /// @dev 当池抵押不足时，可以被终止以保护系统
  function kill() external onlyPoolManager {
    if (isKilled) revert ErrorPoolKilled();

    isKilled = true;
  }

  /// @inheritdoc IShortPool
  /// @notice 使用信用票据赎回抵押品
  /// @param creditNoteAmount 信用票据数量
  /// @return rawColls 赎回的抵押品数量
  function redeemByCreditNote(uint256 creditNoteAmount) external onlyPoolManager returns (uint256 rawColls) {
    // allowTickNotMoved = true，允许 tick 不移动
    (, rawColls) = _redeem(creditNoteAmount, true);
  }

  /**********************
   * 内部函数 *
   **********************/

  /// @inheritdoc BasePool
  /// @notice 更新抵押品和债务索引（空头池特有实现）
  /// @dev 实现空头池的资金费率扣除机制
  ///
  /// 资金费率计算:
  /// - 从 PoolConfiguration 获取空头池资金费率
  /// - 根据时间间隔计算资金费用
  /// - 通过增加抵押品索引来扣除费用
  ///
  /// @return newCollIndex 更新后的抵押品索引
  /// @return newDebtIndex 更新后的债务索引
  function _updateCollAndDebtIndex() internal virtual override returns (uint256 newCollIndex, uint256 newDebtIndex) {
    // 池已终止时禁止操作
    if (isKilled) revert ErrorPoolKilled();

    (newDebtIndex, newCollIndex) = _getDebtAndCollateralIndex();

    // 计算时间间隔
    uint256 duration = block.timestamp - lastFundingTimestamp;
    if (duration > 0) {
      // 获取空头池资金费率
      uint256 fundingRatio = IPoolConfiguration(configuration).getShortPoolFundingRatio(address(this));
      if (fundingRatio > 0) {
        (, uint256 totalColls) = _getDebtAndCollateralShares();
        uint256 totalRawColls = _convertToRawColl(totalColls, newCollIndex, Math.Rounding.Down);
        // 计算资金费用 = 总抵押品 × 资金费率 × 时间间隔 / (精度 × 365天)
        uint256 funding = (totalRawColls * fundingRatio * duration) / (PRECISION * 365 days);

        // 通过增加抵押品索引来扣除资金费用
        // 新索引 = 旧索引 × 总抵押品 / (总抵押品 - 资金费用)
        newCollIndex = (newCollIndex * totalRawColls) / (totalRawColls - funding);
        _updateCollateralIndex(newCollIndex);
      }

      // 在池配置上触发 checkpoint
      IPoolConfiguration(configuration).checkpoint(address(this));

      lastFundingTimestamp = block.timestamp;
    }
  }

  /// @inheritdoc BasePool
  /// @notice 扣除协议费用（空头池实现返回 0）
  /// @dev 空头池不收取开仓/平仓协议费用，费用通过资金费率机制收取
  function _deductProtocolFees(int256) internal view virtual override returns (uint256) {
    return 0;
  }
}
