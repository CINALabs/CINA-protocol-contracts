// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "../../../contracts/mocks/MockERC20.sol";

/**
 * @title MockERC20PropertyTest
 * @notice Property-based tests for MockERC20 token minting functionality
 * @dev **Feature: sepolia-deployment, Property 1: Token Minting Consistency**
 * @dev **Validates: Requirements 3.3, 3.4**
 */
contract MockERC20PropertyTest is Test {
    MockERC20 internal usdc;
    MockERC20 internal wstETH;

    function setUp() public {
        // Deploy MockERC20 tokens with different decimals (matching Sepolia deployment)
        usdc = new MockERC20("USD Coin", "USDC", 6);
        wstETH = new MockERC20("Wrapped liquid staked Ether 2.0", "wstETH", 18);
    }

    /**
     * @notice Property 1: Token Minting Consistency
     * @dev For any address and any positive amount, when minting tokens to that address,
     *      the address's balance SHALL increase by exactly that amount.
     * @dev **Feature: sepolia-deployment, Property 1: Token Minting Consistency**
     * @dev **Validates: Requirements 3.3, 3.4**
     */
    function testFuzz_MintingConsistency_USDC(address recipient, uint256 amount) public {
        // Exclude zero address as ERC20 doesn't allow minting to zero address
        vm.assume(recipient != address(0));
        // Bound amount to avoid overflow (max supply reasonable for testing)
        amount = bound(amount, 0, type(uint128).max);

        uint256 balanceBefore = usdc.balanceOf(recipient);
        
        usdc.mint(recipient, amount);
        
        uint256 balanceAfter = usdc.balanceOf(recipient);
        
        // Property: balance should increase by exactly the minted amount
        assertEq(balanceAfter - balanceBefore, amount, "Balance should increase by minted amount");
        assertEq(balanceAfter, balanceBefore + amount, "Final balance should equal initial + minted");
    }

    /**
     * @notice Property 1: Token Minting Consistency for wstETH (18 decimals)
     * @dev For any address and any positive amount, when minting tokens to that address,
     *      the address's balance SHALL increase by exactly that amount.
     * @dev **Feature: sepolia-deployment, Property 1: Token Minting Consistency**
     * @dev **Validates: Requirements 3.3, 3.4**
     */
    function testFuzz_MintingConsistency_wstETH(address recipient, uint256 amount) public {
        // Exclude zero address as ERC20 doesn't allow minting to zero address
        vm.assume(recipient != address(0));
        // Bound amount to avoid overflow
        amount = bound(amount, 0, type(uint128).max);

        uint256 balanceBefore = wstETH.balanceOf(recipient);
        
        wstETH.mint(recipient, amount);
        
        uint256 balanceAfter = wstETH.balanceOf(recipient);
        
        // Property: balance should increase by exactly the minted amount
        assertEq(balanceAfter - balanceBefore, amount, "Balance should increase by minted amount");
        assertEq(balanceAfter, balanceBefore + amount, "Final balance should equal initial + minted");
    }

    /**
     * @notice Property 1: Multiple mints accumulate correctly
     * @dev For any sequence of mints to the same address, the final balance should equal
     *      the sum of all minted amounts.
     * @dev **Feature: sepolia-deployment, Property 1: Token Minting Consistency**
     * @dev **Validates: Requirements 3.3, 3.4**
     */
    function testFuzz_MultipleMints_Accumulate(
        address recipient,
        uint256 amount1,
        uint256 amount2,
        uint256 amount3
    ) public {
        // Exclude zero address
        vm.assume(recipient != address(0));
        // Bound amounts to avoid overflow when summed
        amount1 = bound(amount1, 0, type(uint64).max);
        amount2 = bound(amount2, 0, type(uint64).max);
        amount3 = bound(amount3, 0, type(uint64).max);

        uint256 balanceBefore = usdc.balanceOf(recipient);
        
        usdc.mint(recipient, amount1);
        usdc.mint(recipient, amount2);
        usdc.mint(recipient, amount3);
        
        uint256 balanceAfter = usdc.balanceOf(recipient);
        uint256 totalMinted = amount1 + amount2 + amount3;
        
        // Property: final balance should equal initial + sum of all mints
        assertEq(balanceAfter, balanceBefore + totalMinted, "Balance should equal sum of all mints");
    }

    /**
     * @notice Property 1: Minting to different addresses is independent
     * @dev Minting to one address should not affect another address's balance.
     * @dev **Feature: sepolia-deployment, Property 1: Token Minting Consistency**
     * @dev **Validates: Requirements 3.3, 3.4**
     */
    function testFuzz_MintingIndependence(
        address recipient1,
        address recipient2,
        uint256 amount1,
        uint256 amount2
    ) public {
        // Exclude zero address and ensure different recipients
        vm.assume(recipient1 != address(0));
        vm.assume(recipient2 != address(0));
        vm.assume(recipient1 != recipient2);
        // Bound amounts
        amount1 = bound(amount1, 0, type(uint128).max);
        amount2 = bound(amount2, 0, type(uint128).max);

        uint256 balance1Before = wstETH.balanceOf(recipient1);
        uint256 balance2Before = wstETH.balanceOf(recipient2);
        
        wstETH.mint(recipient1, amount1);
        
        // After minting to recipient1, recipient2's balance should be unchanged
        assertEq(wstETH.balanceOf(recipient2), balance2Before, "Recipient2 balance should be unchanged");
        
        wstETH.mint(recipient2, amount2);
        
        // Final balances should reflect only their respective mints
        assertEq(wstETH.balanceOf(recipient1), balance1Before + amount1, "Recipient1 balance incorrect");
        assertEq(wstETH.balanceOf(recipient2), balance2Before + amount2, "Recipient2 balance incorrect");
    }

    /**
     * @notice Property 1: Total supply increases by minted amount
     * @dev When minting tokens, the total supply should increase by exactly the minted amount.
     * @dev **Feature: sepolia-deployment, Property 1: Token Minting Consistency**
     * @dev **Validates: Requirements 3.3, 3.4**
     */
    function testFuzz_TotalSupplyConsistency(address recipient, uint256 amount) public {
        // Exclude zero address
        vm.assume(recipient != address(0));
        // Bound amount
        amount = bound(amount, 0, type(uint128).max);

        uint256 supplyBefore = usdc.totalSupply();
        
        usdc.mint(recipient, amount);
        
        uint256 supplyAfter = usdc.totalSupply();
        
        // Property: total supply should increase by exactly the minted amount
        assertEq(supplyAfter - supplyBefore, amount, "Total supply should increase by minted amount");
    }

    /**
     * @notice Verify token decimals are configured correctly
     * @dev USDC should have 6 decimals, wstETH should have 18 decimals
     */
    function test_TokenDecimals() public view {
        assertEq(usdc.decimals(), 6, "USDC should have 6 decimals");
        assertEq(wstETH.decimals(), 18, "wstETH should have 18 decimals");
    }

    /**
     * @notice Verify token names and symbols
     */
    function test_TokenMetadata() public view {
        assertEq(usdc.name(), "USD Coin", "USDC name incorrect");
        assertEq(usdc.symbol(), "USDC", "USDC symbol incorrect");
        assertEq(wstETH.name(), "Wrapped liquid staked Ether 2.0", "wstETH name incorrect");
        assertEq(wstETH.symbol(), "wstETH", "wstETH symbol incorrect");
    }
}
