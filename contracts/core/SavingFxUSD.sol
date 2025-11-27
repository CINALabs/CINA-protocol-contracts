// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ERC20PermitUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import { IMultipleRewardDistributor } from "../common/rewards/distributor/IMultipleRewardDistributor.sol";
import { IHarvesterCallback } from "../helpers/interfaces/IHarvesterCallback.sol";
import { IConvexFXNBooster } from "../interfaces/Convex/IConvexFXNBooster.sol";
import { IStakingProxyERC20 } from "../interfaces/Convex/IStakingProxyERC20.sol";
import { IFxUSDBasePool } from "../interfaces/IFxUSDBasePool.sol";
import { ISavingFxUSD } from "../interfaces/ISavingFxUSD.sol";
import { ILiquidityGauge } from "../voting-escrow/interfaces/ILiquidityGauge.sol";

import { WordCodec } from "../common/codec/WordCodec.sol";
import { ConcentratorBase } from "../common/concentrator/ConcentratorBase.sol";

/// @title LockedFxSaveProxy - 锁定 fxSave 代理合约
/// @notice 为每个用户创建的代理合约，用于处理锁定期赎回
/// @dev 当用户请求赎回时，资产会转移到此代理合约中等待解锁
contract LockedFxSaveProxy {
  /// @notice fxSAVE 合约地址
  address immutable fxSAVE;

  /// @dev 当调用者不是 fxSAVE 时抛出
  error ErrorCallerNotFxSave();

  /// @notice 构造函数，记录创建者（fxSAVE）地址
  constructor() {
    fxSAVE = msg.sender;
  }

  /// @notice 执行目标合约调用
  /// @dev 仅 fxSAVE 可调用，用于代理执行赎回操作
  /// @param target 目标合约地址
  /// @param data 调用数据
  function execute(address target, bytes calldata data) external {
    if (msg.sender != fxSAVE) revert ErrorCallerNotFxSave();

    (bool success, ) = target.call(data);
    // 以下代码将内部错误向上传播
    if (!success) {
      // solhint-disable-next-line no-inline-assembly
      assembly {
        let ptr := mload(0x40)
        let size := returndatasize()
        returndatacopy(ptr, 0, size)
        revert(ptr, size)
      }
    }
  }
}

