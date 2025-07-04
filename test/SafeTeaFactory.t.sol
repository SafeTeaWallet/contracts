// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "../src/SafeTeaFactory.sol";
import "../src/SafeTeaWallet.sol";

contract SafeTeaFactoryTest is Test {
    SafeTeaFactory factory;

    address owner1 = address(0x1);
    address owner2 = address(0x2);
    address owner3 = address(0x3);
    address nonOwner = address(0x999);

    address[] owners;

    event WalletCreated(address indexed wallet, address[] owners);

    function setUp() public {
        owners.push(owner1);
        owners.push(owner2);
        owners.push(owner3);

        factory = new SafeTeaFactory();
    }

    // Test factory deployment
    function testFactoryDeployment() public view {
        assertTrue(address(factory) != address(0), "Factory should be deployed");
    }

    // Test wallet creation
    function testCreateWallet() public {
        // Set up expectEmit BEFORE the actual call
        // Parameters: (checkTopic1, checkTopic2, checkTopic3, checkData, emitter)
        // - true: check first indexed param (wallet address) - but we don't know it yet
        // - false: no second indexed param
        // - false: no third indexed param
        // - true: check non-indexed data (owners array)
        // - address(factory): check emitter address
        vm.expectEmit(false, false, false, true, address(factory));

        // Emit the expected event with the data we want to check
        // We use address(0) as placeholder since we don't know the wallet address yet
        emit WalletCreated(address(0), owners);

        // Perform the actual call that should emit the event
        address walletAddress = factory.createWallet(owners);

        // Rest of your assertions...
        assertTrue(walletAddress != address(0), "Wallet should be created");
        assertTrue(factory.isSafeTeaWallet(walletAddress), "Should be registered as SafeTeaWallet");

        address[] memory allWallets = factory.getAllWallets();
        assertEq(allWallets.length, 1, "Should have 1 wallet");
        assertEq(allWallets[0], walletAddress, "Wallet address should match");

        for (uint256 i = 0; i < owners.length; i++) {
            address[] memory userWallets = factory.getUserWallets(owners[i]);
            assertEq(userWallets.length, 1, "Owner should have 1 wallet");
            assertEq(userWallets[0], walletAddress, "Wallet address should match");
        }
    }

    // Test multiple wallet creation
    function testCreateMultipleWallets() public {
        address wallet1 = factory.createWallet(owners);
        address wallet2 = factory.createWallet(owners);

        assertTrue(wallet1 != wallet2, "Wallets should be different");

        address[] memory allWallets = factory.getAllWallets();
        assertEq(allWallets.length, 2, "Should have 2 wallets");

        for (uint256 i = 0; i < owners.length; i++) {
            address[] memory userWallets = factory.getUserWallets(owners[i]);
            assertEq(userWallets.length, 2, "Owner should have 2 wallets");
        }
    }

    // Test getUserWallets for non-owner
    function testGetUserWalletsForNonOwner() public {
        factory.createWallet(owners);

        address[] memory wallets = factory.getUserWallets(nonOwner);
        assertEq(wallets.length, 0, "Non-owner should have no wallets");
    }

    // Test updateWalletOwners from non-wallet
    function testUpdateWalletOwnersFromNonWallet() public {
        vm.expectRevert("Only SafeTeaWallet");
        factory.updateWalletOwners(owners);
    }

    // Test updateWalletOwners from wallet
    function testUpdateWalletOwnersFromWallet() public {
        address walletAddress = factory.createWallet(owners);

        // Create new owners array
        address[] memory newOwners = new address[](2);
        newOwners[0] = address(0x4);
        newOwners[1] = address(0x5);

        // Impersonate the wallet
        vm.prank(walletAddress);
        factory.updateWalletOwners(newOwners);

        // Verify new owners have the wallet
        for (uint256 i = 0; i < newOwners.length; i++) {
            address[] memory userWallets = factory.getUserWallets(newOwners[i]);
            assertEq(userWallets.length, 1, "New owner should have the wallet");
            assertEq(userWallets[0], walletAddress, "Wallet address should match");
        }

        // Verify original owners still have the wallet (no removal in factory)
        for (uint256 i = 0; i < owners.length; i++) {
            address[] memory userWallets = factory.getUserWallets(owners[i]);
            assertEq(userWallets.length, 1, "Original owner should still have the wallet");
        }
    }

    // Test getAllWallets with no wallets
    function testGetAllWalletsEmpty() public view {
        address[] memory wallets = factory.getAllWallets();
        assertEq(wallets.length, 0, "Should have no wallets initially");
    }

    // Test wallet creation with empty owners array
    function testCreateWalletWithEmptyOwners() public {
        address[] memory emptyOwners;

        vm.expectRevert(SafeTeaWallet.NotUnique.selector);
        factory.createWallet(emptyOwners);
    }

    // Test wallet creation with duplicate owners
    function testCreateWalletWithDuplicateOwners() public {
        address[] memory duplicateOwners = new address[](2);
        duplicateOwners[0] = owner1;
        duplicateOwners[1] = owner1;

        vm.expectRevert("Duplicate owners");
        factory.createWallet(duplicateOwners);
    }

    // Test wallet creation with zero address owner
    function testCreateWalletWithZeroAddressOwner() public {
        address[] memory invalidOwners = new address[](2);
        invalidOwners[0] = owner1;
        invalidOwners[1] = address(0);

        vm.expectRevert("Zero address");
        factory.createWallet(invalidOwners);
    }
}
