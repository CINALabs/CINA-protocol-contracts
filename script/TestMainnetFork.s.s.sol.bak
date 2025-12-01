// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Core contracts
import "../contracts/core/PoolManager.sol";
import "../contracts/core/FxUSDRegeneracy.sol";
import "../contracts/core/FxUSDBasePool.sol";
import "../contracts/core/PegKeeper.sol";
import "../contracts/core/ReservePool.sol";

// Helper contracts
import "../contracts/helpers/ProxyAdmin.sol";
import "../contracts/helpers/EmptyContract.sol";
import "../contracts/helpers/TransparentUpgradeableProxy.sol";
import "../contracts/helpers/RevenuePool.sol";

// Pool contracts
import "../contracts/core/pool/AaveFundingPool.sol";

// Price oracle
import "../contracts/price-oracle/ETHPriceOracle.sol";

// Interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title TestMainnetFork
 * @notice 在 Fork 主网上部署和测试 f(x) Protocol
 * @dev 使用主网真实的 wstETH 和 USDC 地址
 */
contract TestMainnetFork is Script {
    // ============================================
    // 主网代币地址
    // ============================================
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    
    // Chainlink 主网价格预言机
    address constant USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    
    // ============================================
    // 部署的合约地址
    // ============================================
    address public proxyAdmin;
    address public emptyContract;
    
    address public poolManagerProxy;
    address public fxUSDProxy;
    address public fxUSDBasePoolProxy;
    address public pegKeeperProxy;
    address public reservePool;
    address public revenuePool;
    
    address public wstETHPool;
    address public wstETHPriceOracle;
    
    // ============================================
    // 配置参数
    // ============================================
    uint256 constant HARVESTER_RATIO = 100_000_000; // 10%
    uint256 constant FLASH_LOAN_FEE_RATIO = 1_000_000; // 0.1%
    uint256 constant STABLE_DEPEG_PRICE = 990_000_000_000_000_000; // 0.99
    uint256 constant REDEEM_COOLDOWN_PERIOD = 3600; // 1 hour
    
    uint256 constant COLLATERAL_CAPACITY = 1_000_000 ether;
    uint256 constant DEBT_CAPACITY = 3_000_000_000 ether;
    uint256 constant DEBT_RATIO_LOWER = 500_000_000_000_000_000; // 50%
    uint256 constant DEBT_RATIO_UPPER = 857_142_857_142_857_142; // 85.71%
    uint256 constant REBALANCE_DEBT_RATIO = 800_000_000_000_000_000; // 80%
    uint256 constant REBALANCE_BONUS_RATIO = 20_000_000; // 2%
    uint256 constant LIQUIDATE_DEBT_RATIO = 950_000_000_000_000_000; // 95%
    uint256 constant LIQUIDATE_BONUS_RATIO = 40_000_000; // 4%
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("\n==============================================");
        console.log("Fork Mainnet Deployment and Test");
        console.log("==============================================");
        console.log("Deployer:", deployer);
        console.log("wstETH:", WSTETH);
        console.log("USDC:", USDC);
        console.log("==============================================\n");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: 准备测试代币
        console.log("=== Step 1: Preparing Test Tokens ===");
        prepareTestTokens(deployer);
        
        // Step 2: 部署基础设施
        console.log("\n=== Step 2: Deploying Infrastructure ===");
        deployInfrastructure(deployer);
        
        // Step 3: 部署核心协议
        console.log("\n=== Step 3: Deploying Core Protocol ===");
        deployCoreProtocol(deployer);
        
        // Step 4: 部署池子
        console.log("\n=== Step 4: Deploying wstETH Pool ===");
        deployPool(deployer);
        
        // Step 5: 测试开仓
        console.log("\n=== Step 5: Testing Open Position ===");
        testOpenPosition(deployer);
        
        vm.stopBroadcast();
        
        // Step 6: 保存部署地址
        console.log("\n=== Step 6: Saving Deployment Addresses ===");
        saveDeploymentAddresses();
        
        console.log("\n==============================================");
        console.log("Deployment and Test Completed!");
        console.log("==============================================");
    }
    
    function prepareTestTokens(address user) internal {
        // 使用 deal 给用户设置代币余额
        deal(WSTETH, user, 100 ether); // 100 wstETH
        deal(USDC, user, 100_000 * 1e6); // 100,000 USDC
        
        console.log("Set token balances:");
        console.log("  wstETH:", IERC20(WSTETH).balanceOf(user) / 1e18, "wstETH");
        console.log("  USDC:", IERC20(USDC).balanceOf(user) / 1e6, "USDC");
    }
    
    function deployInfrastructure(address admin) internal {
        proxyAdmin = address(new ProxyAdmin(admin));
        console.log("ProxyAdmin:", proxyAdmin);
        
        emptyContract = address(new EmptyContract());
        console.log("EmptyContract:", emptyContract);
    }
    
    function deployCoreProtocol(address admin) internal {
        // Deploy proxies
        poolManagerProxy = address(new TransparentUpgradeableProxy(
            emptyContract,
            proxyAdmin,
            ""
        ));
        console.log("PoolManagerProxy:", poolManagerProxy);
        
        fxUSDProxy = address(new TransparentUpgradeableProxy(
            emptyContract,
            proxyAdmin,
            ""
        ));
        console.log("FxUSDProxy:", fxUSDProxy);
        
        fxUSDBasePoolProxy = address(new TransparentUpgradeableProxy(
            emptyContract,
            proxyAdmin,
            ""
        ));
        console.log("FxUSDBasePoolProxy:", fxUSDBasePoolProxy);
        
        pegKeeperProxy = address(new TransparentUpgradeableProxy(
            emptyContract,
            proxyAdmin,
            ""
        ));
        console.log("PegKeeperProxy:", pegKeeperProxy);
        
        // Deploy ReservePool and RevenuePool
        reservePool = address(new ReservePool(admin, poolManagerProxy));
        console.log("ReservePool:", reservePool);
        
        revenuePool = address(new RevenuePool(admin, admin, admin));
        console.log("RevenuePool:", revenuePool);
        
        // Deploy and initialize PoolManager
        address poolManagerImpl = address(new PoolManager(
            fxUSDProxy,
            fxUSDBasePoolProxy,
            pegKeeperProxy
        ));
        console.log("PoolManager Implementation:", poolManagerImpl);
        
        bytes memory poolManagerInitData = abi.encodeWithSelector(
            PoolManager.initialize.selector,
            admin,
            0,
            HARVESTER_RATIO,
            FLASH_LOAN_FEE_RATIO,
            admin,
            revenuePool,
            reservePool
        );
        
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(poolManagerProxy),
            poolManagerImpl,
            poolManagerInitData
        );
        console.log("PoolManager initialized");
        
        // Deploy and initialize FxUSDBasePool
        bytes memory priceOracleData = abi.encode(USDC_USD_FEED, USDC_USD_FEED, address(0), uint256(0));
        
        address fxUSDBasePoolImpl = address(new FxUSDBasePool(
            poolManagerProxy,
            pegKeeperProxy,
            fxUSDProxy,
            USDC,
            priceOracleData
        ));
        console.log("FxUSDBasePool Implementation:", fxUSDBasePoolImpl);
        
        bytes memory fxUSDBasePoolInitData = abi.encodeWithSelector(
            FxUSDBasePool.initialize.selector,
            admin,
            "fxUSD Save",
            "fxBASE",
            STABLE_DEPEG_PRICE,
            REDEEM_COOLDOWN_PERIOD
        );
        
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(fxUSDBasePoolProxy),
            fxUSDBasePoolImpl,
            fxUSDBasePoolInitData
        );
        console.log("FxUSDBasePool initialized");
        
        // Deploy and initialize PegKeeper
        address pegKeeperImpl = address(new PegKeeper(fxUSDBasePoolProxy));
        console.log("PegKeeper Implementation:", pegKeeperImpl);
        
        bytes memory pegKeeperInitData = abi.encodeWithSelector(
            PegKeeper.initialize.selector,
            admin,
            address(0),
            address(0)
        );
        
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(pegKeeperProxy),
            pegKeeperImpl,
            pegKeeperInitData
        );
        console.log("PegKeeper initialized");
        
        // Deploy and initialize FxUSD
        address fxUSDImpl = address(new FxUSDRegeneracy(
            poolManagerProxy,
            USDC,
            pegKeeperProxy
        ));
        console.log("FxUSD Implementation:", fxUSDImpl);
        
        bytes memory fxUSDInitData = abi.encodeWithSelector(
            FxUSDRegeneracy.initialize.selector,
            admin,
            "f(x) USD",
            "fxUSD"
        );
        
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(fxUSDProxy),
            fxUSDImpl,
            fxUSDInitData
        );
        console.log("FxUSD initialized");
    }
    
    function deployPool(address admin) internal {
        // Deploy price oracle
        wstETHPriceOracle = address(new ETHPriceOracle(
            ETH_USD_FEED,
            ETH_USD_FEED,
            address(0),
            50_000_000_000_000_000 // 5% max deviation
        ));
        console.log("WstETH Price Oracle:", wstETHPriceOracle);
        
        // Deploy pool implementation
        address poolImpl = address(new AaveFundingPool(
            poolManagerProxy,
            address(0)
        ));
        console.log("AaveFundingPool Implementation:", poolImpl);
        
        // Prepare initialization data
        bytes memory poolInitData = abi.encodeWithSelector(
            AaveFundingPool.initialize.selector,
            admin,
            "f(x) wstETH Position",
            "xwstETH",
            WSTETH,
            wstETHPriceOracle
        );
        
        // Deploy proxy
        wstETHPool = address(new TransparentUpgradeableProxy(
            poolImpl,
            proxyAdmin,
            poolInitData
        ));
        console.log("WstETH Pool:", wstETHPool);
        
        // Configure pool parameters
        AaveFundingPool pool = AaveFundingPool(wstETHPool);
        
        pool.updateDebtRatioRange(DEBT_RATIO_LOWER, DEBT_RATIO_UPPER);
        console.log("Debt ratio range updated");
        
        pool.updateRebalanceRatios(REBALANCE_DEBT_RATIO, REBALANCE_BONUS_RATIO);
        console.log("Rebalance ratios updated");
        
        pool.updateLiquidateRatios(LIQUIDATE_DEBT_RATIO, LIQUIDATE_BONUS_RATIO);
        console.log("Liquidate ratios updated");
        
        pool.updateBorrowAndRedeemStatus(true, true);
        console.log("Borrow and redeem enabled");
        
        // Register pool in PoolManager
        PoolManager(poolManagerProxy).registerPool(
            wstETHPool,
            COLLATERAL_CAPACITY,
            DEBT_CAPACITY
        );
        console.log("Pool registered in PoolManager");
    }
    
    function testOpenPosition(address user) internal {
        console.log("Testing open position for user:", user);
        
        // Check initial balances
        uint256 wstETHBefore = IERC20(WSTETH).balanceOf(user);
        console.log("Initial wstETH balance:", wstETHBefore / 1e18, "wstETH");
        
        // Approve wstETH
        IERC20(WSTETH).approve(poolManagerProxy, type(uint256).max);
        console.log("Approved wstETH to PoolManager");
        
        // Open position: 10 wstETH collateral, 15,000 fxUSD debt
        uint256 collateralAmount = 10 ether;
        uint256 debtAmount = 15_000 ether;
        
        console.log("Opening position:");
        console.log("  Collateral:", collateralAmount / 1e18, "wstETH");
        console.log("  Debt:", debtAmount / 1e18, "fxUSD");
        
        PoolManager(poolManagerProxy).operate(
            wstETHPool,
            0, // new position
            collateralAmount,
            debtAmount,
            false
        );
        
        console.log("Position opened successfully!");
        
        // Query position
        uint256 positionId = 1;
        (uint256 colls, uint256 debts) = AaveFundingPool(wstETHPool).getPosition(positionId);
        console.log("Position ID:", positionId);
        console.log("  Collateral:", colls / 1e18, "wstETH");
        console.log("  Debt:", debts / 1e18, "fxUSD");
        
        // Check balances after
        uint256 wstETHAfter = IERC20(WSTETH).balanceOf(user);
        uint256 fxUSDBalance = IERC20(fxUSDProxy).balanceOf(user);
        console.log("After opening:");
        console.log("  wstETH balance:", wstETHAfter / 1e18, "wstETH");
        console.log("  fxUSD balance:", fxUSDBalance / 1e18, "fxUSD");
        
        // Calculate debt ratio
        // Assuming ETH price from oracle, but for simplicity use $3000
        uint256 collateralValue = colls * 3000; // in USD
        uint256 debtRatio = (debts * 1e18) / collateralValue;
        console.log("  Debt ratio:", (debtRatio * 100) / 1e18, "%");
    }
    
    function saveDeploymentAddresses() internal {
        string memory json = "deployment";
        
        vm.serializeAddress(json, "ProxyAdmin", proxyAdmin);
        vm.serializeAddress(json, "EmptyContract", emptyContract);
        vm.serializeAddress(json, "WSTETH", WSTETH);
        vm.serializeAddress(json, "USDC", USDC);
        vm.serializeAddress(json, "PoolManager", poolManagerProxy);
        vm.serializeAddress(json, "FxUSD", fxUSDProxy);
        vm.serializeAddress(json, "FxUSDBasePool", fxUSDBasePoolProxy);
        vm.serializeAddress(json, "PegKeeper", pegKeeperProxy);
        vm.serializeAddress(json, "ReservePool", reservePool);
        vm.serializeAddress(json, "RevenuePool", revenuePool);
        vm.serializeAddress(json, "WstETHPool", wstETHPool);
        string memory finalJson = vm.serializeAddress(json, "WstETHPriceOracle", wstETHPriceOracle);
        
        vm.writeJson(finalJson, "./deployments/mainnet-fork.json");
        console.log("Deployment addresses saved to: ./deployments/mainnet-fork.json");
    }
}
