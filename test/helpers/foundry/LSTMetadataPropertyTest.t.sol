// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "../../../contracts/mocks/MockERC20.sol";
import { MockAggregatorV3Interface } from "../../../contracts/mocks/MockAggregatorV3Interface.sol";

/**
 * @title LSTMetadataPropertyTest
 * @notice Property-based tests for LST (Liquid Staking Token) metadata correctness
 * @dev **Feature: additional-test-tokens, Property 3: Token Metadata Correctness** (LST part)
 * @dev **Validates: Requirements 2.1, 2.2, 2.3**
 */
contract LSTMetadataPropertyTest is Test {
    // ============ Token Configuration Constants ============
    
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
    
    // Oracle configuration
    uint8 constant ORACLE_DECIMALS = 8;
    int256 constant ETH_PRICE = 3000_00000000; // $3000.00
    
    // ============ Token Instances ============
    
    MockERC20 internal steth;
    MockERC20 internal reth;
    MockERC20 internal cbeth;
    
    MockAggregatorV3Interface internal stethOracle;
    MockAggregatorV3Interface internal rethOracle;
    MockAggregatorV3Interface internal cbethOracle;

    function setUp() public {
        // Deploy LST tokens with expected configuration
        steth = new MockERC20(STETH_NAME, STETH_SYMBOL, STETH_DECIMALS);
        reth = new MockERC20(RETH_NAME, RETH_SYMBOL, RETH_DECIMALS);
        cbeth = new MockERC20(CBETH_NAME, CBETH_SYMBOL, CBETH_DECIMALS);
        
        // Deploy oracles
        stethOracle = new MockAggregatorV3Interface(ORACLE_DECIMALS, ETH_PRICE);
        rethOracle = new MockAggregatorV3Interface(ORACLE_DECIMALS, ETH_PRICE);
        cbethOracle = new MockAggregatorV3Interface(ORACLE_DECIMALS, ETH_PRICE);
    }


    // ============ Property 3: Token Metadata Correctness Tests ============

    /**
     * @notice Property 3: stETH Metadata Correctness
     * @dev WHEN deploying MockStETH THEN the system SHALL create an ERC20 token 
     *      with name "Lido Staked Ether", symbol "stETH", and 18 decimals
     * @dev **Feature: additional-test-tokens, Property 3: Token Metadata Correctness**
     * @dev **Validates: Requirements 2.1**
     */
    function test_stETH_MetadataCorrectness() public view {
        assertEq(steth.name(), STETH_NAME, "stETH name should be 'Lido Staked Ether'");
        assertEq(steth.symbol(), STETH_SYMBOL, "stETH symbol should be 'stETH'");
        assertEq(steth.decimals(), STETH_DECIMALS, "stETH should have 18 decimals");
    }

    /**
     * @notice Property 3: rETH Metadata Correctness
     * @dev WHEN deploying MockRETH THEN the system SHALL create an ERC20 token 
     *      with name "Rocket Pool ETH", symbol "rETH", and 18 decimals
     * @dev **Feature: additional-test-tokens, Property 3: Token Metadata Correctness**
     * @dev **Validates: Requirements 2.2**
     */
    function test_rETH_MetadataCorrectness() public view {
        assertEq(reth.name(), RETH_NAME, "rETH name should be 'Rocket Pool ETH'");
        assertEq(reth.symbol(), RETH_SYMBOL, "rETH symbol should be 'rETH'");
        assertEq(reth.decimals(), RETH_DECIMALS, "rETH should have 18 decimals");
    }

    /**
     * @notice Property 3: cbETH Metadata Correctness
     * @dev WHEN deploying MockCbETH THEN the system SHALL create an ERC20 token 
     *      with name "Coinbase Wrapped Staked ETH", symbol "cbETH", and 18 decimals
     * @dev **Feature: additional-test-tokens, Property 3: Token Metadata Correctness**
     * @dev **Validates: Requirements 2.3**
     */
    function test_cbETH_MetadataCorrectness() public view {
        assertEq(cbeth.name(), CBETH_NAME, "cbETH name should be 'Coinbase Wrapped Staked ETH'");
        assertEq(cbeth.symbol(), CBETH_SYMBOL, "cbETH symbol should be 'cbETH'");
        assertEq(cbeth.decimals(), CBETH_DECIMALS, "cbETH should have 18 decimals");
    }

    /**
     * @notice Property 3: LST metadata is immutable after deployment
     * @dev For any LST token, the name(), symbol(), and decimals() functions 
     *      should return consistent values across multiple calls
     * @dev **Feature: additional-test-tokens, Property 3: Token Metadata Correctness**
     * @dev **Validates: Requirements 2.1, 2.2, 2.3**
     */
    function testFuzz_LSTMetadataImmutability(uint256 tokenIndex) public view {
        tokenIndex = bound(tokenIndex, 0, 2);
        
        MockERC20 token;
        string memory expectedName;
        string memory expectedSymbol;
        uint8 expectedDecimals;
        
        if (tokenIndex == 0) {
            token = steth;
            expectedName = STETH_NAME;
            expectedSymbol = STETH_SYMBOL;
            expectedDecimals = STETH_DECIMALS;
        } else if (tokenIndex == 1) {
            token = reth;
            expectedName = RETH_NAME;
            expectedSymbol = RETH_SYMBOL;
            expectedDecimals = RETH_DECIMALS;
        } else {
            token = cbeth;
            expectedName = CBETH_NAME;
            expectedSymbol = CBETH_SYMBOL;
            expectedDecimals = CBETH_DECIMALS;
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
     * @notice Property 3: LST oracle price correctness
     * @dev WHEN deploying ETH-based LST oracles THEN the system SHALL configure 
     *      each oracle to return $3000.00 price (3000_00000000 with 8 decimals)
     * @dev **Feature: additional-test-tokens, Property 3: Token Metadata Correctness**
     * @dev **Validates: Requirements 5.2**
     */
    function test_LSTOraclePriceCorrectness() public view {
        // Check stETH oracle
        (, int256 stethPrice,,,) = stethOracle.latestRoundData();
        assertEq(stethPrice, ETH_PRICE, "stETH oracle should return $3000.00");
        assertEq(stethOracle.decimals(), ORACLE_DECIMALS, "stETH oracle should have 8 decimals");
        
        // Check rETH oracle
        (, int256 rethPrice,,,) = rethOracle.latestRoundData();
        assertEq(rethPrice, ETH_PRICE, "rETH oracle should return $3000.00");
        assertEq(rethOracle.decimals(), ORACLE_DECIMALS, "rETH oracle should have 8 decimals");
        
        // Check cbETH oracle
        (, int256 cbethPrice,,,) = cbethOracle.latestRoundData();
        assertEq(cbethPrice, ETH_PRICE, "cbETH oracle should return $3000.00");
        assertEq(cbethOracle.decimals(), ORACLE_DECIMALS, "cbETH oracle should have 8 decimals");
    }

    /**
     * @notice Property 3: Fuzz test for LST oracle consistency
     * @dev For any LST oracle, calling latestRoundData() should return 
     *      the configured initial price, and decimals() should return 8
     * @dev **Feature: additional-test-tokens, Property 3: Token Metadata Correctness**
     * @dev **Validates: Requirements 5.2**
     */
    function testFuzz_LSTOracleConsistency(uint256 oracleIndex) public view {
        oracleIndex = bound(oracleIndex, 0, 2);
        
        MockAggregatorV3Interface oracle;
        if (oracleIndex == 0) {
            oracle = stethOracle;
        } else if (oracleIndex == 1) {
            oracle = rethOracle;
        } else {
            oracle = cbethOracle;
        }
        
        // Oracle should return consistent price
        (, int256 price,,,) = oracle.latestRoundData();
        assertEq(price, ETH_PRICE, "Oracle should return $3000.00");
        assertEq(oracle.decimals(), ORACLE_DECIMALS, "Oracle should have 8 decimals");
        
        // latestAnswer should match
        assertEq(oracle.latestAnswer(), uint256(ETH_PRICE), "latestAnswer should match");
    }
}
