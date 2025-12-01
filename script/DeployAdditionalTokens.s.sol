// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Mock contracts for testing
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockAggregatorV3Interface.sol";

/**
 * @title DeployAdditionalTokens
 * @notice Deploys additional test tokens for Sepolia testnet
 * @dev Extends the existing deployment with more token types:
 *      - Stablecoins: USDT, DAI, FRAX
 *      - LST (Liquid Staking Tokens): stETH, rETH, cbETH
 *      - LRT (Liquid Restaking Tokens): ezETH, weETH, rsETH
 *      - BTC derivatives: WBTC, tBTC
 */
contract DeployAdditionalTokens is Script {
    // ============ Token Info Structure ============
    
    struct TokenInfo {
        address token;
        address oracle;
        string name;
        string symbol;
        uint8 decimals;
        uint256 initialPrice;
    }
    
    // ============ Token Storage ============
    
    TokenInfo[] public stablecoins;
    TokenInfo[] public lstTokens;
    TokenInfo[] public lrtTokens;
    TokenInfo[] public btcTokens;
    
    // ============ Price Constants (8 decimals) ============
    
    uint256 constant STABLECOIN_PRICE = 100_000_000;        // $1.00
    uint256 constant ETH_PRICE = 3000_00000000;             // $3000.00
    uint256 constant BTC_PRICE = 60000_00000000;            // $60000.00
    uint8 constant ORACLE_DECIMALS = 8;
    
    // ============ Mint Amount Constants ============
    
    uint256 constant STABLECOIN_MINT_AMOUNT = 1e15;         // 10^15 tokens
    uint256 constant LST_MINT_AMOUNT = 1e15;                // 10^15 tokens
    uint256 constant LRT_MINT_AMOUNT = 1e15;                // 10^15 tokens
    uint256 constant BTC_MINT_AMOUNT = 1e12;                // 10^12 tokens
    
    // ============ Stablecoin Configuration ============
    
    // USDT - Tether USD
    string constant USDT_NAME = "Tether USD";
    string constant USDT_SYMBOL = "USDT";
    uint8 constant USDT_DECIMALS = 6;
    
    // DAI - Dai Stablecoin
    string constant DAI_NAME = "Dai Stablecoin";
    string constant DAI_SYMBOL = "DAI";
    uint8 constant DAI_DECIMALS = 18;
    
    // FRAX - Frax
    string constant FRAX_NAME = "Frax";
    string constant FRAX_SYMBOL = "FRAX";
    uint8 constant FRAX_DECIMALS = 18;

    
    // ============ LST Configuration ============
    
    // stETH - Lido Staked Ether
    string constant STETH_NAME = "Lido Staked Ether";
    string constant STETH_SYMBOL = "stETH";
    uint8 constant STETH_DECIMALS = 18;
    
    // rETH - Rocket Pool ETH
    string constant RETH_NAME = "Rocket Pool ETH";
    string constant RETH_SYMBOL = "rETH";
    uint8 constant RETH_DECIMALS = 18;
    
    // cbETH - Coinbase Wrapped Staked ETH
    string constant CBETH_NAME = "Coinbase Wrapped Staked ETH";
    string constant CBETH_SYMBOL = "cbETH";
    uint8 constant CBETH_DECIMALS = 18;
    
    // ============ LRT Configuration ============
    
    // ezETH - Renzo Restaked ETH
    string constant EZETH_NAME = "Renzo Restaked ETH";
    string constant EZETH_SYMBOL = "ezETH";
    uint8 constant EZETH_DECIMALS = 18;
    
    // weETH - Wrapped eETH
    string constant WEETH_NAME = "Wrapped eETH";
    string constant WEETH_SYMBOL = "weETH";
    uint8 constant WEETH_DECIMALS = 18;
    
    // rsETH - KelpDAO Restaked ETH
    string constant RSETH_NAME = "KelpDAO Restaked ETH";
    string constant RSETH_SYMBOL = "rsETH";
    uint8 constant RSETH_DECIMALS = 18;
    
    // ============ BTC Configuration ============
    
    // WBTC - Wrapped BTC
    string constant WBTC_NAME = "Wrapped BTC";
    string constant WBTC_SYMBOL = "WBTC";
    uint8 constant WBTC_DECIMALS = 8;
    
    // tBTC - tBTC v2
    string constant TBTC_NAME = "tBTC v2";
    string constant TBTC_SYMBOL = "tBTC";
    uint8 constant TBTC_DECIMALS = 18;
    
    // ============ Main Entry Point ============
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy stablecoins
        console.log("\n=== Step 1: Deploying Stablecoins ===");
        deployStablecoins(deployer);
        
        // Step 2: Deploy LST tokens
        console.log("\n=== Step 2: Deploying LST Tokens ===");
        deployLSTTokens(deployer);
        
        // Step 3: Deploy LRT tokens
        console.log("\n=== Step 3: Deploying LRT Tokens ===");
        deployLRTTokens(deployer);
        
        // Step 4: Deploy BTC tokens
        console.log("\n=== Step 4: Deploying BTC Tokens ===");
        deployBTCTokens(deployer);
        
        // Step 5: Print deployment summary
        console.log("\n=== Deployment Summary ===");
        printDeploymentSummary();
        
        vm.stopBroadcast();
        
        // Save deployment addresses
        saveTokenRegistry();
    }

    
    // ============ Deployment Functions ============
    
    function deployStablecoins(address deployer) internal {
        // Deploy USDT
        address usdtToken = address(new MockERC20(USDT_NAME, USDT_SYMBOL, USDT_DECIMALS));
        address usdtOracle = address(new MockAggregatorV3Interface(ORACLE_DECIMALS, int256(STABLECOIN_PRICE)));
        MockERC20(usdtToken).mint(deployer, STABLECOIN_MINT_AMOUNT * (10 ** USDT_DECIMALS));
        stablecoins.push(TokenInfo({
            token: usdtToken,
            oracle: usdtOracle,
            name: USDT_NAME,
            symbol: USDT_SYMBOL,
            decimals: USDT_DECIMALS,
            initialPrice: STABLECOIN_PRICE
        }));
        console.log("MockUSDT:", usdtToken);
        console.log("  Oracle:", usdtOracle);
        
        // Deploy DAI
        address daiToken = address(new MockERC20(DAI_NAME, DAI_SYMBOL, DAI_DECIMALS));
        address daiOracle = address(new MockAggregatorV3Interface(ORACLE_DECIMALS, int256(STABLECOIN_PRICE)));
        MockERC20(daiToken).mint(deployer, STABLECOIN_MINT_AMOUNT * (10 ** DAI_DECIMALS));
        stablecoins.push(TokenInfo({
            token: daiToken,
            oracle: daiOracle,
            name: DAI_NAME,
            symbol: DAI_SYMBOL,
            decimals: DAI_DECIMALS,
            initialPrice: STABLECOIN_PRICE
        }));
        console.log("MockDAI:", daiToken);
        console.log("  Oracle:", daiOracle);
        
        // Deploy FRAX
        address fraxToken = address(new MockERC20(FRAX_NAME, FRAX_SYMBOL, FRAX_DECIMALS));
        address fraxOracle = address(new MockAggregatorV3Interface(ORACLE_DECIMALS, int256(STABLECOIN_PRICE)));
        MockERC20(fraxToken).mint(deployer, STABLECOIN_MINT_AMOUNT * (10 ** FRAX_DECIMALS));
        stablecoins.push(TokenInfo({
            token: fraxToken,
            oracle: fraxOracle,
            name: FRAX_NAME,
            symbol: FRAX_SYMBOL,
            decimals: FRAX_DECIMALS,
            initialPrice: STABLECOIN_PRICE
        }));
        console.log("MockFRAX:", fraxToken);
        console.log("  Oracle:", fraxOracle);
    }
    
    function deployLSTTokens(address deployer) internal {
        // Deploy stETH
        address stethToken = address(new MockERC20(STETH_NAME, STETH_SYMBOL, STETH_DECIMALS));
        address stethOracle = address(new MockAggregatorV3Interface(ORACLE_DECIMALS, int256(ETH_PRICE)));
        MockERC20(stethToken).mint(deployer, LST_MINT_AMOUNT * (10 ** STETH_DECIMALS));
        lstTokens.push(TokenInfo({
            token: stethToken,
            oracle: stethOracle,
            name: STETH_NAME,
            symbol: STETH_SYMBOL,
            decimals: STETH_DECIMALS,
            initialPrice: ETH_PRICE
        }));
        console.log("MockStETH:", stethToken);
        console.log("  Oracle:", stethOracle);
        
        // Deploy rETH
        address rethToken = address(new MockERC20(RETH_NAME, RETH_SYMBOL, RETH_DECIMALS));
        address rethOracle = address(new MockAggregatorV3Interface(ORACLE_DECIMALS, int256(ETH_PRICE)));
        MockERC20(rethToken).mint(deployer, LST_MINT_AMOUNT * (10 ** RETH_DECIMALS));
        lstTokens.push(TokenInfo({
            token: rethToken,
            oracle: rethOracle,
            name: RETH_NAME,
            symbol: RETH_SYMBOL,
            decimals: RETH_DECIMALS,
            initialPrice: ETH_PRICE
        }));
        console.log("MockRETH:", rethToken);
        console.log("  Oracle:", rethOracle);
        
        // Deploy cbETH
        address cbethToken = address(new MockERC20(CBETH_NAME, CBETH_SYMBOL, CBETH_DECIMALS));
        address cbethOracle = address(new MockAggregatorV3Interface(ORACLE_DECIMALS, int256(ETH_PRICE)));
        MockERC20(cbethToken).mint(deployer, LST_MINT_AMOUNT * (10 ** CBETH_DECIMALS));
        lstTokens.push(TokenInfo({
            token: cbethToken,
            oracle: cbethOracle,
            name: CBETH_NAME,
            symbol: CBETH_SYMBOL,
            decimals: CBETH_DECIMALS,
            initialPrice: ETH_PRICE
        }));
        console.log("MockCbETH:", cbethToken);
        console.log("  Oracle:", cbethOracle);
    }

    
    function deployLRTTokens(address deployer) internal {
        // Deploy ezETH
        address ezethToken = address(new MockERC20(EZETH_NAME, EZETH_SYMBOL, EZETH_DECIMALS));
        address ezethOracle = address(new MockAggregatorV3Interface(ORACLE_DECIMALS, int256(ETH_PRICE)));
        MockERC20(ezethToken).mint(deployer, LRT_MINT_AMOUNT * (10 ** EZETH_DECIMALS));
        lrtTokens.push(TokenInfo({
            token: ezethToken,
            oracle: ezethOracle,
            name: EZETH_NAME,
            symbol: EZETH_SYMBOL,
            decimals: EZETH_DECIMALS,
            initialPrice: ETH_PRICE
        }));
        console.log("MockEzETH:", ezethToken);
        console.log("  Oracle:", ezethOracle);
        
        // Deploy weETH
        address weethToken = address(new MockERC20(WEETH_NAME, WEETH_SYMBOL, WEETH_DECIMALS));
        address weethOracle = address(new MockAggregatorV3Interface(ORACLE_DECIMALS, int256(ETH_PRICE)));
        MockERC20(weethToken).mint(deployer, LRT_MINT_AMOUNT * (10 ** WEETH_DECIMALS));
        lrtTokens.push(TokenInfo({
            token: weethToken,
            oracle: weethOracle,
            name: WEETH_NAME,
            symbol: WEETH_SYMBOL,
            decimals: WEETH_DECIMALS,
            initialPrice: ETH_PRICE
        }));
        console.log("MockWeETH:", weethToken);
        console.log("  Oracle:", weethOracle);
        
        // Deploy rsETH
        address rsethToken = address(new MockERC20(RSETH_NAME, RSETH_SYMBOL, RSETH_DECIMALS));
        address rsethOracle = address(new MockAggregatorV3Interface(ORACLE_DECIMALS, int256(ETH_PRICE)));
        MockERC20(rsethToken).mint(deployer, LRT_MINT_AMOUNT * (10 ** RSETH_DECIMALS));
        lrtTokens.push(TokenInfo({
            token: rsethToken,
            oracle: rsethOracle,
            name: RSETH_NAME,
            symbol: RSETH_SYMBOL,
            decimals: RSETH_DECIMALS,
            initialPrice: ETH_PRICE
        }));
        console.log("MockRsETH:", rsethToken);
        console.log("  Oracle:", rsethOracle);
    }
    
    function deployBTCTokens(address deployer) internal {
        // Deploy WBTC
        address wbtcToken = address(new MockERC20(WBTC_NAME, WBTC_SYMBOL, WBTC_DECIMALS));
        address wbtcOracle = address(new MockAggregatorV3Interface(ORACLE_DECIMALS, int256(BTC_PRICE)));
        MockERC20(wbtcToken).mint(deployer, BTC_MINT_AMOUNT * (10 ** WBTC_DECIMALS));
        btcTokens.push(TokenInfo({
            token: wbtcToken,
            oracle: wbtcOracle,
            name: WBTC_NAME,
            symbol: WBTC_SYMBOL,
            decimals: WBTC_DECIMALS,
            initialPrice: BTC_PRICE
        }));
        console.log("MockWBTC:", wbtcToken);
        console.log("  Oracle:", wbtcOracle);
        
        // Deploy tBTC
        address tbtcToken = address(new MockERC20(TBTC_NAME, TBTC_SYMBOL, TBTC_DECIMALS));
        address tbtcOracle = address(new MockAggregatorV3Interface(ORACLE_DECIMALS, int256(BTC_PRICE)));
        MockERC20(tbtcToken).mint(deployer, BTC_MINT_AMOUNT * (10 ** TBTC_DECIMALS));
        btcTokens.push(TokenInfo({
            token: tbtcToken,
            oracle: tbtcOracle,
            name: TBTC_NAME,
            symbol: TBTC_SYMBOL,
            decimals: TBTC_DECIMALS,
            initialPrice: BTC_PRICE
        }));
        console.log("MockTBTC:", tbtcToken);
        console.log("  Oracle:", tbtcOracle);
    }

    
    // ============ Output Functions ============
    
    function printDeploymentSummary() internal view {
        console.log("\n--- Stablecoins ---");
        for (uint256 i = 0; i < stablecoins.length; i++) {
            console.log(stablecoins[i].symbol, ":", stablecoins[i].token);
            console.log("  Oracle:", stablecoins[i].oracle);
        }
        
        console.log("\n--- LST Tokens ---");
        for (uint256 i = 0; i < lstTokens.length; i++) {
            console.log(lstTokens[i].symbol, ":", lstTokens[i].token);
            console.log("  Oracle:", lstTokens[i].oracle);
        }
        
        console.log("\n--- LRT Tokens ---");
        for (uint256 i = 0; i < lrtTokens.length; i++) {
            console.log(lrtTokens[i].symbol, ":", lrtTokens[i].token);
            console.log("  Oracle:", lrtTokens[i].oracle);
        }
        
        console.log("\n--- BTC Tokens ---");
        for (uint256 i = 0; i < btcTokens.length; i++) {
            console.log(btcTokens[i].symbol, ":", btcTokens[i].token);
            console.log("  Oracle:", btcTokens[i].oracle);
        }
    }
    
    function saveTokenRegistry() internal {
        string memory json = "tokens";
        
        // Serialize stablecoins
        string memory stablecoinsJson = "stablecoins";
        for (uint256 i = 0; i < stablecoins.length; i++) {
            string memory tokenKey = stablecoins[i].symbol;
            string memory tokenJson = tokenKey;
            vm.serializeAddress(tokenJson, "address", stablecoins[i].token);
            vm.serializeAddress(tokenJson, "oracle", stablecoins[i].oracle);
            vm.serializeString(tokenJson, "name", stablecoins[i].name);
            string memory tokenFinal = vm.serializeUint(tokenJson, "decimals", stablecoins[i].decimals);
            vm.serializeString(stablecoinsJson, tokenKey, tokenFinal);
        }
        string memory stablecoinsFinal = vm.serializeString(stablecoinsJson, "_type", "stablecoins");
        
        // Serialize LST tokens
        string memory lstJson = "lst";
        for (uint256 i = 0; i < lstTokens.length; i++) {
            string memory tokenKey = lstTokens[i].symbol;
            string memory tokenJson = tokenKey;
            vm.serializeAddress(tokenJson, "address", lstTokens[i].token);
            vm.serializeAddress(tokenJson, "oracle", lstTokens[i].oracle);
            vm.serializeString(tokenJson, "name", lstTokens[i].name);
            string memory tokenFinal = vm.serializeUint(tokenJson, "decimals", lstTokens[i].decimals);
            vm.serializeString(lstJson, tokenKey, tokenFinal);
        }
        string memory lstFinal = vm.serializeString(lstJson, "_type", "lst");
        
        // Serialize LRT tokens
        string memory lrtJson = "lrt";
        for (uint256 i = 0; i < lrtTokens.length; i++) {
            string memory tokenKey = lrtTokens[i].symbol;
            string memory tokenJson = tokenKey;
            vm.serializeAddress(tokenJson, "address", lrtTokens[i].token);
            vm.serializeAddress(tokenJson, "oracle", lrtTokens[i].oracle);
            vm.serializeString(tokenJson, "name", lrtTokens[i].name);
            string memory tokenFinal = vm.serializeUint(tokenJson, "decimals", lrtTokens[i].decimals);
            vm.serializeString(lrtJson, tokenKey, tokenFinal);
        }
        string memory lrtFinal = vm.serializeString(lrtJson, "_type", "lrt");
        
        // Serialize BTC tokens
        string memory btcJson = "btc";
        for (uint256 i = 0; i < btcTokens.length; i++) {
            string memory tokenKey = btcTokens[i].symbol;
            string memory tokenJson = tokenKey;
            vm.serializeAddress(tokenJson, "address", btcTokens[i].token);
            vm.serializeAddress(tokenJson, "oracle", btcTokens[i].oracle);
            vm.serializeString(tokenJson, "name", btcTokens[i].name);
            string memory tokenFinal = vm.serializeUint(tokenJson, "decimals", btcTokens[i].decimals);
            vm.serializeString(btcJson, tokenKey, tokenFinal);
        }
        string memory btcFinal = vm.serializeString(btcJson, "_type", "btc");
        
        // Combine all categories
        vm.serializeString(json, "stablecoins", stablecoinsFinal);
        vm.serializeString(json, "lst", lstFinal);
        vm.serializeString(json, "lrt", lrtFinal);
        string memory finalJson = vm.serializeString(json, "btc", btcFinal);
        
        vm.writeJson(finalJson, "./deployments/sepolia-tokens.json");
        console.log("\nToken registry saved to: ./deployments/sepolia-tokens.json");
    }
    
    // ============ Getter Functions ============
    
    function getStablecoinsCount() external view returns (uint256) {
        return stablecoins.length;
    }
    
    function getLSTTokensCount() external view returns (uint256) {
        return lstTokens.length;
    }
    
    function getLRTTokensCount() external view returns (uint256) {
        return lrtTokens.length;
    }
    
    function getBTCTokensCount() external view returns (uint256) {
        return btcTokens.length;
    }
}
