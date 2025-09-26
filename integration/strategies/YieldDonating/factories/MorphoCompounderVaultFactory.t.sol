// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MorphoCompounderStrategy } from "src/strategies/yieldDonating/MorphoCompounderStrategy.sol";
import { MorphoCompounderStrategyFactory } from "src/factories/yieldDonating/MorphoCompounderStrategyFactory.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { YieldDonatingTokenizedStrategy } from "src/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { CREATE3 } from "solady/utils/CREATE3.sol";

/// @title MorphoCompounderVaultFactory Test (Yield Donating)
/// @author Octant
/// @notice Integration tests for the MorphoCompounderStrategyFactory (yield donating version) using a mainnet fork
contract MorphoCompounderDonatingVaultFactoryTest is Test {
    using SafeERC20 for ERC20;

    // Factory for creating strategies
    YieldDonatingTokenizedStrategy public tokenizedStrategy;
    MorphoCompounderStrategyFactory public factory;
    YieldDonatingTokenizedStrategy public implementation;

    // Strategy parameters
    address public management;
    address public keeper;
    address public emergencyAdmin;
    address public donationAddress;

    // Mainnet addresses
    address public constant MORPHO_VAULT = 0x074134A2784F4F66b6ceD6f68849382990Ff3215; // Steakhouse USDC vault
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC token
    address public constant TOKENIZED_STRATEGY_ADDRESS = 0x8cf7246a74704bBE59c9dF614ccB5e3d9717d8Ac;

    // Test constants
    uint256 public mainnetFork;
    uint256 public mainnetForkBlock = 22508883 - 6500 * 90; // latest alchemy block - 90 days

    function setUp() public {
        // Create a mainnet fork
        mainnetFork = vm.createFork("mainnet");
        vm.selectFork(mainnetFork);

        // Etch YieldDonatingTokenizedStrategy
        implementation = new YieldDonatingTokenizedStrategy{ salt: keccak256("OCT_YIELD_DONATING_STRATEGY_V1") }();
        bytes memory tokenizedStrategyBytecode = address(implementation).code;
        vm.etch(TOKENIZED_STRATEGY_ADDRESS, tokenizedStrategyBytecode);

        // Now use that address as our tokenizedStrategy
        tokenizedStrategy = YieldDonatingTokenizedStrategy(TOKENIZED_STRATEGY_ADDRESS);

        // Set up addresses
        management = address(0x1);
        keeper = address(0x2);
        emergencyAdmin = address(0x3);
        donationAddress = address(0x4);

        // Deploy factory
        factory = new MorphoCompounderStrategyFactory();

        // Label addresses for better trace outputs
        vm.label(address(factory), "MorphoCompounderDonatingVaultFactory");
        vm.label(MORPHO_VAULT, "Morpho Compounder Vault");
        vm.label(USDC, "USDC");
        vm.label(TOKENIZED_STRATEGY_ADDRESS, "TokenizedStrategy");
        vm.label(management, "Management");
        vm.label(keeper, "Keeper");
        vm.label(emergencyAdmin, "Emergency Admin");
        vm.label(donationAddress, "Donation Address");
    }

    /// @notice Test creating a strategy through the factory
    function testCreateStrategy() public {
        string memory vaultSharesName = "MorphoCompounder Donating Vault Shares";

        // Generate parameter hash for prediction
        bytes32 parameterHash = keccak256(
            abi.encode(
                MORPHO_VAULT,
                0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                vaultSharesName,
                management,
                keeper,
                emergencyAdmin,
                donationAddress,
                false, // enableBurning
                address(implementation)
            )
        );

        // Build the bytecode for address prediction
        bytes memory bytecode = abi.encodePacked(
            type(MorphoCompounderStrategy).creationCode,
            abi.encode(
                MORPHO_VAULT,
                0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                vaultSharesName,
                management,
                keeper,
                emergencyAdmin,
                donationAddress,
                false, // enableBurning
                address(implementation)
            )
        );

        address expectedStrategyAddress = factory.predictStrategyAddress(parameterHash, management, bytecode);

        // Create a strategy and check events
        vm.startPrank(management);
        vm.expectEmit(true, true, true, false); // Check first 3 indexed params, ignore the non-indexed timestamp
        emit MorphoCompounderStrategyFactory.StrategyDeploy(
            management,
            donationAddress,
            expectedStrategyAddress,
            vaultSharesName
        );

        address strategyAddress = factory.createStrategy(
            MORPHO_VAULT,
            vaultSharesName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false, // enableBurning
            address(implementation)
        );
        vm.stopPrank();

        // Verify strategy is tracked in factory
        (address deployerAddress, uint256 timestamp, string memory name, address stratDonationAddress) = factory
            .strategies(management, 0);

        assertEq(deployerAddress, management, "Deployer address incorrect in factory");
        assertEq(name, vaultSharesName, "Vault shares name incorrect in factory");
        assertEq(stratDonationAddress, donationAddress, "Donation address incorrect in factory");
        assertTrue(timestamp > 0, "Timestamp should be set");

        // Verify strategy was initialized correctly
        MorphoCompounderStrategy strategy = MorphoCompounderStrategy(strategyAddress);
        assertEq(IERC4626(address(strategy)).asset(), USDC, "Asset should be USDC");
    }

    /// @notice Test creating multiple strategies for the same user
    function testMultipleStrategiesPerUser() public {
        // Create first strategy
        string memory firstVaultName = "First MorphoCompounder Donating Vault";

        vm.startPrank(management);
        address firstStrategyAddress = factory.createStrategy(
            MORPHO_VAULT,
            firstVaultName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false, // enableBurning
            address(implementation)
        );

        // Create second strategy for same user
        string memory secondVaultName = "Second MorphoCompounder Donating Vault";

        address secondStrategyAddress = factory.createStrategy(
            MORPHO_VAULT,
            secondVaultName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false, // enableBurning
            address(implementation)
        );
        vm.stopPrank();

        // Verify both strategies exist
        (address deployerAddress, , string memory name, ) = factory.strategies(management, 0);
        assertEq(deployerAddress, management, "First deployer address incorrect");
        assertEq(name, firstVaultName, "First vault name incorrect");

        (deployerAddress, , name, ) = factory.strategies(management, 1);
        assertEq(deployerAddress, management, "Second deployer address incorrect");
        assertEq(name, secondVaultName, "Second vault name incorrect");

        // Verify strategies are different
        assertTrue(firstStrategyAddress != secondStrategyAddress, "Strategies should have different addresses");
    }

    /// @notice Test creating strategies for different users
    function testMultipleUsers() public {
        string memory firstVaultName = "First User's Donating Vault";

        address firstUser = address(0x5678);
        address secondUser = address(0x9876);

        // Create strategy for first user
        vm.startPrank(firstUser);
        address firstStrategyAddress = factory.createStrategy(
            MORPHO_VAULT,
            firstVaultName,
            firstUser,
            keeper,
            emergencyAdmin,
            donationAddress,
            false, // enableBurning
            address(implementation)
        );
        vm.stopPrank();

        // Create strategy for second user
        string memory secondVaultName = "Second User's Donating Vault";

        vm.startPrank(secondUser);
        address secondStrategyAddress = factory.createStrategy(
            MORPHO_VAULT,
            secondVaultName,
            secondUser,
            keeper,
            emergencyAdmin,
            donationAddress,
            false, // enableBurning
            address(implementation)
        );
        vm.stopPrank();

        // Verify strategies are properly tracked for each user
        (address deployerAddress, , string memory name, ) = factory.strategies(firstUser, 0);
        assertEq(deployerAddress, firstUser, "First user's deployer address incorrect");
        assertEq(name, firstVaultName, "First user's vault name incorrect");

        (deployerAddress, , name, ) = factory.strategies(secondUser, 0);
        assertEq(deployerAddress, secondUser, "Second user's deployer address incorrect");
        assertEq(name, secondVaultName, "Second user's vault name incorrect");

        // Verify strategies are different
        assertTrue(firstStrategyAddress != secondStrategyAddress, "Strategies should have different addresses");
    }

    /// @notice Test for deterministic addressing and duplicate prevention
    function testDeterministicAddressing() public {
        string memory vaultSharesName = "Deterministic Donating Vault";

        // Create a strategy
        vm.startPrank(management);
        address firstAddress = factory.createStrategy(
            MORPHO_VAULT,
            vaultSharesName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false, // enableBurning
            address(implementation)
        );
        vm.stopPrank();

        // Try to deploy the exact same strategy again - should revert
        vm.startPrank(management);
        vm.expectRevert(
            abi.encodeWithSelector(MorphoCompounderStrategyFactory.StrategyAlreadyExists.selector, firstAddress)
        );
        factory.createStrategy(
            MORPHO_VAULT,
            vaultSharesName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false, // enableBurning
            address(implementation)
        );
        vm.stopPrank();

        // Create a strategy with different parameters - should succeed
        string memory differentName = "Different Donating Vault";
        vm.startPrank(management);
        address secondAddress = factory.createStrategy(
            MORPHO_VAULT,
            differentName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false, // enableBurning
            address(implementation)
        );
        vm.stopPrank();

        // Different parameters should result in different address
        assertTrue(firstAddress != secondAddress, "Different params should create different address");
    }

    /// @notice Test creating strategies with different Morpho vaults
    function testDifferentMorphoVaults() public {
        string memory firstVaultName = "First Morpho Vault Strategy";
        string memory secondVaultName = "Second Morpho Vault Strategy";

        // Use a different Morpho vault address for the second strategy
        address secondMorphoVault = 0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204; // another usdc vault

        vm.startPrank(management);
        address firstStrategyAddress = factory.createStrategy(
            MORPHO_VAULT,
            firstVaultName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false, // enableBurning
            address(implementation)
        );

        address secondStrategyAddress = factory.createStrategy(
            secondMorphoVault,
            secondVaultName,
            management,
            keeper,
            emergencyAdmin,
            donationAddress,
            false, // enableBurning
            address(implementation)
        );
        vm.stopPrank();

        // Verify both strategies exist and are different
        assertTrue(firstStrategyAddress != secondStrategyAddress, "Strategies should have different addresses");

        // Verify both strategies are tracked in factory
        (address deployerAddress, , string memory name, ) = factory.strategies(management, 0);
        assertEq(deployerAddress, management, "First deployer address incorrect");
        assertEq(name, firstVaultName, "First vault name incorrect");

        (deployerAddress, , name, ) = factory.strategies(management, 1);
        assertEq(deployerAddress, management, "Second deployer address incorrect");
        assertEq(name, secondVaultName, "Second vault name incorrect");
    }
}
