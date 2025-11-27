// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable-v4/access/AccessControlUpgradeable.sol";
import { ERC20PermitUpgradeable } from "@openzeppelin/contracts-upgradeable-v4/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable-v4/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable-v4/token/ERC20/IERC20Upgradeable.sol";
import { EnumerableSetUpgradeable } from "@openzeppelin/contracts-upgradeable-v4/utils/structs/EnumerableSetUpgradeable.sol";

import { IFxFractionalTokenV2 } from "../v2/interfaces/IFxFractionalTokenV2.sol";
import { IFxMarketV2 } from "../v2/interfaces/IFxMarketV2.sol";
import { IFxTreasuryV2 } from "../v2/interfaces/IFxTreasuryV2.sol";
import { IFxUSD } from "../v2/interfaces/IFxUSD.sol";
import { IFxShareableRebalancePool } from "../v2/interfaces/IFxShareableRebalancePool.sol";
import { IFxUSDRegeneracy } from "../interfaces/IFxUSDRegeneracy.sol";
import { IPegKeeper } from "../interfaces/IPegKeeper.sol";

import { Math } from "../libraries/Math.sol";

/// @title FxUSDRegeneracy - fxUSD 代币合约（再生版）
/// @notice fxUSD 稳定币的核心合约，支持铸造、销毁和回购
/// @dev 与 AladdinDAO v3 合约的 FxUSD 具有相同的存储布局
///
/// ==================== fxUSD 概述 ====================
///
/// fxUSD 是一种去中心化稳定币，通过以下机制维持锚定：
///
/// 1. 铸造机制
///    - 用户存入抵押品，借出 fxUSD
///    - 通过 PoolManager 管理仓位
///
/// 2. 回购机制
///    - 当 fxUSD 价格低于锚定时
///    - 使用稳定币储备购买 fxUSD 并销毁
///    - 减少供应，推高价格
///
/// 3. 稳定币储备
///    - 当使用稳定币进行再平衡时
///    - 稳定币存入储备，记录对应的 fxUSD 债务
///    - 回购时使用储备中的稳定币
///
/// 4. 遗留市场支持
///    - 支持 v2 版本的 fToken 包装/解包
///    - 维护与旧版本的兼容性
///
contract FxUSDRegeneracy is AccessControlUpgradeable, ERC20PermitUpgradeable, IFxUSD, IFxUSDRegeneracy {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

  /**********
   * 错误定义 *
   **********/

  /// @dev 当调用者不是 PoolManager 时抛出
  error ErrorCallerNotPoolManager();

  /// @dev 当调用者不是 PegKeeper 时抛出
  error ErrorCallerNotPegKeeper();

  /// @dev 当超过稳定币储备时抛出
  error ErrorExceedStableReserve();

  /// @dev 当输出不足时抛出
  error ErrorInsufficientOutput();

  /// @dev 当回购数量不足时抛出
  error ErrorInsufficientBuyBack();

  /*************
   * 常量定义 *
   *************/

  /// @notice 迁移者角色标识符
  bytes32 public constant MIGRATOR_ROLE = keccak256("MIGRATOR_ROLE");

  /// @dev 计算 NAV 的精度 (1e18)
  uint256 private constant PRECISION = 1e18;

  /***********
   * 结构体 *
   ***********/

  /// @dev f(x) 市场结构体
  /// @param fToken 分数代币地址
  /// @param treasury 国库合约地址
  /// @param market 市场合约地址
  /// @param mintCap 最大可铸造的 fToken 数量
  /// @param managed 此合约管理的 fToken 数量
  struct FxMarketStruct {
    address fToken;
    address treasury;
    address market;
    uint256 mintCap;
    uint256 managed;
  }

  /// @dev 稳定币储备结构体
  /// @param owned 合约拥有的稳定币数量
  /// @param managed 此稳定币对应管理的 fxUSD 数量
  /// @param decimals 稳定币精度
  struct StableReserveStruct {
    uint96 owned;     // 拥有的稳定币数量
    uint96 managed;   // 对应的 fxUSD 债务
    uint8 decimals;   // 稳定币精度
  }

  /***********************
   * 不可变变量 *
   ***********************/

  /// @inheritdoc IFxUSDRegeneracy
  /// @notice PoolManager 合约地址
  address public immutable poolManager;

  /// @inheritdoc IFxUSDRegeneracy
  /// @notice 稳定币（USDC）地址
  address public immutable stableToken;

  /// @inheritdoc IFxUSDRegeneracy
  /// @notice PegKeeper 合约地址
  address public immutable pegKeeper;

  /*********************
   * 存储变量 *
   *********************/

  /// @notice 基础代币地址到市场元数据的映射
  mapping(address => FxMarketStruct) public markets;

  /// @dev 支持的基础代币列表
  EnumerableSetUpgradeable.AddressSet private supportedTokens;

  /// @dev 支持的再平衡池列表
  EnumerableSetUpgradeable.AddressSet private supportedPools;

  /// @notice 遗留 2.0 池的总供应量
  /// @dev 用于兼容旧版本
  uint256 public legacyTotalSupply;

  /// @notice 稳定币储备结构
  /// @dev 记录稳定币储备和对应的 fxUSD 债务
  StableReserveStruct public stableReserve;

  /*************
   * 修饰符 *
   *************/

  /// @dev 验证基础代币是否支持
  modifier onlySupportedMarket(address _baseToken) {
    _checkBaseToken(_baseToken);
    _;
  }

  /// @dev 验证再平衡池是否支持
  modifier onlySupportedPool(address _pool) {
    if (!supportedPools.contains(_pool)) revert ErrorUnsupportedRebalancePool();
    _;
  }

  /// @dev 验证市场是否可铸造
  modifier onlyMintableMarket(address _baseToken, bool isMint) {
    _checkMarketMintable(_baseToken, isMint);
    _;
  }

  /// @dev 仅 PoolManager 可调用
  modifier onlyPoolManager() {
    if (_msgSender() != poolManager) revert ErrorCallerNotPoolManager();
    _;
  }

  /// @dev 仅 PegKeeper 可调用
  modifier onlyPegKeeper() {
    if (_msgSender() != pegKeeper) revert ErrorCallerNotPegKeeper();
    _;
  }

  /***************
   * 构造函数 *
   ***************/

  /// @notice 构造函数
  /// @param _poolManager PoolManager 合约地址
  /// @param _stableToken 稳定币（USDC）地址
  /// @param _pegKeeper PegKeeper 合约地址
  constructor(address _poolManager, address _stableToken, address _pegKeeper) {
    poolManager = _poolManager;
    stableToken = _stableToken;
    pegKeeper = _pegKeeper;
  }

  /// @notice 初始化函数（代理模式）
  /// @param _name 代币名称
  /// @param _symbol 代币符号
  function initialize(string memory _name, string memory _symbol) external initializer {
    __Context_init();
    __ERC165_init();
    __AccessControl_init();
    __ERC20_init(_name, _symbol);
    __ERC20Permit_init(_name);

    _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
  }

  /// @notice V2 初始化函数
  /// @dev 用于升级时初始化新增的存储变量
  function initializeV2() external reinitializer(2) {
    stableReserve.decimals = FxUSDRegeneracy(stableToken).decimals();
    legacyTotalSupply = totalSupply();
  }

  /*************************
   * 公共视图函数 *
   *************************/

  /// @inheritdoc IFxUSD
  /// @notice 获取所有支持的市场（基础代币）
  /// @return _tokens 支持的基础代币地址数组
  function getMarkets() external view override returns (address[] memory _tokens) {
    uint256 _numMarkets = supportedTokens.length();
    _tokens = new address[](_numMarkets);
    for (uint256 i = 0; i < _numMarkets; ++i) {
      _tokens[i] = supportedTokens.at(i);
    }
  }

  /// @inheritdoc IFxUSD
  /// @notice 获取所有支持的再平衡池
  /// @return _pools 支持的再平衡池地址数组
  function getRebalancePools() external view override returns (address[] memory _pools) {
    uint256 _numPools = supportedPools.length();
    _pools = new address[](_numPools);
    for (uint256 i = 0; i < _numPools; ++i) {
      _pools[i] = supportedPools.at(i);
    }
  }

  /// @inheritdoc IFxUSD
  /// @notice 获取 fxUSD 的净资产价值 (NAV)
  /// @return _nav NAV 值（×1e18）
  function nav() external view override returns (uint256 _nav) {
    uint256 _numMarkets = supportedTokens.length();
    uint256 _supply = legacyTotalSupply;
    if (_supply == 0) return PRECISION;

    // 计算所有市场的加权 NAV
    for (uint256 i = 0; i < _numMarkets; i++) {
      address _baseToken = supportedTokens.at(i);
      address _fToken = markets[_baseToken].fToken;
      uint256 _fnav = IFxFractionalTokenV2(_fToken).nav();
      _nav += _fnav * markets[_baseToken].managed;
    }
    _nav /= _supply;
  }

  /// @inheritdoc IFxUSD
  /// @notice 检查是否有市场处于抵押不足状态
  /// @return 如果任何市场抵押不足返回 true
  function isUnderCollateral() public view override returns (bool) {
    uint256 _numMarkets = supportedTokens.length();
    for (uint256 i = 0; i < _numMarkets; i++) {
      address _baseToken = supportedTokens.at(i);
      address _treasury = markets[_baseToken].treasury;
      if (IFxTreasuryV2(_treasury).isUnderCollateral()) return true;
    }
    return false;
  }

  /****************************
   * Public Mutated Functions *
   ****************************/

  /// @inheritdoc IFxUSD
  function wrap(
    address _baseToken,
    uint256 _amount,
    address _receiver
  ) external override onlySupportedMarket(_baseToken) onlyMintableMarket(_baseToken, false) {
    if (isUnderCollateral()) revert ErrorUnderCollateral();

    address _fToken = markets[_baseToken].fToken;
    IERC20Upgradeable(_fToken).safeTransferFrom(_msgSender(), address(this), _amount);

    _mintShares(_baseToken, _receiver, _amount);

    emit Wrap(_baseToken, _msgSender(), _receiver, _amount);
  }

  /// @inheritdoc IFxUSD
  function unwrap(
    address _baseToken,
    uint256 _amount,
    address _receiver
  ) external onlyRole(MIGRATOR_ROLE) onlySupportedMarket(_baseToken) {
    if (isUnderCollateral()) revert ErrorUnderCollateral();

    _burnShares(_baseToken, _msgSender(), _amount);

    address _fToken = markets[_baseToken].fToken;
    IERC20Upgradeable(_fToken).safeTransfer(_receiver, _amount);

    emit Unwrap(_baseToken, _msgSender(), _receiver, _amount);
  }

  /// @inheritdoc IFxUSD
  function wrapFrom(address _pool, uint256 _amount, address _receiver) external override onlySupportedPool(_pool) {
    if (isUnderCollateral()) revert ErrorUnderCollateral();

    address _baseToken = IFxShareableRebalancePool(_pool).baseToken();
    _checkBaseToken(_baseToken);
    _checkMarketMintable(_baseToken, false);

    IFxShareableRebalancePool(_pool).withdrawFrom(_msgSender(), _amount, address(this));
    _mintShares(_baseToken, _receiver, _amount);

    emit Wrap(_baseToken, _msgSender(), _receiver, _amount);
  }

  /// @inheritdoc IFxUSD
  function mint(address, uint256, address, uint256) external virtual override returns (uint256) {
    revert("mint paused");
  }

  /// @inheritdoc IFxUSD
  function earn(address, uint256, address) external virtual override {
    revert("earn paused");
  }

  /// @inheritdoc IFxUSD
  function mintAndEarn(address, uint256, address, uint256) external virtual override returns (uint256) {
    revert("mint and earn paused");
  }

  /// @inheritdoc IFxUSD
  function redeem(
    address _baseToken,
    uint256 _amountIn,
    address _receiver,
    uint256 _minOut
  ) external override onlySupportedMarket(_baseToken) returns (uint256 _amountOut, uint256 _bonusOut) {
    if (isUnderCollateral()) revert ErrorUnderCollateral();

    address _market = markets[_baseToken].market;
    address _fToken = markets[_baseToken].fToken;

    uint256 _balance = IERC20Upgradeable(_fToken).balanceOf(address(this));
    (_amountOut, _bonusOut) = IFxMarketV2(_market).redeemFToken(_amountIn, _receiver, _minOut);
    // the real amount of fToken redeemed
    _amountIn = _balance - IERC20Upgradeable(_fToken).balanceOf(address(this));

    _burnShares(_baseToken, _msgSender(), _amountIn);
    emit Unwrap(_baseToken, _msgSender(), _receiver, _amountIn);
  }

  /// @inheritdoc IFxUSD
  function redeemFrom(
    address _pool,
    uint256 _amountIn,
    address _receiver,
    uint256 _minOut
  ) external override onlySupportedPool(_pool) returns (uint256 _amountOut, uint256 _bonusOut) {
    address _baseToken = IFxShareableRebalancePool(_pool).baseToken();
    address _market = markets[_baseToken].market;
    address _fToken = markets[_baseToken].fToken;

    // calculate the actual amount of fToken withdrawn from rebalance pool.
    _amountOut = IERC20Upgradeable(_fToken).balanceOf(address(this));
    IFxShareableRebalancePool(_pool).withdrawFrom(_msgSender(), _amountIn, address(this));
    _amountOut = IERC20Upgradeable(_fToken).balanceOf(address(this)) - _amountOut;

    // redeem fToken as base token
    // assume all fToken will be redeem for simplicity
    (_amountOut, _bonusOut) = IFxMarketV2(_market).redeemFToken(_amountOut, _receiver, _minOut);
  }

  /// @inheritdoc IFxUSD
  function autoRedeem(
    uint256 _amountIn,
    address _receiver,
    uint256[] memory _minOuts
  )
    external
    override
    returns (address[] memory _baseTokens, uint256[] memory _amountOuts, uint256[] memory _bonusOuts)
  {
    uint256 _numMarkets = supportedTokens.length();
    if (_minOuts.length != _numMarkets) revert ErrorLengthMismatch();

    _baseTokens = new address[](_numMarkets);
    _amountOuts = new uint256[](_numMarkets);
    _bonusOuts = new uint256[](_numMarkets);
    uint256[] memory _supplies = new uint256[](_numMarkets);

    bool _isUnderCollateral = false;
    for (uint256 i = 0; i < _numMarkets; i++) {
      _baseTokens[i] = supportedTokens.at(i);
      _supplies[i] = markets[_baseTokens[i]].managed;
      address _treasury = markets[_baseTokens[i]].treasury;
      if (IFxTreasuryV2(_treasury).isUnderCollateral()) _isUnderCollateral = true;
    }

    uint256 _supply = legacyTotalSupply;
    if (_amountIn > _supply) revert("redeem exceed supply");
    unchecked {
      legacyTotalSupply = _supply - _amountIn;
    }
    _burn(_msgSender(), _amountIn);

    if (_isUnderCollateral) {
      // redeem proportionally
      for (uint256 i = 0; i < _numMarkets; i++) {
        _amountOuts[i] = (_supplies[i] * _amountIn) / _supply;
      }
    } else {
      // redeem by sorted fToken amounts
      while (_amountIn > 0) {
        unchecked {
          uint256 maxSupply = _supplies[0];
          uint256 maxIndex = 0;
          for (uint256 i = 1; i < _numMarkets; i++) {
            if (_supplies[i] > maxSupply) {
              maxSupply = _supplies[i];
              maxIndex = i;
            }
          }
          if (_amountIn > maxSupply) _amountOuts[maxIndex] = maxSupply;
          else _amountOuts[maxIndex] = _amountIn;
          _supplies[maxIndex] -= _amountOuts[maxIndex];
          _amountIn -= _amountOuts[maxIndex];
        }
      }
    }

    for (uint256 i = 0; i < _numMarkets; i++) {
      if (_amountOuts[i] == 0) continue;
      emit Unwrap(_baseTokens[i], _msgSender(), _receiver, _amountOuts[i]);

      markets[_baseTokens[i]].managed -= _amountOuts[i];
      address _market = markets[_baseTokens[i]].market;
      (_amountOuts[i], _bonusOuts[i]) = IFxMarketV2(_market).redeemFToken(_amountOuts[i], _receiver, _minOuts[i]);
    }
  }

  /// @inheritdoc IFxUSDRegeneracy
  /// @notice 铸造 fxUSD
  /// @dev 仅 PoolManager 可调用
  /// @param to 接收者地址
  /// @param amount 铸造数量
  function mint(address to, uint256 amount) external onlyPoolManager {
    _mint(to, amount);
  }

  /// @inheritdoc IFxUSDRegeneracy
  /// @notice 销毁 fxUSD
  /// @dev 仅 PoolManager 可调用
  /// @param from 销毁来源地址
  /// @param amount 销毁数量
  function burn(address from, uint256 amount) external onlyPoolManager {
    _burn(from, amount);
  }

  /// @inheritdoc IFxUSDRegeneracy
  /// @notice 使用稳定币进行再平衡时的回调
  /// @dev 仅 PoolManager 可调用，记录稳定币储备和对应的 fxUSD 债务
  /// @param amountStableToken 稳定币数量
  /// @param amountFxUSD 对应的 fxUSD 数量
  function onRebalanceWithStable(uint256 amountStableToken, uint256 amountFxUSD) external onlyPoolManager {
    stableReserve.owned += uint96(amountStableToken);
    stableReserve.managed += uint96(amountFxUSD);

    emit RebalanceWithStable(amountStableToken, amountFxUSD);
  }

  /// @inheritdoc IFxUSDRegeneracy
  /// @notice 回购 fxUSD
  /// @dev 仅 PegKeeper 可调用，使用稳定币储备购买 fxUSD 并销毁
  /// @param amountIn 使用的稳定币数量
  /// @param receiver 奖励接收者地址
  /// @param data 交换路径数据
  /// @return amountOut 购买的 fxUSD 数量
  /// @return bonusOut 额外奖励
  function buyback(
    uint256 amountIn,
    address receiver,
    bytes calldata data
  ) external onlyPegKeeper returns (uint256 amountOut, uint256 bonusOut) {
    StableReserveStruct memory cachedStableReserve = stableReserve;
    // 检查稳定币储备是否足够
    if (amountIn > cachedStableReserve.owned) revert ErrorExceedStableReserve();

    // 向上取整计算预期需要的 fxUSD
    uint256 expectedFxUSD = Math.mulDivUp(amountIn, cachedStableReserve.managed, cachedStableReserve.owned);

    // 将 USDC 转给 PegKeeper 进行交换
    IERC20Upgradeable(stableToken).safeTransfer(pegKeeper, amountIn);
    uint256 actualOut = balanceOf(address(this));
    amountOut = IPegKeeper(pegKeeper).onSwap(stableToken, address(this), amountIn, data);
    actualOut = balanceOf(address(this)) - actualOut;

    // 检查实际交换的 fxUSD 数量（防止 PegKeeper 被攻击）
    if (amountOut > actualOut) revert ErrorInsufficientOutput();

    // 检查交换的 fxUSD 能够覆盖债务
    if (amountOut < expectedFxUSD) revert ErrorInsufficientBuyBack();
    bonusOut = amountOut - expectedFxUSD;

    // 销毁债务对应的 fxUSD
    _burn(address(this), expectedFxUSD);
    unchecked {
      // 更新稳定币储备
      cachedStableReserve.owned -= uint96(amountIn);
      if (cachedStableReserve.managed > expectedFxUSD) {
        cachedStableReserve.managed -= uint96(expectedFxUSD);
      } else {
        cachedStableReserve.managed = 0;
      }
      stableReserve = cachedStableReserve;
    }

    // 转移奖励给接收者
    if (bonusOut > 0) {
      _transfer(address(this), receiver, bonusOut);
    }

    emit Buyback(amountIn, amountOut, bonusOut);
  }

  /**********************
   * 内部函数 *
   **********************/

  /// @dev 内部函数：检查基础代币是否支持
  /// @param _baseToken 基础代币地址
  function _checkBaseToken(address _baseToken) private view {
    if (!supportedTokens.contains(_baseToken)) revert ErrorUnsupportedMarket();
  }

  /// @dev 内部函数：检查市场是否可铸造
  /// @param _baseToken 基础代币地址
  /// @param _checkCollateralRatio 是否检查抵押率
  function _checkMarketMintable(address _baseToken, bool _checkCollateralRatio) private view {
    address _treasury = markets[_baseToken].treasury;
    if (_checkCollateralRatio) {
      uint256 _collateralRatio = IFxTreasuryV2(_treasury).collateralRatio();
      uint256 _stabilityRatio = IFxMarketV2(markets[_baseToken].market).stabilityRatio();
      // 当抵押率 <= 稳定率时，不允许铸造
      if (_collateralRatio <= _stabilityRatio) revert ErrorMarketInStabilityMode();
    }
    // 当价格无效时，不允许铸造
    if (!IFxTreasuryV2(_treasury).isBaseTokenPriceValid()) revert ErrorMarketWithInvalidPrice();
  }

  /// @dev 内部函数：铸造 fxUSD（遗留市场）
  /// @param _baseToken 基础代币地址
  /// @param _receiver fxUSD 接收者地址
  /// @param _amount 铸造数量
  function _mintShares(address _baseToken, address _receiver, uint256 _amount) private {
    unchecked {
      markets[_baseToken].managed += _amount;
      legacyTotalSupply += _amount;
    }

    _mint(_receiver, _amount);
  }

  /// @dev 内部函数：销毁 fxUSD（遗留市场）
  /// @param _baseToken 基础代币地址
  /// @param _owner fxUSD 所有者地址
  /// @param _amount 销毁数量
  function _burnShares(address _baseToken, address _owner, uint256 _amount) private {
    uint256 _managed = markets[_baseToken].managed;
    if (_amount > _managed) revert ErrorInsufficientLiquidity();
    unchecked {
      markets[_baseToken].managed -= _amount;
      legacyTotalSupply -= _amount;
    }

    _burn(_owner, _amount);
  }
}
