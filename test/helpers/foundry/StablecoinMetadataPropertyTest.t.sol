// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "../../../contracts/mocks/MockERC20.sol";
import { MockAggregatorV3Interface } from "../../../contracts/mocks/MockAggregatorV3Interface.sol";

/**
 * @title StablecoinMetadataPropertyTest
 * @notice Property-based tests for stablecoin token metadata correctness
 * @dev **Feature: additional-test-tokens, Property 3: Token Metadata Correctness** (Stablecoin part)
 * @dev **Validates: Requirements 1.1, 1.2, 1.3**
 */
contract StablecoinMetadataPropertyTest is Test {
    // ============ Token Configuration Constants ============
    
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
    
    // Oracle configuration
    uint8 constant ORACLE_DECIMALS = 8;
    int256 constant STABLECOIN_PRICE = 100_000_000; // $1.00
    
    // ============ Token Instances ============
    
    MockERC20 internal usdt;
    MockERC20 internal dai;
    MockERC20 internal frax;
    
    MockAggregatorV3Interface internal usdtOracle;
    MockAggregatorV3Interface internal daiOracle;
    MockAggregatorV3Interface internal fraxOracle;

    function setUp() public {
        // Deploy stablecoins with expected configuration
        usdt = new MockERC20(USDT_NAME, USDT_SYMBOL, USDT_DECIMALS);
        dai = new MockERC20(DAI_NAME, DAI_SYMBOL, DAI_DECIMALS);
        frax = new MockERC20(FRAX_NAME, FRAX_SYMBOL, FRAX_DECIMALS);
        
        // Deploy oracles
        usdtOracle = new MockAggregatorV3Interface(ORACLE_DECIMALS, STABLECOIN_PRICE);
        daiOracle = new MockAggregatorV3Interface(ORACLE_DECIMALS, STABLECOIN_PRICE);
        fraxOracle = new MockAggregatorV3Interface(ORACLE_DECIMALS, STABLECOIN_PRICE);
    }

    // ============ Property 3: Token Metadata Correctness Tests ============

    /**
     * @notice Property 3: USDT Metadata Correctness
     * @dev WHEN deploying MockUSDT THEN the system SHALL create an ERC20 token 
     *      with name "Tether USD", symbol "USDT", and 6 decimals
     * @dev **Feature: additional-test-tokens, Property 3: Token Metadata Correctness**
     * @dev **Validates: Requirements 1.1**
     */
    function test_USDT_MetadataCorrectness() public view {
        assertEq(usdt.name(), USDT_NAME, "USDT name should be 'Tether USD'");
        assertEq(usdt.symbol(), USDT_SYMBOL, "USDT symbol should be 'USDT'");
        assertEq(usdt.decimals(), USDT_DECIMALS, "USDT should have 6 decimals");
    }

    /**
     * @notice Property 3: DAI Metadata Correctness
     * @dev WHEN deploying MockDAI THEN the system SHALL create an ERC20 token 
     *      with name "Dai Stablecoin", symbol "DAI", and 18 decimals
     * @dev **Feature: additional-test-tokens, Property 3: Token Metadata Correctness**
     * @dev **Validates: Requirements 1.2**
     */
    function test_DAI_MetadataCorrectness() public view {
        assertEq(dai.name(), DAI_NAME, "DAI name should be 'Dai Stablecoin'");
        assertEq(dai.symbol(), DAI_SYMBOL, "DAI symbol should be 'DAI'");
        assertEq(dai.decimals(), DAI_DECIMALS, "DAI should have 18 decimals");
    }

    /**
     * @notice Property 3: FRAX Metadata Correctness
     * @dev WHEN deploying MockFRAX THEN the system SHALL create an ERC20 token 
     *      with name "Frax", symbol "FRAX", and 18 decimals
     * @dev **Feature: additional-test-tokens, Property 3: Token Metadata Correctness**
     * @dev **Validates: Requirements 1.3**
     */
    function test_FRAX_MetadataCorrectness() public view {
        assertEq(frax.name(), FRAX_NAME, "FRAX name should be 'Frax'");
        assertEq(frax.symbol(), FRAX_SYMBOL, "FRAX symbol should be 'FRAX'");
        assertEq(frax.decimals(), FRAX_DECIMALS, "FRAX should have 18 decimals");
    }

    /**
     * @notice Property 3: Stablecoin metadata is immutable after deployment
     * @dev For any stablecoin, the name(), symbol(), and decimals() functions 
     *      should return consistent values across multiple calls
     * @dev **Feature: additional-test-tokens, Property 3: Token Metadata Correctness**
     * @dev **Validates: Requirements 1.1, 1.2, 1.3**
     */
    function testFuzz_StablecoinMetadataImmutability(uint256 tokenIndex) public view {
        tokenIndex = bound(tokenIndex, 0, 2);
        
        MockERC20 token;
        string memory expectedName;
        string memory expectedSymbol;
        uint8 expectedDecimals;
        
        if (tokenIndex == 0) {
            token = usdt;
            expectedName = USDT_NAME;
            expectedSymbol = USDT_SYMBOL;
            expectedDecimals = USDT_DECIMALS;
        } else if (tokenIndex == 1) {
            token = dai;
            expectedName = DAI_NAME;
            expectedSymbol = DAI_SYMBOL;
            expectedDecimals = DAI_DECIMALS;
        } else {
            token = frax;
            expectedName = FRAX_NAME;
            expectedSymbol = FRAX_SYMBOL;
            expectedDecimals = FRAX_DECIMALS;
        }
        
        // Multiple calls should return consistent values
        assertEq(token.name(), expectedName, "Name should be consistent");
        assertEq(token.name(), expectedName, "Name should be consistent on second call");
        assertEq(token.symbol(), expectedSymbol, "Symbol should be consistent");
        assertEq(token.symbol(), expectedSymbol, "Symbol should be consistent on second call");
        assertEq(token.decimals(), expectedDecimals, "Decimals should be consistent");
        assertEq(token.decimals(), expectedDecimals, "Decimals should be consistent on second call");
    }

    /**
     * @notice Property 3: Stablecoin oracle price correctness
     * @dev WHEN deploying stablecoin oracles THEN the system SHALL configure 
     *      each oracle to return $1.00 price (100_000_000 with 8 decimals)
     * @dev **Feature: additional-test-tokens, Property 3: Token Metadata Correctness**
     * @dev **Validates: Requirements 5.1**
     */
    function test_StablecoinOraclePriceCorrectness() public view {
        // Check USDT oracle
        (, int256 usdtPrice,,,) = usdtOracle.latestRoundData();
        assertEq(usdtPrice, STABLECOIN_PRICE, "USDT oracle should return $1.00");
        assertEq(usdtOracle.decimals(), ORACLE_DECIMALS, "USDT oracle should have 8 decimals");
        
        // Check DAI oracle
        (, int256 daiPrice,,,) = daiOracle.latestRoundData();
        assertEq(daiPrice, STABLECOIN_PRICE, "DAI oracle should return $1.00");
        assertEq(daiOracle.decimals(), ORACLE_DECIMALS, "DAI oracle should have 8 decimals");
        
        // Check FRAX oracle
        (, int256 fraxPrice,,,) = fraxOracle.latestRoundData();
        assertEq(fraxPrice, STABLECOIN_PRICE, "FRAX oracle should return $1.00");
        assertEq(fraxOracle.decimals(), ORACLE_DECIMALS, "FRAX oracle should have 8 decimals");
    }

    /**
     * @notice Property 3: Fuzz test for stablecoin oracle consistency
     * @dev For any stablecoin oracle, calling latestRoundData() should return 
     *      the configured initial price, and decimals() should return 8
     * @dev **Feature: additional-test-tokens, Property 3: Token Metadata Correctness**
     * @dev **Validates: Requirements 5.1**
     */
    function testFuzz_StablecoinOracleConsistency(uint256 oracleIndex) public view {
        oracleIndex = bound(oracleIndex, 0, 2);
        
        MockAggregatorV3Interface oracle;
        if (oracleIndex == 0) {
            oracle = usdtOracle;
        } else if (oracleIndex == 1) {
            oracle = daiOracle;
        } else {
            oracle = fraxOracle;
        }
        
        // Oracle should return consistent price
        (, int256 price,,,) = oracle.latestRoundData();
        assertEq(price, STABLECOIN_PRICE, "Oracle should return $1.00");
        assertEq(oracle.decimals(), ORACLE_DECIMALS, "Oracle should have 8 decimals");
        
        // latestAnswer should match
        assertEq(oracle.latestAnswer(), uint256(STABLECOIN_PRICE), "latestAnswer should match");
    }
}
