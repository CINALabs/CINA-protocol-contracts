// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../contracts/helpers/ProxyAdmin.sol";
import "../contracts/helpers/TransparentUpgradeableProxyV4.sol";
import "../contracts/core/PoolConfiguration.sol";
import "../contracts/core/PoolManager.sol";
import "../contracts/mocks/MockAaveV3Pool.sol";

contract FixConfiguration is Script {
    function run() external {
        string memory json = vm.readFile("./deployments/sepolia-latest.json");
        address poolManagerProxy = vm.parseJsonAddress(json, ".PoolManager");
        address fxUSDProxy = vm.parseJsonAddress(json, ".FxUSD");
        address fxUSDBasePoolProxy = vm.parseJsonAddress(json, ".FxUSDBasePool");
        address pegKeeperProxy = vm.parseJsonAddress(json, ".PegKeeper");
        address mockUSDC = vm.parseJsonAddress(json, ".MockUSDC");
        address proxyAdmin = vm.parseJsonAddress(json, ".ProxyAdmin");
        
        // Hardcoded from previous deployment logs
        address fxUSDPriceOracle = 0xec6fc4dF32D0d39fcF9a167b484d71EB2F6cF8B7;

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);

        address poolConfiguration;
        {
            // 1. Deploy MockAaveV3Pool
            address mockAaveV3Pool = address(new MockAaveV3Pool(0));
            console.log("MockAaveV3Pool:", mockAaveV3Pool);

            // 2. Deploy PoolConfiguration Implementation
            // constructor(fxBASE, aavePool, stableToken, poolManager, shortPoolManager)
            address poolConfigImpl = address(new PoolConfiguration(
                fxUSDBasePoolProxy,
                mockAaveV3Pool,
                mockUSDC,
                poolManagerProxy,
                address(0)
            ));
            console.log("PoolConfiguration Implementation:", poolConfigImpl);

            // 3. Deploy PoolConfiguration Proxy
            bytes memory initData = abi.encodeWithSignature("initialize(address,address)", deployer, fxUSDPriceOracle);
            poolConfiguration = address(new TransparentUpgradeableProxyV4(
                poolConfigImpl,
                proxyAdmin,
                initData
            ));
            console.log("PoolConfiguration Proxy:", poolConfiguration);
        }

        // 4. Deploy New PoolManager Implementation
        // constructor(fxUSD, fxBASE, counterparty, configuration, whitelist)
        address newPoolManagerImpl = address(new PoolManager(
            fxUSDProxy,
            fxUSDBasePoolProxy,
            pegKeeperProxy,
            poolConfiguration, // The fix!
            address(0)
        ));
        console.log("New PoolManager Implementation:", newPoolManagerImpl);

        // 5. Upgrade PoolManager
        // Use a harmless view function call to bypass the empty data restriction/issue
        bytes memory upgradeData = abi.encodeWithSignature("getTokenScalingFactor(address)", address(0));
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(poolManagerProxy),
            newPoolManagerImpl,
            upgradeData
        );
        console.log("PoolManager Upgraded");

        vm.stopBroadcast();
        
        // Save PoolConfiguration address for future use (optional)
        // vm.serializeAddress... 
    }
}
