// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Helper contracts (no OZ upgradeable conflicts)
import "../contracts/helpers/ProxyAdmin.sol";
import "../contracts/helpers/EmptyContract.sol";
import "../contracts/helpers/TransparentUpgradeableProxy.sol";
import "../contracts/helpers/RevenuePool.sol";

// OpenZeppelin interfaces
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// Mock contracts for testing
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockAggregatorV3Interface.sol";

// Import interfaces only to avoid OZ v4/v5 conflicts
import "../contracts/interfaces/IPoolManager.sol";
import "../contracts/interfaces/IFxUSDRegeneracy.sol";
import "../contracts/interfaces/IFxUSDBasePool.sol";
import "../contracts/interfaces/IPegKeeper.sol";
import "../contracts/interfaces/IReservePool.sol";
import "../contracts/interfaces/IAaveFundingPool.sol";
import "../contracts/interfaces/IPool.sol";

contract DeploySepolia is Script {
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
    
    // Mock tokens
    address public mockUSDC;
    address public mockWstETH;
    
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
    
    uint256 constant COLLATERAL_CAPACITY = 1000 ether; // 1000 wstETH
    uint256 constant DEBT_CAPACITY = 500_000 ether; // 500,000 fxUSD
    uint256 constant DEBT_RATIO_LOWER = 500_000_000_000_000_000; // 50%
    uint256 constant DEBT_RATIO_UPPER = 857_142_857_142_857_142; // 85.71%
    uint256 constant REBALANCE_DEBT_RATIO = 800_000_000_000_000_000; // 80%
    uint256 constant REBALANCE_BONUS_RATIO = 20_000_000; // 2%
    uint256 constant LIQUIDATE_DEBT_RATIO = 950_000_000_000_000_000; // 95%
    uint256 constant LIQUIDATE_BONUS_RATIO = 40_000_000; // 4%
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy infrastructure
        console.log("\n=== Step 1: Deploying Infrastructure ===");
        deployInfrastructure(deployer);
        
        // Step 2: Deploy mock tokens and oracles
        console.log("\n=== Step 2: Deploying Mock Tokens and Oracles ===");
        deployMocks(deployer);
        
        // Step 3: Deploy core protocol
        console.log("\n=== Step 3: Deploying Core Protocol ===");
        deployCoreProtocol(deployer);
        
        // Step 4: Deploy pool
        console.log("\n=== Step 4: Deploying wstETH Pool ===");
        deployPool(deployer);
        
        // Step 5: Print deployment summary
        console.log("\n=== Deployment Summary ===");
        printDeploymentSummary();
        
        vm.stopBroadcast();
        
        // Save deployment addresses
        saveDeploymentAddresses();
    }
    
    function deployInfrastructure(address admin) internal {
        // Deploy ProxyAdmin with admin as the owner
        proxyAdmin = address(new ProxyAdmin(admin));
        console.log("ProxyAdmin:", proxyAdmin);
        console.log("  Owner:", admin);
        
        // Deploy EmptyContract as initial implementation for proxies
        emptyContract = address(new EmptyContract());
        console.log("EmptyContract:", emptyContract);
    }
    
    function deployMocks(address deployer) internal {
        // Deploy mock tokens
        // Requirements 3.1: Deploy MockERC20 as USDC with 6 decimals
        mockUSDC = address(new MockERC20("USD Coin", "USDC", 6));
        console.log("MockUSDC:", mockUSDC);
        
        // Requirements 3.2: Deploy MockERC20 as wstETH with 18 decimals
        mockWstETH = address(new MockERC20("Wrapped liquid staked Ether 2.0", "wstETH", 18));
        console.log("MockWstETH:", mockWstETH);
        
        // Deploy mock oracles (constructor takes decimals and price)
        mockUSDCOracle = address(new MockAggregatorV3Interface(
            8,              // decimals
            100_000_000     // $1.00
        ));
        console.log("MockUSDCOracle:", mockUSDCOracle);
        
        mockETHOracle = address(new MockAggregatorV3Interface(
            8,              // decimals
            3000_00000000   // $3000.00
        ));
        console.log("MockETHOracle:", mockETHOracle);
        
        // Requirements 3.3, 3.4: Mint test tokens to deployer
        // USDC: 10^15 tokens (with 6 decimals = 10^15 * 10^6 = 10^21)
        // wstETH: 10^15 tokens (with 18 decimals = 10^15 * 10^18 = 10^33)
        uint256 usdcMintAmount = 1e15 * 1e6;   // 10^15 USDC (10^21 base units)
        uint256 wstETHMintAmount = 1e15 * 1e18; // 10^15 wstETH (10^33 base units)
        
        MockERC20(mockUSDC).mint(deployer, usdcMintAmount);
        console.log("Minted USDC to deployer:", usdcMintAmount);
        
        MockERC20(mockWstETH).mint(deployer, wstETHMintAmount);
        console.log("Minted wstETH to deployer:", wstETHMintAmount);
    }

    function deployCoreProtocol(address admin) internal {
        // Deploy proxies with EmptyContract as initial implementation
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
        
        // Deploy ReservePool using deployCode to avoid OZ conflicts
        reservePool = deployCode(
            "ReservePool.sol:ReservePool",
            abi.encode(admin, poolManagerProxy)
        );
        console.log("ReservePool:", reservePool);
        
        revenuePool = address(new RevenuePool(admin, admin, admin));
        console.log("RevenuePool:", revenuePool);
        
        // Deploy PoolManager implementation using deployCode
        // PoolManager constructor: (address _fxUSD, address _fxBASE, address _counterparty, address _configuration, address _whitelist)
        // For Sepolia testing, we use pegKeeperProxy as counterparty and address(0) for configuration and whitelist
        address poolManagerImpl = deployCode(
            "PoolManager.sol:PoolManager",
            abi.encode(fxUSDProxy, fxUSDBasePoolProxy, pegKeeperProxy, address(0), address(0))
        );
        console.log("PoolManager Implementation:", poolManagerImpl);
        
        // Initialize PoolManager
        bytes memory poolManagerInitData = abi.encodeWithSignature(
            "initialize(address,uint256,uint256,uint256,address,address,address)",
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
        
        // Deploy FxUSDBasePool implementation
        bytes memory priceOracleData = abi.encode(mockUSDCOracle, mockUSDCOracle, address(0), uint256(0));
        
        address fxUSDBasePoolImpl = deployCode(
            "FxUSDBasePool.sol:FxUSDBasePool",
            abi.encode(poolManagerProxy, pegKeeperProxy, fxUSDProxy, mockUSDC, priceOracleData)
        );
        console.log("FxUSDBasePool Implementation:", fxUSDBasePoolImpl);
        
        bytes memory fxUSDBasePoolInitData = abi.encodeWithSignature(
            "initialize(address,string,string,uint256,uint256)",
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
        
        // Deploy PegKeeper implementation
        address pegKeeperImpl = deployCode(
            "PegKeeper.sol:PegKeeper",
            abi.encode(fxUSDBasePoolProxy)
        );
        console.log("PegKeeper Implementation:", pegKeeperImpl);
        
        bytes memory pegKeeperInitData = abi.encodeWithSignature(
            "initialize(address,address,address)",
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
        
        // Deploy FxUSD implementation
        address fxUSDImpl = deployCode(
            "FxUSDRegeneracy.sol:FxUSDRegeneracy",
            abi.encode(poolManagerProxy, mockUSDC, pegKeeperProxy)
        );
        console.log("FxUSD Implementation:", fxUSDImpl);
        
        bytes memory fxUSDInitData = abi.encodeWithSignature(
            "initialize(address,string,string)",
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
        // Deploy price oracle using MockPriceOracle for testing
        // Requirements 4.3: Deploy ETHPriceOracle with 5% max deviation
        // Using MockPriceOracle which implements IPriceOracle interface
        // ETH price: $3000 = 3000 * 1e18 (18 decimals for protocol)
        uint256 ethPriceWith18Decimals = 3000 * 1e18;
        wstETHPriceOracle = deployCode(
            "MockPriceOracle.sol:MockPriceOracle",
            abi.encode(
                ethPriceWith18Decimals, // anchorPrice
                ethPriceWith18Decimals, // minPrice (same for testing)
                ethPriceWith18Decimals  // maxPrice (same for testing)
            )
        );
        console.log("WstETH Price Oracle (MockPriceOracle):", wstETHPriceOracle);
        
        // Deploy pool implementation using deployCode
        address poolImpl = deployCode(
            "AaveFundingPool.sol:AaveFundingPool",
            abi.encode(poolManagerProxy, address(0))
        );
        console.log("AaveFundingPool Implementation:", poolImpl);
        
        // Prepare initialization data
        bytes memory poolInitData = abi.encodeWithSignature(
            "initialize(address,string,string,address,address)",
            admin,
            "f(x) wstETH Position",
            "xwstETH",
            mockWstETH,
            wstETHPriceOracle
        );
        
        // Deploy proxy
        wstETHPool = address(new TransparentUpgradeableProxy(
            poolImpl,
            proxyAdmin,
            poolInitData
        ));
        console.log("WstETH Pool:", wstETHPool);
        
        // Configure pool parameters using low-level calls (methods not in IPool interface)
        (bool success, ) = wstETHPool.call(
            abi.encodeWithSignature("updateDebtRatioRange(uint256,uint256)", DEBT_RATIO_LOWER, DEBT_RATIO_UPPER)
        );
        require(success, "Failed to update debt ratio range");
        console.log("Debt ratio range updated");
        
        (success, ) = wstETHPool.call(
            abi.encodeWithSignature("updateRebalanceRatios(uint256,uint256)", REBALANCE_DEBT_RATIO, REBALANCE_BONUS_RATIO)
        );
        require(success, "Failed to update rebalance ratios");
        console.log("Rebalance ratios updated");
        
        (success, ) = wstETHPool.call(
            abi.encodeWithSignature("updateLiquidateRatios(uint256,uint256)", LIQUIDATE_DEBT_RATIO, LIQUIDATE_BONUS_RATIO)
        );
        require(success, "Failed to update liquidate ratios");
        console.log("Liquidate ratios updated");
        
        (success, ) = wstETHPool.call(
            abi.encodeWithSignature("updateBorrowAndRedeemStatus(bool,bool)", true, true)
        );
        require(success, "Failed to update borrow and redeem status");
        console.log("Borrow and redeem enabled");
        
        // Register pool in PoolManager using low-level call (method not in IPoolManager interface)
        (success, ) = poolManagerProxy.call(
            abi.encodeWithSignature("registerPool(address,uint96,uint96)", wstETHPool, uint96(COLLATERAL_CAPACITY), uint96(DEBT_CAPACITY))
        );
        require(success, "Failed to register pool");
        console.log("Pool registered in PoolManager");
    }
    
    function printDeploymentSummary() internal view {
        console.log("ProxyAdmin:", proxyAdmin);
        console.log("EmptyContract:", emptyContract);
        console.log("");
        console.log("MockUSDC:", mockUSDC);
        console.log("MockWstETH:", mockWstETH);
        console.log("MockUSDCOracle:", mockUSDCOracle);
        console.log("MockETHOracle:", mockETHOracle);
        console.log("");
        console.log("PoolManager:", poolManagerProxy);
        console.log("FxUSD:", fxUSDProxy);
        console.log("FxUSDBasePool:", fxUSDBasePoolProxy);
        console.log("PegKeeper:", pegKeeperProxy);
        console.log("ReservePool:", reservePool);
        console.log("RevenuePool:", revenuePool);
        console.log("");
        console.log("WstETH Pool:", wstETHPool);
        console.log("WstETH Price Oracle:", wstETHPriceOracle);
    }
    
    function saveDeploymentAddresses() internal {
        string memory json = "deployment";
        
        vm.serializeAddress(json, "ProxyAdmin", proxyAdmin);
        vm.serializeAddress(json, "EmptyContract", emptyContract);
        vm.serializeAddress(json, "MockUSDC", mockUSDC);
        vm.serializeAddress(json, "MockWstETH", mockWstETH);
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
        
        vm.writeJson(finalJson, "./deployments/sepolia-latest.json");
        console.log("\nDeployment addresses saved to: ./deployments/sepolia-latest.json");
    }
}
