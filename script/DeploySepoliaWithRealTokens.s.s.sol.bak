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

// Mock contracts - Mintable ERC20
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockAggregatorV3Interface.sol";

// OpenZeppelin interfaces
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title DeploySepoliaWithRealTokens
 * @notice Deploy to Sepolia with mintable token contracts (simulating mainnet tokens)
 * @dev Deploy mintable USDC and wstETH, and mint large amounts to deployer
 */
contract DeploySepoliaWithRealTokens is Script {
    // Deployment addresses
    address public proxyAdmin;
    address public emptyContract;
    
    // Core protocol
    address public poolManagerProxy;
    address public fxUSDProxy;
    address public fxUSDBasePoolProxy;
    address public pegKeeperProxy;
    address public reservePool;
    address public revenuePool;
    
    // Mintable tokens (模拟主网代币)
    address public mintableUSDC;
    address public mintableWstETH;
    
    // Mock oracles
    address public mockUSDCOracle;
    address public mockETHOracle;
    
    // Pool
    address public wstETHPool;
    address public wstETHPriceOracle;
    
    // Configuration parameters
    uint256 constant HARVESTER_RATIO = 100_000_000; // 10%
    uint256 constant FLASH_LOAN_FEE_RATIO = 1_000_000; // 0.1%
    uint256 constant STABLE_DEPEG_PRICE = 990_000_000_000_000_000; // 0.99
    uint256 constant REDEEM_COOLDOWN_PERIOD = 3600; // 1 hour
    
    uint256 constant COLLATERAL_CAPACITY = 1_000_000 ether; // 1,000,000 wstETH
    uint256 constant DEBT_CAPACITY = 1_000_000_000 ether; // 1,000,000,000 fxUSD
    uint256 constant DEBT_RATIO_LOWER = 500_000_000_000_000_000; // 50%
    uint256 constant DEBT_RATIO_UPPER = 857_142_857_142_857_142; // 85.71%
    uint256 constant REBALANCE_DEBT_RATIO = 800_000_000_000_000_000; // 80%
    uint256 constant REBALANCE_BONUS_RATIO = 20_000_000; // 2%
    uint256 constant LIQUIDATE_DEBT_RATIO = 950_000_000_000_000_000; // 95%
    uint256 constant LIQUIDATE_BONUS_RATIO = 40_000_000; // 4%
    
    // 给用户铸造的代币数量（10亿亿）
    uint256 constant MINT_AMOUNT_USDC = 1_000_000_000_000_000 * 10**6; // 10^15 USDC (6 decimals)
    uint256 constant MINT_AMOUNT_WSTETH = 1_000_000_000_000_000 ether; // 10^15 wstETH (18 decimals)
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("==============================================");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("==============================================");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy infrastructure
        console.log("\n=== Step 1: Deploying Infrastructure ===");
        deployInfrastructure(deployer);
        
        // Step 2: Deploy mintable tokens and oracles
        console.log("\n=== Step 2: Deploying Mintable Tokens and Oracles ===");
        deployMintableTokensAndOracles(deployer);
        
        // Step 3: Deploy core protocol
        console.log("\n=== Step 3: Deploying Core Protocol ===");
        deployCoreProtocol(deployer);
        
        // Step 4: Deploy pool
        console.log("\n=== Step 4: Deploying wstETH Pool ===");
        deployPool(deployer);
        
        // Step 5: Mint tokens to deployer
        console.log("\n=== Step 5: Minting Tokens to Deployer ===");
        mintTokensToDeployer(deployer);
        
        // Step 6: Print deployment summary
        console.log("\n=== Deployment Summary ===");
        printDeploymentSummary();
        
        vm.stopBroadcast();
        
        // Save deployment addresses
        saveDeploymentAddresses();
    }
    
    function deployInfrastructure(address admin) internal {
        proxyAdmin = address(new ProxyAdmin(admin));
        console.log("ProxyAdmin:", proxyAdmin);
        
        emptyContract = address(new EmptyContract());
        console.log("EmptyContract:", emptyContract);
    }
    
    function deployMintableTokensAndOracles(address deployer) internal {
        // Deploy mintable USDC (6 decimals, 模拟主网 USDC)
        mintableUSDC = address(new MockERC20("USD Coin", "USDC", 6));
        console.log("Mintable USDC:", mintableUSDC);
        console.log("  Name: USD Coin");
        console.log("  Symbol: USDC");
        console.log("  Decimals: 6");
        
        // Deploy mintable wstETH (18 decimals, 模拟主网 wstETH)
        mintableWstETH = address(new MockERC20("Wrapped liquid staked Ether 2.0", "wstETH", 18));
        console.log("Mintable wstETH:", mintableWstETH);
        console.log("  Name: Wrapped liquid staked Ether 2.0");
        console.log("  Symbol: wstETH");
        console.log("  Decimals: 18");
        
        // Deploy mock oracles (使用主网价格)
        mockUSDCOracle = address(new MockAggregatorV3Interface(
            8,
            "USDC/USD",
            1,
            100_000_000 // $1.00
        ));
        console.log("Mock USDC Oracle:", mockUSDCOracle);
        console.log("  Price: $1.00");
        
        mockETHOracle = address(new MockAggregatorV3Interface(
            8,
            "ETH/USD",
            1,
            3000_00000000 // $3000.00
        ));
        console.log("Mock ETH Oracle:", mockETHOracle);
        console.log("  Price: $3000.00");
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
            admin, // treasury
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
        bytes memory priceOracleData = abi.encode(mockUSDCOracle, mockUSDCOracle, address(0), uint256(0));
        
        address fxUSDBasePoolImpl = address(new FxUSDBasePool(
            poolManagerProxy,
            pegKeeperProxy,
            fxUSDProxy,
            mintableUSDC,
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
            address(0), // no converter for now
            address(0)  // no curve pool for now
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
            mintableUSDC,
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
            mockETHOracle,
            mockETHOracle,
            address(0), // no rate provider
            50_000_000_000_000_000 // 5% max deviation
        ));
        console.log("WstETH Price Oracle:", wstETHPriceOracle);
        
        // Deploy pool implementation
        address poolImpl = address(new AaveFundingPool(
            poolManagerProxy,
            address(0) // no pool configuration
        ));
        console.log("AaveFundingPool Implementation:", poolImpl);
        
        // Prepare initialization data
        bytes memory poolInitData = abi.encodeWithSelector(
            AaveFundingPool.initialize.selector,
            admin,
            "f(x) wstETH Position",
            "xwstETH",
            mintableWstETH,
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
    
    function mintTokensToDeployer(address deployer) internal {
        console.log("Minting tokens to deployer:", deployer);
        
        // Mint USDC (10^15 USDC with 6 decimals)
        MockERC20(mintableUSDC).mint(deployer, MINT_AMOUNT_USDC);
        console.log("Minted USDC:", MINT_AMOUNT_USDC);
        console.log("  = 1,000,000,000,000,000 USDC");
        
        // Mint wstETH (10^15 wstETH with 18 decimals)
        MockERC20(mintableWstETH).mint(deployer, MINT_AMOUNT_WSTETH);
        console.log("Minted wstETH:", MINT_AMOUNT_WSTETH);
        console.log("  = 1,000,000,000,000,000 wstETH");
        
        // Verify balances
        uint256 usdcBalance = MockERC20(mintableUSDC).balanceOf(deployer);
        uint256 wstETHBalance = MockERC20(mintableWstETH).balanceOf(deployer);
        
        console.log("\nDeployer balances:");
        console.log("  USDC:", usdcBalance);
        console.log("  wstETH:", wstETHBalance);
    }
    
    function printDeploymentSummary() internal view {
        console.log("==============================================");
        console.log("Infrastructure:");
        console.log("  ProxyAdmin:", proxyAdmin);
        console.log("  EmptyContract:", emptyContract);
        console.log("");
        console.log("Mintable Tokens:");
        console.log("  USDC:", mintableUSDC);
        console.log("  wstETH:", mintableWstETH);
        console.log("");
        console.log("Oracles:");
        console.log("  USDC Oracle:", mockUSDCOracle);
        console.log("  ETH Oracle:", mockETHOracle);
        console.log("");
        console.log("Core Protocol:");
        console.log("  PoolManager:", poolManagerProxy);
        console.log("  FxUSD:", fxUSDProxy);
        console.log("  FxUSDBasePool:", fxUSDBasePoolProxy);
        console.log("  PegKeeper:", pegKeeperProxy);
        console.log("  ReservePool:", reservePool);
        console.log("  RevenuePool:", revenuePool);
        console.log("");
        console.log("Pools:");
        console.log("  WstETH Pool:", wstETHPool);
        console.log("  WstETH Price Oracle:", wstETHPriceOracle);
        console.log("==============================================");
    }
    
    function saveDeploymentAddresses() internal {
        string memory json = "deployment";
        
        vm.serializeAddress(json, "ProxyAdmin", proxyAdmin);
        vm.serializeAddress(json, "EmptyContract", emptyContract);
        vm.serializeAddress(json, "MintableUSDC", mintableUSDC);
        vm.serializeAddress(json, "MintableWstETH", mintableWstETH);
        vm.serializeAddress(json, "MockUSDCOracle", mockUSDCOracle);
        vm.serializeAddress(json, "MockETHOracle", mockETHOracle);
        vm.serializeAddress(json, "PoolManager", poolManagerProxy);
        vm.serializeAddress(json, "FxUSD", fxUSDProxy);
        vm.serializeAddress(json, "FxUSDBasePool", fxUSDBasePoolProxy);
        vm.serializeAddress(json, "PegKeeper", pegKeeperProxy);
        vm.serializeAddress(json, "ReservePool", reservePool);
        vm.serializeAddress(json, "RevenuePool", revenuePool);
        vm.serializeAddress(json, "WstETHPool", wstETHPool);
        string memory finalJson = vm.serializeAddress(json, "WstETHPriceOracle", wstETHPriceOracle);
        
        vm.writeJson(finalJson, "./deployments/sepolia-real-tokens.json");
        console.log("\nDeployment addresses saved to: ./deployments/sepolia-real-tokens.json");
    }
}
