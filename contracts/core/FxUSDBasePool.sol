// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ERC20PermitUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import { IStrategy } from "../fund/IStrategy.sol";
import { AggregatorV3Interface } from "../interfaces/Chainlink/AggregatorV3Interface.sol";
import { IPegKeeper } from "../interfaces/IPegKeeper.sol";
import { IPool } from "../interfaces/IPool.sol";
import { ILongPoolManager } from "../interfaces/ILongPoolManager.sol";
import { IFxUSDBasePool } from "../interfaces/IFxUSDBasePool.sol";
import { IFxUSDPriceOracle } from "../interfaces/IFxUSDPriceOracle.sol";

import { AssetManagement } from "../fund/AssetManagement.sol";
import { Math } from "../libraries/Math.sol";

/// @title FxUSDBasePool - fxUSD 基础池合约
/// @notice 管理 fxUSD 和稳定币的流动性池，支持存款、赎回、再平衡和清算
/// @dev 实现 ERC20 代币标准，代表池中的份额
///
/// ==================== 基础池概述 ====================
///
/// 1. 存款机制
///    - 用户可以存入 fxUSD 或 USDC
///    - 根据当前池的 NAV 计算份额
///    - 份额代表用户在池中的权益
///
/// 2. 赎回机制
///    - 延迟赎回: 请求赎回 -> 等待冷却期 -> 领取
///    - 即时赎回: 支付手续费后立即赎回
///    - 赎回时按比例获得 fxUSD 和 USDC
///
/// 3. 再平衡和清算
///    - 当仓位需要再平衡或清算时，使用池中的资金
///    - 获得抵押品作为回报
///    - 支持套利机制维护价格锚定
///
/// 4. 套利机制
///    - 当 fxUSD 价格偏离时，允许套利
///    - 套利者获得利润，同时帮助稳定价格
///
contract FxUSDBasePool is
  ERC20PermitUpgradeable,
  AccessControlUpgradeable,
  ReentrancyGuardUpgradeable,
  AssetManagement,
  IFxUSDBasePool
{
  using SafeERC20 for IERC20;

  /**********
   * 错误定义 *
   **********/

  /// @dev 当存款金额为零时抛出
  error ErrDepositZeroAmount();

  /// @dev 当铸造的份额不足时抛出
  error ErrInsufficientSharesOut();

  /// @dev 当输入代币无效时抛出
  error ErrInvalidTokenIn();

  /// @dev 当赎回份额为零时抛出
  error ErrRedeemZeroShares();

  /// @dev 当调用者不是 PegKeeper 时抛出
  error ErrorCallerNotPegKeeper();

  /// @dev 当稳定币脱锚时抛出
  error ErrorStableTokenDepeg();

  /// @dev 当交换金额超过余额时抛出
  error ErrorSwapExceedBalance();

  /// @dev 当输出不足时抛出
  error ErrorInsufficientOutput();

  /// @dev 当套利收益不足时抛出
  error ErrorInsufficientArbitrage();

  /// @dev 当赎回冷却期过长时抛出
  error ErrorRedeemCoolDownPeriodTooLarge();

  /// @dev 当赎回金额超过余额时抛出
  error ErrorRedeemMoreThanBalance();

  /// @dev 当赎回锁定的份额时抛出
  error ErrorRedeemLockedShares();

  /// @dev 当可用余额不足时抛出
  error ErrorInsufficientFreeBalance();

  /// @dev 当即时赎回费率过高时抛出
  error ErrorInstantRedeemFeeTooLarge();

  /*************
   * 常量定义 *
   *************/

  /// @notice 免即时赎回费角色标识符
  /// @dev 拥有此角色的地址可以免费即时赎回
  bytes32 public constant NO_INSTANT_REDEEM_FEE_ROLE = keccak256("NO_INSTANT_REDEEM_FEE_ROLE");

  /// @dev 汇率计算精度 (1e18)
  uint256 internal constant PRECISION = 1e18;

  /// @dev 最大即时赎回费率 (5%)
  uint256 internal constant MAX_INSTANT_REDEEM_FEE = 5e16;

  /***********************
   * 不可变变量 *
   ***********************/

  /// @notice PoolManager 合约地址
  address public immutable poolManager;

  /// @notice PegKeeper 合约地址
  address public immutable pegKeeper;

  /// @inheritdoc IFxUSDBasePool
  /// @notice 收益代币地址（即 fxUSD）
  address public immutable yieldToken;

  /// @inheritdoc IFxUSDBasePool
  /// @notice 稳定币地址（即 USDC）
  address public immutable stableToken;

  /// @dev 稳定币精度缩放因子（将 USDC 的 6 位精度转换为 18 位）
  uint256 private immutable stableTokenScale;

  /// @notice fxUSD 价格预言机地址
  address public immutable fxUSDPriceOracle;

  /***********
   * 结构体 *
   ***********/

  /// @dev 再平衡/清算操作的内存变量
  struct RebalanceMemoryVar {
    uint256 stablePrice;        // 稳定币价格
    uint256 totalYieldToken;    // 总 fxUSD 数量
    uint256 totalStableToken;   // 总稳定币数量
    uint256 yieldTokenToUse;    // 要使用的 fxUSD 数量
    uint256 stableTokenToUse;   // 要使用的稳定币数量
    uint256 colls;              // 获得的抵押品数量
    uint256 yieldTokenUsed;     // 实际使用的 fxUSD 数量
    uint256 stableTokenUsed;    // 实际使用的稳定币数量
  }

  /// @dev 赎回请求结构体
  struct RedeemRequest {
    uint128 amount;    // 请求赎回的份额数量
    uint128 unlockAt;  // 解锁时间戳
  }

  /*************
   * 存储变量 *
   *************/

  /// @inheritdoc IFxUSDBasePool
  /// @notice 池中的 fxUSD 总量
  uint256 public totalYieldToken;

  /// @inheritdoc IFxUSDBasePool
  /// @notice 池中的稳定币总量
  uint256 public totalStableToken;

  /// @notice 稳定币脱锚价格阈值
  /// @dev 当 USDC 价格低于此值时，禁止某些操作
  uint256 public stableDepegPrice;

  /// @notice 用户地址到赎回请求的映射
  mapping(address => RedeemRequest) public redeemRequests;

  /// @notice 赎回冷却期（秒）
  uint256 public redeemCoolDownPeriod;

  /// @notice 即时赎回费率
  uint256 public instantRedeemFeeRatio;

  /*************
   * 修饰符 *
   *************/

  /// @dev 验证输入代币是否有效（fxUSD 或 USDC）
  modifier onlyValidToken(address token) {
    if (token != stableToken && token != yieldToken) {
      revert ErrInvalidTokenIn();
    }
    _;
  }

  /// @dev 仅 PegKeeper 可调用
  modifier onlyPegKeeper() {
    if (_msgSender() != pegKeeper) revert ErrorCallerNotPegKeeper();
    _;
  }

  /// @dev 同步稳定币余额（包括策略中的资金）
  modifier sync() {
    totalStableToken = _getTotalStableTokenInPool();
    _;
  }

  /***************
   * 构造函数 *
   ***************/

  /// @notice 构造函数
  /// @param _poolManager PoolManager 合约地址
  /// @param _pegKeeper PegKeeper 合约地址
  /// @param _yieldToken fxUSD 代币地址
  /// @param _stableToken 稳定币（USDC）地址
  /// @param _fxUSDPriceOracle fxUSD 价格预言机地址
  constructor(
    address _poolManager,
    address _pegKeeper,
    address _yieldToken,
    address _stableToken,
    address _fxUSDPriceOracle
  ) {
    poolManager = _poolManager;
    pegKeeper = _pegKeeper;
    yieldToken = _yieldToken;
    stableToken = _stableToken;
    fxUSDPriceOracle = _fxUSDPriceOracle;

    // 计算稳定币精度缩放因子（USDC 是 6 位精度，需要乘以 10^12 转换为 18 位）
    stableTokenScale = 10 ** (18 - IERC20Metadata(_stableToken).decimals());
  }

  /// @notice 初始化函数（代理模式）
  /// @param admin 管理员地址
  /// @param _name 代币名称
  /// @param _symbol 代币符号
  /// @param _stableDepegPrice 稳定币脱锚价格阈值
  /// @param _redeemCoolDownPeriod 赎回冷却期
  function initialize(
    address admin,
    string memory _name,
    string memory _symbol,
    uint256 _stableDepegPrice,
    uint256 _redeemCoolDownPeriod
  ) external initializer {
    __Context_init();
    __ERC165_init();
    __AccessControl_init();
    __ReentrancyGuard_init();

    __ERC20_init(_name, _symbol);
    __ERC20Permit_init(_name);

    _grantRole(DEFAULT_ADMIN_ROLE, admin);

    _updateStableDepegPrice(_stableDepegPrice);
    _updateRedeemCoolDownPeriod(_redeemCoolDownPeriod);

    // 授权 PoolManager 无限额度
    IERC20(yieldToken).forceApprove(poolManager, type(uint256).max);
    IERC20(stableToken).forceApprove(poolManager, type(uint256).max);
  }

  /*************************
   * 公共视图函数 *
   *************************/

  /// @inheritdoc IFxUSDBasePool
  /// @notice 预览存款可获得的份额
  /// @param tokenIn 输入代币地址（fxUSD 或 USDC）
  /// @param amountTokenToDeposit 存款数量
  /// @return amountSharesOut 可获得的份额数量
  function previewDeposit(
    address tokenIn,
    uint256 amountTokenToDeposit
  ) public view override onlyValidToken(tokenIn) returns (uint256 amountSharesOut) {
    uint256 price = getStableTokenPriceWithScale();
    uint256 amountUSD = amountTokenToDeposit;
    // 如果是稳定币，转换为 USD 价值
    if (tokenIn == stableToken) {
      amountUSD = (amountUSD * price) / PRECISION;
    }

    uint256 _totalSupply = totalSupply();
    if (_totalSupply == 0) {
      // 首次存款，1:1 铸造份额
      amountSharesOut = amountUSD;
    } else {
      // 按比例计算份额
      uint256 totalUSD = totalYieldToken + (_getTotalStableTokenInPool() * price) / PRECISION;
      amountSharesOut = (amountUSD * _totalSupply) / totalUSD;
    }
  }

  /// @inheritdoc IFxUSDBasePool
  /// @notice 预览赎回可获得的代币数量
  /// @param amountSharesToRedeem 要赎回的份额数量
  /// @return amountYieldOut 可获得的 fxUSD 数量
  /// @return amountStableOut 可获得的稳定币数量
  function previewRedeem(
    uint256 amountSharesToRedeem
  ) external view returns (uint256 amountYieldOut, uint256 amountStableOut) {
    uint256 cachedTotalYieldToken = totalYieldToken;
    uint256 cachedTotalStableToken = _getTotalStableTokenInPool();
    uint256 cachedTotalSupply = totalSupply();
    // 按比例计算可赎回的代币数量
    amountYieldOut = (amountSharesToRedeem * cachedTotalYieldToken) / cachedTotalSupply;
    amountStableOut = (amountSharesToRedeem * cachedTotalStableToken) / cachedTotalSupply;
  }

  /// @inheritdoc IFxUSDBasePool
  /// @notice 返回每份额的净资产价值 (NAV)
  /// @return NAV 值（×1e18）
  function nav() external view returns (uint256) {
    uint256 _totalSupply = totalSupply();
    if (_totalSupply == 0) {
      return PRECISION;
    } else {
      uint256 stablePrice = getStableTokenPriceWithScale();
      (, uint256 yieldPrice) = IFxUSDPriceOracle(fxUSDPriceOracle).getPrice();
      // NAV = (fxUSD 价值 + 稳定币价值) / 总份额
      return (totalYieldToken * yieldPrice + _getTotalStableTokenInPool() * stablePrice) / _totalSupply;
    }
  }

  /// @inheritdoc IFxUSDBasePool
  /// @notice 获取稳定币价格
  /// @return USDC/USD 价格（×1e18）
  function getStableTokenPrice() public view returns (uint256) {
    return IFxUSDPriceOracle(fxUSDPriceOracle).getUSDCPrice();
  }

  /// @inheritdoc IFxUSDBasePool
  /// @notice 获取稳定币价格（带精度缩放）
  /// @return 缩放后的价格，用于与 18 位精度的代币计算
  function getStableTokenPriceWithScale() public view returns (uint256) {
    return getStableTokenPrice() * stableTokenScale;
  }

  /****************************
   * 公共状态修改函数 *
   ****************************/

  /// @inheritdoc IFxUSDBasePool
  /// @notice 存款
  /// @param receiver 份额接收者地址
  /// @param tokenIn 输入代币地址（fxUSD 或 USDC）
  /// @param amountTokenToDeposit 存款数量
  /// @param minSharesOut 最小可接受的份额数量
  /// @return amountSharesOut 实际铸造的份额数量
  function deposit(
    address receiver,
    address tokenIn,
    uint256 amountTokenToDeposit,
    uint256 minSharesOut
  ) external override nonReentrant onlyValidToken(tokenIn) sync returns (uint256 amountSharesOut) {
    if (amountTokenToDeposit == 0) revert ErrDepositZeroAmount();

    // 转入代币（假设是标准 ERC20，无转账税）
    IERC20(tokenIn).safeTransferFrom(_msgSender(), address(this), amountTokenToDeposit);

    amountSharesOut = _deposit(tokenIn, amountTokenToDeposit);
    if (amountSharesOut < minSharesOut) revert ErrInsufficientSharesOut();

    _mint(receiver, amountSharesOut);

    emit Deposit(_msgSender(), receiver, tokenIn, amountTokenToDeposit, amountSharesOut);
  }

  /// @inheritdoc IFxUSDBasePool
  /// @notice 请求赎回（延迟赎回）
  /// @dev 份额会被锁定，等待冷却期后才能领取
  /// @param shares 要赎回的份额数量
  function requestRedeem(uint256 shares) external {
    address caller = _msgSender();
    uint256 balance = balanceOf(caller);
    RedeemRequest memory request = redeemRequests[caller];
    if (request.amount + shares > balance) revert ErrorRedeemMoreThanBalance();
    request.amount += uint128(shares);
    request.unlockAt = uint128(block.timestamp + redeemCoolDownPeriod);
    redeemRequests[caller] = request;

    emit RequestRedeem(caller, shares, request.unlockAt);
  }

  /// @inheritdoc IFxUSDBasePool
  /// @notice 赎回已解锁的份额
  /// @param receiver 代币接收者地址
  /// @param amountSharesToRedeem 要赎回的份额数量
  /// @return amountYieldOut 获得的 fxUSD 数量
  /// @return amountStableOut 获得的稳定币数量
  function redeem(
    address receiver,
    uint256 amountSharesToRedeem
  ) external nonReentrant sync returns (uint256 amountYieldOut, uint256 amountStableOut) {
    address caller = _msgSender();
    RedeemRequest memory request = redeemRequests[caller];
    // 检查是否已过冷却期
    if (request.unlockAt > block.timestamp) revert ErrorRedeemLockedShares();
    // 限制赎回数量不超过请求数量
    if (request.amount < amountSharesToRedeem) {
      amountSharesToRedeem = request.amount;
    }
    if (amountSharesToRedeem == 0) revert ErrRedeemZeroShares();
    request.amount -= uint128(amountSharesToRedeem);
    redeemRequests[caller] = request;

    uint256 cachedTotalYieldToken = totalYieldToken;
    uint256 cachedTotalStableToken = totalStableToken;
    uint256 cachedTotalSupply = totalSupply();

    // 按比例计算可赎回的代币数量
    amountYieldOut = (amountSharesToRedeem * cachedTotalYieldToken) / cachedTotalSupply;
    amountStableOut = (amountSharesToRedeem * cachedTotalStableToken) / cachedTotalSupply;

    _burn(caller, amountSharesToRedeem);

    // 转出 fxUSD
    if (amountYieldOut > 0) {
      _transferOut(yieldToken, amountYieldOut, receiver);
      unchecked {
        totalYieldToken = cachedTotalYieldToken - amountYieldOut;
      }
    }
    // 转出稳定币
    if (amountStableOut > 0) {
      _transferOut(stableToken, amountStableOut, receiver);
      unchecked {
        totalStableToken = cachedTotalStableToken - amountStableOut;
      }
    }

    emit Redeem(caller, receiver, amountSharesToRedeem, amountYieldOut, amountStableOut);
  }

  /// @inheritdoc IFxUSDBasePool
  /// @notice 即时赎回（支付手续费）
  /// @dev 无需等待冷却期，但需要支付手续费
  /// @param receiver 代币接收者地址
  /// @param amountSharesToRedeem 要赎回的份额数量
  /// @return amountYieldOut 获得的 fxUSD 数量（扣除手续费后）
  /// @return amountStableOut 获得的稳定币数量（扣除手续费后）
  function instantRedeem(
    address receiver,
    uint256 amountSharesToRedeem
  ) public nonReentrant sync returns (uint256 amountYieldOut, uint256 amountStableOut) {
    if (amountSharesToRedeem == 0) revert ErrRedeemZeroShares();

    address caller = _msgSender();
    // 只能即时赎回未锁定的份额
    uint256 leftover = balanceOf(caller) - redeemRequests[caller].amount;
    if (amountSharesToRedeem > leftover) revert ErrorInsufficientFreeBalance();

    uint256 cachedTotalYieldToken = totalYieldToken;
    uint256 cachedTotalStableToken = totalStableToken;
    uint256 cachedTotalSupply = totalSupply();

    // 按比例计算可赎回的代币数量
    amountYieldOut = (amountSharesToRedeem * cachedTotalYieldToken) / cachedTotalSupply;
    amountStableOut = (amountSharesToRedeem * cachedTotalStableToken) / cachedTotalSupply;
    uint256 feeRatio = instantRedeemFeeRatio;

    _burn(caller, amountSharesToRedeem);

    // 转出 fxUSD（扣除手续费）
    if (amountYieldOut > 0) {
      uint256 fee = (amountYieldOut * feeRatio) / PRECISION;
      amountYieldOut -= fee;
      _transferOut(yieldToken, amountYieldOut, receiver);
      unchecked {
        totalYieldToken = cachedTotalYieldToken - amountYieldOut;
      }
    }
    // 转出稳定币（扣除手续费）
    if (amountStableOut > 0) {
      uint256 fee = (amountStableOut * feeRatio) / PRECISION;
      amountStableOut -= fee;
      _transferOut(stableToken, amountStableOut, receiver);
      unchecked {
        totalStableToken = cachedTotalStableToken - amountStableOut;
      }
    }

    emit InstantRedeem(caller, receiver, amountSharesToRedeem, amountYieldOut, amountStableOut);
  }

  /// @inheritdoc IFxUSDBasePool
  /// @notice 免手续费即时赎回
  /// @dev 仅拥有 NO_INSTANT_REDEEM_FEE_ROLE 角色的地址可调用
  /// @param receiver 代币接收者地址
  /// @param amountSharesToRedeem 要赎回的份额数量
  /// @return amountYieldOut 获得的 fxUSD 数量
  /// @return amountStableOut 获得的稳定币数量
  function instantRedeemNoFee(address receiver, uint256 amountSharesToRedeem) external onlyRole(NO_INSTANT_REDEEM_FEE_ROLE) returns (uint256 amountYieldOut, uint256 amountStableOut) {
    // 临时清除手续费率
    uint256 originalFeeRatio = instantRedeemFeeRatio;
    instantRedeemFeeRatio = 0;
    (amountYieldOut, amountStableOut) = instantRedeem(receiver, amountSharesToRedeem);
    // 恢复手续费率
    instantRedeemFeeRatio = originalFeeRatio;
  }

  /// @inheritdoc IFxUSDBasePool
  /// @notice 再平衡指定 tick 的仓位
  /// @dev 使用池中的 fxUSD/USDC 来再平衡仓位，获得抵押品作为回报
  /// @param pool 目标池地址
  /// @param tickId 要再平衡的 tick ID
  /// @param tokenIn 用户支付的代币类型（fxUSD 或 USDC）
  /// @param maxAmount 最大支付数量
  /// @param minCollOut 最小可接受的抵押品数量
  /// @return tokenUsed 实际使用的代币数量
  /// @return colls 获得的抵押品数量
  function rebalance(
    address pool,
    int16 tickId,
    address tokenIn,
    uint256 maxAmount,
    uint256 minCollOut
  ) external onlyValidToken(tokenIn) nonReentrant sync returns (uint256 tokenUsed, uint256 colls) {
    RebalanceMemoryVar memory op = _beforeRebalanceOrLiquidate(tokenIn, maxAmount);
    (op.colls, op.yieldTokenUsed, op.stableTokenUsed) = ILongPoolManager(poolManager).rebalance(
      pool,
      _msgSender(),
      tickId,
      op.yieldTokenToUse,
      op.stableTokenToUse
    );
    tokenUsed = _afterRebalanceOrLiquidate(tokenIn, minCollOut, op);
    colls = op.colls;
  }

  /// @inheritdoc IFxUSDBasePool
  /// @notice 再平衡池中的仓位（自动选择 tick）
  /// @param pool 目标池地址
  /// @param tokenIn 用户支付的代币类型（fxUSD 或 USDC）
  /// @param maxAmount 最大支付数量
  /// @param minCollOut 最小可接受的抵押品数量
  /// @return tokenUsed 实际使用的代币数量
  /// @return colls 获得的抵押品数量
  function rebalance(
    address pool,
    address tokenIn,
    uint256 maxAmount,
    uint256 minCollOut
  ) external onlyValidToken(tokenIn) nonReentrant sync returns (uint256 tokenUsed, uint256 colls) {
    RebalanceMemoryVar memory op = _beforeRebalanceOrLiquidate(tokenIn, maxAmount);
    (op.colls, op.yieldTokenUsed, op.stableTokenUsed) = ILongPoolManager(poolManager).rebalance(
      pool,
      _msgSender(),
      op.yieldTokenToUse,
      op.stableTokenToUse
    );
    tokenUsed = _afterRebalanceOrLiquidate(tokenIn, minCollOut, op);
    colls = op.colls;
  }

  /// @inheritdoc IFxUSDBasePool
  /// @notice 清算池中的仓位
  /// @dev 当仓位低于清算阈值时，可以清算获得抵押品
  /// @param pool 目标池地址
  /// @param tokenIn 用户支付的代币类型（fxUSD 或 USDC）
  /// @param maxAmount 最大支付数量
  /// @param minCollOut 最小可接受的抵押品数量
  /// @return tokenUsed 实际使用的代币数量
  /// @return colls 获得的抵押品数量
  function liquidate(
    address pool,
    address tokenIn,
    uint256 maxAmount,
    uint256 minCollOut
  ) external onlyValidToken(tokenIn) nonReentrant sync returns (uint256 tokenUsed, uint256 colls) {
    RebalanceMemoryVar memory op = _beforeRebalanceOrLiquidate(tokenIn, maxAmount);
    (op.colls, op.yieldTokenUsed, op.stableTokenUsed) = ILongPoolManager(poolManager).liquidate(
      pool,
      _msgSender(),
      op.yieldTokenToUse,
      op.stableTokenToUse
    );
    tokenUsed = _afterRebalanceOrLiquidate(tokenIn, minCollOut, op);
    colls = op.colls;
  }

  /// @inheritdoc IFxUSDBasePool
  /// @notice 套利交换
  /// @dev 仅 PegKeeper 可调用，用于维护 fxUSD 价格锚定
  /// @param srcToken 源代币地址（fxUSD 或 USDC）
  /// @param amountIn 输入数量
  /// @param receiver 套利利润接收者
  /// @param data 交换路径数据
  /// @return amountOut 输出数量
  /// @return bonusOut 套利利润
  function arbitrage(
    address srcToken,
    uint256 amountIn,
    address receiver,
    bytes calldata data
  ) external onlyValidToken(srcToken) onlyPegKeeper nonReentrant sync returns (uint256 amountOut, uint256 bonusOut) {
    address dstToken;
    uint256 expectedOut;
    uint256 cachedTotalYieldToken = totalYieldToken;
    uint256 cachedTotalStableToken = totalStableToken;
    {
      uint256 price = getStableTokenPrice();
      uint256 scaledPrice = price * stableTokenScale;
      if (srcToken == yieldToken) {
        // 用 fxUSD 换 USDC
        // 检查 USDC 是否脱锚
        if (price < stableDepegPrice) revert ErrorStableTokenDepeg();
        if (amountIn > cachedTotalYieldToken) revert ErrorSwapExceedBalance();
        dstToken = stableToken;
        unchecked {
          // 向上取整计算预期输出
          expectedOut = Math.mulDivUp(amountIn, PRECISION, scaledPrice);
          cachedTotalYieldToken -= amountIn;
          cachedTotalStableToken += expectedOut;
        }
      } else {
        // 用 USDC 换 fxUSD
        if (amountIn > cachedTotalStableToken) revert ErrorSwapExceedBalance();
        dstToken = yieldToken;
        unchecked {
          // 向上取整计算预期输出
          expectedOut = Math.mulDivUp(amountIn, scaledPrice, PRECISION);
          cachedTotalStableToken -= amountIn;
          cachedTotalYieldToken += expectedOut;
        }
      }
    }
    // 将源代币转给 PegKeeper 进行交换
    _transferOut(srcToken, amountIn, pegKeeper);
    uint256 actualOut = IERC20(dstToken).balanceOf(address(this));
    amountOut = IPegKeeper(pegKeeper).onSwap(srcToken, dstToken, amountIn, data);
    actualOut = IERC20(dstToken).balanceOf(address(this)) - actualOut;
    // 检查实际交换的代币数量（防止 PegKeeper 被攻击）
    if (amountOut > actualOut) revert ErrorInsufficientOutput();
    // 检查交换没有亏损
    if (amountOut < expectedOut) revert ErrorInsufficientArbitrage();

    totalYieldToken = cachedTotalYieldToken;
    totalStableToken = cachedTotalStableToken;
    // 计算套利利润
    bonusOut = amountOut - expectedOut;
    if (bonusOut > 0) {
      _transferOut(dstToken, bonusOut, receiver);
    }

    emit Arbitrage(_msgSender(), srcToken, amountIn, amountOut, bonusOut);
  }

  /************************
   * 管理函数 *
   ************************/

  /// @notice 更新稳定币脱锚价格阈值
  /// @param newPrice 新的脱锚价格（×1e18）
  function updateStableDepegPrice(uint256 newPrice) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateStableDepegPrice(newPrice);
  }

  /// @notice 更新赎回冷却期
  /// @param newPeriod 新的冷却期（秒）
  function updateRedeemCoolDownPeriod(uint256 newPeriod) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateRedeemCoolDownPeriod(newPeriod);
  }

  /// @notice 更新即时赎回费率
  /// @param newRatio 新的费率（×1e18）
  function updateInstantRedeemFeeRatio(uint256 newRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateInstantRedeemFeeRatio(newRatio);
  }

  /**********************
   * 内部函数 *
   **********************/

  /// @inheritdoc ERC20Upgradeable
  /// @dev 重写转账函数，确保用户不能转移已锁定的份额
  function _update(address from, address to, uint256 value) internal virtual override {
    // 确保发送者不会转移超过可用余额的份额
    if (from != address(0) && to != address(0)) {
      uint256 leftover = balanceOf(from) - redeemRequests[from].amount;
      if (value > leftover) revert ErrorInsufficientFreeBalance();
    }

    super._update(from, to, value);
  }

  /// @dev 内部函数：更新稳定币脱锚价格阈值
  /// @param newPrice 新的脱锚价格（×1e18）
  function _updateStableDepegPrice(uint256 newPrice) internal {
    uint256 oldPrice = stableDepegPrice;
    stableDepegPrice = newPrice;

    emit UpdateStableDepegPrice(oldPrice, newPrice);
  }

  /// @dev 内部函数：更新赎回冷却期
  /// @param newPeriod 新的冷却期（秒）
  function _updateRedeemCoolDownPeriod(uint256 newPeriod) internal {
    // 最大冷却期为 7 天
    if (newPeriod > 7 days) revert ErrorRedeemCoolDownPeriodTooLarge();

    uint256 oldPeriod = redeemCoolDownPeriod;
    redeemCoolDownPeriod = newPeriod;

    emit UpdateRedeemCoolDownPeriod(oldPeriod, newPeriod);
  }

  /// @dev 内部函数：更新即时赎回费率
  /// @param newRatio 新的费率（×1e18）
  function _updateInstantRedeemFeeRatio(uint256 newRatio) internal {
    if (newRatio > MAX_INSTANT_REDEEM_FEE) revert ErrorInstantRedeemFeeTooLarge();

    uint256 oldRatio = instantRedeemFeeRatio;
    instantRedeemFeeRatio = newRatio;

    emit UpdateInstantRedeemFeeRatio(oldRatio, newRatio);
  }

  /// @dev 内部函数：根据存入的代币铸造份额
  /// @param tokenIn 存入的代币地址
  /// @param amountDeposited 存入的代币数量
  /// @return amountSharesOut 铸造的份额数量
  function _deposit(address tokenIn, uint256 amountDeposited) internal virtual returns (uint256 amountSharesOut) {
    uint256 price = getStableTokenPriceWithScale();
    // 检查稳定币是否脱锚
    if (price < stableDepegPrice * stableTokenScale) revert ErrorStableTokenDepeg();

    // 计算存入的 USD 价值
    uint256 amountUSD = amountDeposited;
    if (tokenIn == stableToken) {
      amountUSD = (amountUSD * price) / PRECISION;
    }

    uint256 cachedTotalYieldToken = totalYieldToken;
    uint256 cachedTotalStableToken = totalStableToken;
    uint256 totalUSD = cachedTotalYieldToken + (cachedTotalStableToken * price) / PRECISION;
    uint256 cachedTotalSupply = totalSupply();
    if (cachedTotalSupply == 0) {
      // 首次存款，1:1 铸造份额
      amountSharesOut = amountUSD;
    } else {
      // 按比例计算份额
      amountSharesOut = (amountUSD * cachedTotalSupply) / totalUSD;
    }

    // 更新池中的代币余额
    if (tokenIn == stableToken) {
      totalStableToken = cachedTotalStableToken + amountDeposited;
    } else {
      totalYieldToken = cachedTotalYieldToken + amountDeposited;
    }
  }

  /// @dev 内部钩子函数：再平衡或清算前的准备工作
  /// @param tokenIn 输入代币地址
  /// @param maxAmount 最大输入数量
  /// @return op 内存变量，包含计算结果
  function _beforeRebalanceOrLiquidate(
    address tokenIn,
    uint256 maxAmount
  ) internal view returns (RebalanceMemoryVar memory op) {
    op.stablePrice = getStableTokenPriceWithScale();
    op.totalYieldToken = totalYieldToken;
    op.totalStableToken = totalStableToken;

    uint256 amountYieldToken = op.totalYieldToken;
    uint256 amountStableToken;
    // 优先使用 fxUSD，然后使用 USDC
    if (tokenIn == yieldToken) {
      // 用户支付 fxUSD
      if (maxAmount < amountYieldToken) amountYieldToken = maxAmount;
      else {
        amountStableToken = ((maxAmount - amountYieldToken) * PRECISION) / op.stablePrice;
      }
    } else {
      // 用户支付 USDC
      uint256 maxAmountInUSD = (maxAmount * op.stablePrice) / PRECISION;
      if (maxAmountInUSD < amountYieldToken) amountYieldToken = maxAmountInUSD;
      else {
        amountStableToken = ((maxAmountInUSD - amountYieldToken) * PRECISION) / op.stablePrice;
      }
    }

    // 限制稳定币使用量不超过池中余额
    if (amountStableToken > op.totalStableToken) {
      amountStableToken = op.totalStableToken;
    }

    op.yieldTokenToUse = amountYieldToken;
    op.stableTokenToUse = amountStableToken;
  }

  /// @dev 内部钩子函数：再平衡或清算后的处理
  /// @param tokenIn 输入代币地址
  /// @param minCollOut 最小预期抵押品数量
  /// @param op 内存变量
  /// @return tokenUsed 实际使用的输入代币数量
  function _afterRebalanceOrLiquidate(
    address tokenIn,
    uint256 minCollOut,
    RebalanceMemoryVar memory op
  ) internal returns (uint256 tokenUsed) {
    if (op.colls < minCollOut) revert ErrorInsufficientOutput();

    // 更新池中的代币余额
    op.totalYieldToken -= op.yieldTokenUsed;
    op.totalStableToken -= op.stableTokenUsed;

    // 计算用户需要支付的代币数量
    uint256 amountUSD = op.yieldTokenUsed + (op.stableTokenUsed * op.stablePrice) / PRECISION;
    if (tokenIn == yieldToken) {
      tokenUsed = amountUSD;
      op.totalYieldToken += tokenUsed;
    } else {
      // 向上取整
      tokenUsed = Math.mulDivUp(amountUSD, PRECISION, op.stablePrice);
      op.totalStableToken += tokenUsed;
    }

    totalYieldToken = op.totalYieldToken;
    totalStableToken = op.totalStableToken;

    // 从调用者转入代币（抵押品已经转给调用者了）
    IERC20(tokenIn).safeTransferFrom(_msgSender(), address(this), tokenUsed);

    emit Rebalance(_msgSender(), tokenIn, tokenUsed, op.colls, op.yieldTokenUsed, op.stableTokenUsed);
  }

  /// @dev 内部函数：获取池中的稳定币总量
  /// @return 稳定币总量（包括策略中的资金）
  function _getTotalStableTokenInPool() internal view returns (uint256) {
    // 只管理稳定币
    Allocation memory b = allocations[stableToken];
    if (b.strategy != address(0)) {
      // 包括策略中的资金和合约中的余额
      return IStrategy(b.strategy).totalSupply() + IERC20(stableToken).balanceOf(address(this));
    } else {
      return IERC20(stableToken).balanceOf(address(this));
    }
  }
}