/// @title SavingFxUSD - fxUSD 储蓄合约
/// @notice 允许用户存入 fxBASE 代币并获得收益
/// @dev 实现 ERC4626 金库标准，通过 Convex 进行收益增强
///
/// ==================== 储蓄机制概述 ====================
///
/// 1. 存款流程
///    - 用户存入 fxBASE 代币
///    - 合约铸造 fxSAVE 份额给用户
///    - 当余额达到阈值时，批量存入 Gauge 获取收益
///
/// 2. 赎回流程
///    - 即时赎回: 直接从 Gauge 提取并转给用户
///    - 延迟赎回: 请求赎回 -> 等待冷却期 -> 领取
///
/// 3. 收益来源
///    - Gauge 质押奖励（FXN 等）
///    - 通过 Convex 增强的收益
///
/// 4. 收益分配
///    - 收割者奖励: 激励调用 harvest 的用户
///    - 协议费用: 分配给国库
///    - 剩余收益: 分配给收割者指定的接收者
///
contract SavingFxUSD is ERC20PermitUpgradeable, ERC4626Upgradeable, ConcentratorBase, ISavingFxUSD {
  using SafeERC20 for IERC20;
  using WordCodec for bytes32;

  /**********
   * 错误定义 *
   **********/

  /// @dev 当阈值超过 `MAX_THRESHOLD` 时抛出
  error ErrorThresholdTooLarge();

  /*************
   * 常量定义 *
   *************/

  /// @notice `claimFor` 函数的角色标识符
  /// @dev 拥有此角色的地址可以代替其他用户领取
  bytes32 public constant CLAIM_FOR_ROLE = keccak256("CLAIM_FOR_ROLE");

  /// @dev Convex f(x) Booster 合约地址
  address private constant BOOSTER = 0xAffe966B27ba3E4Ebb8A0eC124C7b7019CC762f8;

  /// @dev FXN 代币地址
  address private constant FXN = 0x365AccFCa291e7D3914637ABf1F7635dB165Bb09;

  /// @dev 计算精度 (1e18)
  uint256 private constant PRECISION = 1e18;

  /// @dev 阈值的位数
  uint256 private constant THRESHOLD_BITS = 80;

  /// @dev 阈值在 `_miscData` 中的位偏移量
  uint256 private constant THRESHOLD_OFFSET = 60;
  
  /// @dev 阈值的最大值 (2^80-1)
  uint256 private constant MAX_THRESHOLD = 1208925819614629174706175;

  /***********************
   * 不可变变量 *
   ***********************/

  /// @notice FxUSDBasePool 合约地址
  address public immutable base;

  /// @notice FxUSDBasePool Gauge 合约地址
  address public immutable gauge;

  /*************
   * 存储变量 *
   *************/

  /// @notice Convex StakingProxyERC20 合约地址
  /// @dev 用于通过 Convex 增强 Gauge 收益
  address public vault;

  /// @notice 用户地址到 LockedFxSaveProxy 合约的映射
  /// @dev 每个用户有一个专属的代理合约用于处理锁定期赎回
  mapping(address => address) public lockedProxy;

  /***************
   * 构造函数 *
   ***************/

  /// @dev 初始化参数结构体
  struct InitializationParameters {
    string name;      // 代币名称
    string symbol;    // 代币符号
    uint256 pid;      // Convex 池 ID
    uint256 threshold; // 批量存款阈值
    address treasury;  // 国库地址
    address harvester; // 收割者地址
  }

  /// @notice 构造函数
  /// @param _base FxUSDBasePool 合约地址
  /// @param _gauge Gauge 合约地址
  constructor(address _base, address _gauge) {
    base = _base;
    gauge = _gauge;
  }

  /// @notice 初始化函数（代理模式）
  /// @param admin 管理员地址
  /// @param params 初始化参数
  function initialize(address admin, InitializationParameters memory params) external initializer {
    __Context_init();
    __ERC165_init();
    __AccessControl_init();

    __ERC20_init(params.name, params.symbol);
    __ERC20Permit_init(params.name);
    __ERC4626_init(IERC20(base));

    __ConcentratorBase_init(params.treasury, params.harvester);

    _grantRole(DEFAULT_ADMIN_ROLE, admin);

    // 通过 Convex Booster 创建质押金库
    vault = IConvexFXNBooster(BOOSTER).createVault(params.pid);
    _updateThreshold(params.threshold);

    // 授权 Gauge 无限额度
    IERC20(base).forceApprove(gauge, type(uint256).max);
  }

  /*************************
   * 公共视图函数 *
   *************************/

  /// @inheritdoc ERC4626Upgradeable
  /// @notice 返回代币精度
  function decimals() public view virtual override(ERC20Upgradeable, ERC4626Upgradeable) returns (uint8) {
    return ERC4626Upgradeable.decimals();
  }

  /// @inheritdoc ERC4626Upgradeable
  /// @notice 返回总资产数量
  /// @dev 包括合约中的 fxBASE 余额和 Gauge 中的质押余额
  function totalAssets() public view virtual override returns (uint256) {
    return IERC20(base).balanceOf(address(this)) + IERC20(gauge).balanceOf(vault);
  }

  /// @notice 返回批量存款阈值
  /// @return 当 fxBASE 余额达到此阈值时，会批量存入 Gauge
  function getThreshold() public view returns (uint256) {
    return _miscData.decodeUint(THRESHOLD_OFFSET, THRESHOLD_BITS);
  }

  /// @inheritdoc ISavingFxUSD
  /// @notice 返回每份 fxSAVE 的净资产价值 (NAV)
  /// @return NAV 值（×1e18）
  function nav() external view returns (uint256) {
    return (IFxUSDBasePool(base).nav() * convertToAssets(PRECISION)) / PRECISION;
  }

  /****************************
   * 公共状态修改函数 *
   ****************************/

  /// @inheritdoc ISavingFxUSD
  /// @notice 直接存入 Gauge 代币
  /// @dev 允许用户直接存入 Gauge 代币而不是 fxBASE
  /// @param assets 存入的 Gauge 代币数量
  /// @param receiver 份额接收者地址
  /// @return 铸造的份额数量
  function depositGauge(uint256 assets, address receiver) external returns (uint256) {
    uint256 maxAssets = maxDeposit(receiver);
    if (assets > maxAssets) {
      revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
    }

    uint256 shares = previewDeposit(assets);

    // 直接将 Gauge 代币转入 Convex vault
    IERC20(gauge).safeTransferFrom(_msgSender(), vault, assets);
    _mint(receiver, shares);

    emit Deposit(_msgSender(), receiver, assets, shares);

    return shares;
  }

  /// @inheritdoc ISavingFxUSD
  /// @notice 请求赎回（延迟赎回）
  /// @dev 资产会被锁定在代理合约中，等待 fxBASE 的冷却期
  /// @param shares 要赎回的份额数量
  /// @return 预计可赎回的资产数量
  function requestRedeem(uint256 shares) external returns (uint256) {
    address owner = _msgSender();
    uint256 maxShares = maxRedeem(owner);
    if (shares > maxShares) {
      revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
    }

    uint256 assets = previewRedeem(shares);
    _requestRedeem(owner, assets, shares);

    return assets;
  }

  /// @inheritdoc ISavingFxUSD
  /// @notice 领取已解锁的资产
  /// @param receiver 资产接收者地址
  function claim(address receiver) external {
    _claim(_msgSender(), receiver);
  }

  /// @inheritdoc ISavingFxUSD
  /// @notice 代替其他用户领取已解锁的资产
  /// @dev 仅拥有 CLAIM_FOR_ROLE 角色的地址可调用
  /// @param owner 资产所有者地址
  /// @param receiver 资产接收者地址
  function claimFor(address owner, address receiver) external onlyRole(CLAIM_FOR_ROLE) {
    _claim(owner, receiver);
  }

  /// @inheritdoc ISavingFxUSD
  /// @notice 收割奖励
  /// @dev 从 Convex vault 获取奖励并分配给各方
  function harvest() external {
    // 从 Convex vault 获取奖励
    IStakingProxyERC20(vault).getReward();
    address[] memory tokens = IMultipleRewardDistributor(gauge).getActiveRewardTokens();
    address cachedHarvester = harvester;
    uint256 harvesterRatio = getHarvesterRatio();
    uint256 expenseRatio = getExpenseRatio();
    bool hasFXN = false;
    // 分配所有奖励代币
    for (uint256 i = 0; i < tokens.length; ++i) {
      _transferRewards(tokens[i], cachedHarvester, harvesterRatio, expenseRatio);
      if (tokens[i] == FXN) hasFXN = true;
    }
    // 确保 FXN 奖励也被分配
    if (!hasFXN) {
      _transferRewards(FXN, cachedHarvester, harvesterRatio, expenseRatio);
    }
  }

  /************************
   * 管理函数 *
   ************************/

  /// @notice 更新批量存款阈值
  /// @param newThreshold 新的阈值
  function updateThreshold(uint256 newThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _updateThreshold(newThreshold);
  }

  /**********************
   * 内部函数 *
   **********************/

  /// @inheritdoc ERC4626Upgradeable
  /// @dev 存款时，如果余额达到阈值，批量存入 Gauge
  function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
    ERC4626Upgradeable._deposit(caller, receiver, assets, shares);

    // 当余额达到阈值时，批量存入 Gauge（通过 Convex vault）
    uint256 balance = IERC20(base).balanceOf(address(this));
    if (balance >= getThreshold()) {
      ILiquidityGauge(gauge).deposit(balance, vault);
    }
  }

  /// @inheritdoc ERC4626Upgradeable
  /// @dev 提款时，从 Gauge 提取资产
  function _withdraw(
    address caller,
    address receiver,
    address owner,
    uint256 assets,
    uint256 shares
  ) internal virtual override {
    if (caller != owner) {
      _spendAllowance(owner, caller, shares);
    }

    // 如果 _asset 是 ERC777，`transfer` 可能通过 `tokensReceived` 钩子触发重入攻击。
    // 另一方面，`tokensToSend` 钩子在转账前触发，调用 vault（假设不是恶意的）。
    //
    // 结论：我们需要在销毁后进行转账，这样任何重入都会发生在
    // 份额被销毁和资产被转移之后，这是一个有效状态。
    _burn(owner, shares);

    emit Withdraw(caller, receiver, owner, assets, shares);

    // 从 Gauge 提取
    IStakingProxyERC20(vault).withdraw(assets);
    IERC20(base).transfer(receiver, assets);
  }

  /// @inheritdoc ConcentratorBase
  /// @dev 收割回调：将收益转换为 fxBASE 并存入 Gauge
  function _onHarvest(address token, uint256 amount) internal virtual override {
    if (token == gauge) {
      // 如果是 Gauge 代币，直接转入 vault
      IERC20(gauge).safeTransfer(vault, amount);
      return;
    } else if (token != base) {
      // 如果不是 fxBASE，先存入 fxBASE 池转换
      IERC20(token).forceApprove(base, amount);
      IFxUSDBasePool(base).deposit(address(this), token, amount, 0);
    }
    // 将所有 fxBASE 存入 Gauge
    amount = IERC20(base).balanceOf(address(this));
    ILiquidityGauge(gauge).deposit(amount, vault);
  }

  /// @dev 内部函数：更新批量存款阈值
  /// @param newThreshold 新的阈值
  function _updateThreshold(uint256 newThreshold) internal {
    if (newThreshold > MAX_THRESHOLD) revert ErrorThresholdTooLarge();

    bytes32 _data = _miscData;
    uint256 oldThreshold = _miscData.decodeUint(THRESHOLD_OFFSET, THRESHOLD_BITS);
    _miscData = _data.insertUint(newThreshold, THRESHOLD_OFFSET, THRESHOLD_BITS);

    emit UpdateThreshold(oldThreshold, newThreshold);
  }

  /// @dev 内部函数：分配奖励给各方
  /// @param token 奖励代币地址
  /// @param receiver 收割者指定的接收者地址
  /// @param harvesterRatio 收割者奖励比率
  /// @param expenseRatio 协议费用比率
  function _transferRewards(address token, address receiver, uint256 harvesterRatio, uint256 expenseRatio) internal {
    if (token == base) return; // 跳过 fxBASE
    uint256 balance = IERC20(token).balanceOf(address(this));
    if (balance > 0) {
      // 计算各方份额
      uint256 performanceFee = (balance * expenseRatio) / FEE_PRECISION;
      uint256 harvesterBounty = (balance * harvesterRatio) / FEE_PRECISION;
      // 转给收割者（调用者）
      if (harvesterBounty > 0) {
        IERC20(token).safeTransfer(_msgSender(), harvesterBounty);
      }
      // 转给国库
      if (performanceFee > 0) {
        IERC20(token).safeTransfer(treasury, performanceFee);
      }
      // 剩余转给指定接收者
      IERC20(token).safeTransfer(receiver, balance - performanceFee - harvesterBounty);
    }
  }

  /// @dev 内部函数：请求赎回
  /// @param owner 份额所有者
  /// @param assets 资产数量
  /// @param shares 份额数量
  function _requestRedeem(address owner, uint256 assets, uint256 shares) internal {
    // 销毁份额
    _burn(owner, shares);

    // 从 Gauge 提取
    IStakingProxyERC20(vault).withdraw(assets);

    // 创建或获取用户的锁定代理合约
    address proxy = lockedProxy[owner];
    if (proxy == address(0)) {
      proxy = address(new LockedFxSaveProxy{ salt: keccak256(abi.encode(owner)) }());
      lockedProxy[owner] = proxy;
    }

    // 转移资产到代理合约并请求解锁
    IERC20(base).transfer(proxy, assets);
    LockedFxSaveProxy(proxy).execute(base, abi.encodeCall(IFxUSDBasePool.requestRedeem, (assets)));

    emit RequestRedeem(owner, shares, assets);
  }

  /// @dev 内部函数：领取已解锁的代币
  /// @param owner 资产所有者
  /// @param receiver 资产接收者
  function _claim(address owner, address receiver) internal {
    address proxy = lockedProxy[owner];
    LockedFxSaveProxy(proxy).execute(base, abi.encodeCall(IFxUSDBasePool.redeem, (receiver, type(uint256).max)));

    emit Claim(owner, receiver);
  }
}
