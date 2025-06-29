// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "../src/SafeTeaWallet.sol";
import "../src/SafeTeaFactory.sol";

contract SafeTeaWalletTest is Test {
    SafeTeaWallet wallet;
    SafeTeaFactory factory;

    address owner1 = address(0x1);
    address owner2 = address(0x2);
    address owner3 = address(0x3);
    address nonOwner = address(0x999);
    address recipient = address(0x777);

    address[] owners;

    // Events from SafeTeaWallet
    event TransactionSubmitted(uint256 indexed txIndex, address indexed to, uint256 value);
    event TransactionConfirmed(uint256 indexed txIndex, address indexed owner);
    event TransactionRejected(uint256 indexed txIndex, address indexed owner);
    event TransactionExecuted(uint256 indexed txIndex);
    event TransactionCanceled(uint256 indexed txIndex);
    event TransactionExpired(uint256 indexed txIndex);
    event OwnerProposed(
        uint256 indexed proposalIndex,
        address indexed proposedOwner,
        SafeTeaWallet.OwnerProposalType indexed proposalType
    );
    event OwnerProposalConfirmed(uint256 indexed proposalIndex, address indexed owner);
    event OwnerProposalRejected(uint256 indexed proposalIndex, address indexed owner);
    event OwnerAdded(uint256 indexed proposalIndex, address indexed newOwner);
    event OwnerRemoved(uint256 indexed proposalIndex, address indexed removedOwner);
    event OwnerProposalCanceled(uint256 indexed proposalIndex);
    event OwnerProposalExpired(uint256 indexed proposalIndex);

    function setUp() public {
        factory = new SafeTeaFactory();

        owners.push(owner1);
        owners.push(owner2);
        owners.push(owner3);

        wallet = SafeTeaWallet(payable(factory.createWallet(owners)));

        // Fund the wallet
        vm.deal(address(wallet), 10 ether);
    }

    // ============ Constructor Tests ============
    function testConstructor() public view {
        assertEq(wallet.getOwnerCount(), 3, "Should have 3 owners");
        assertTrue(wallet.isOwner(owner1), "Owner1 should be owner");
        assertTrue(wallet.isOwner(owner2), "Owner2 should be owner");
        assertTrue(wallet.isOwner(owner3), "Owner3 should be owner");
        assertEq(address(wallet.safeTeaFactory()), address(factory), "Factory address should be set");
    }

    function testConstructorWithZeroAddressFactory() public {
        address[] memory singleOwner = new address[](2);
        singleOwner[0] = owner1;
        singleOwner[1] = owner2;

        vm.expectRevert("Zero address");
        new SafeTeaWallet(singleOwner, address(0));
    }

    function testConstructorWithEmptyOwners() public {
        address[] memory emptyOwners;

        vm.expectRevert("Owners required");
        new SafeTeaWallet(emptyOwners, address(factory));
    }

    function testConstructorWithSingleOwner() public {
        address[] memory singleOwner = new address[](1);
        singleOwner[0] = owner1;

        vm.expectRevert("Minimum 2 owners required for majority voting");
        new SafeTeaWallet(singleOwner, address(factory));
    }

    function testConstructorWithDuplicateOwners() public {
        address[] memory duplicateOwners = new address[](2);
        duplicateOwners[0] = owner1;
        duplicateOwners[1] = owner1;

        vm.expectRevert("Not unique");
        new SafeTeaWallet(duplicateOwners, address(factory));
    }

    function testConstructorWithZeroAddressOwner() public {
        address[] memory invalidOwners = new address[](2);
        invalidOwners[0] = owner1;
        invalidOwners[1] = address(0);

        vm.expectRevert("Zero address");
        new SafeTeaWallet(invalidOwners, address(factory));
    }

    function testConstructorWithMinimumOwner() public {
        address[] memory invalidOwners = new address[](1);
        invalidOwners[0] = owner1;

        vm.expectRevert("Minimum 2 owners required for majority voting");
        new SafeTeaWallet(invalidOwners, address(factory));
    }

    // ============ Transaction Tests ============
    function testSubmitTransaction() public {
        vm.prank(owner1);
        uint256 expiry = block.timestamp + 1 days;

        vm.expectEmit(true, true, false, true);
        emit TransactionSubmitted(0, recipient, 1 ether);

        uint256 txIndex = wallet.submitTransaction(recipient, 1 ether, "", expiry);

        assertEq(txIndex, 0, "Should be first transaction");
        assertEq(wallet.getTransactionCount(), 1, "Transaction count should be 1");

        (address to, uint256 value,, bool executed, bool canceled,,, uint256 txExpiry,) = wallet.getTransaction(0);
        assertEq(to, recipient, "Recipient should match");
        assertEq(value, 1 ether, "Value should match");
        assertFalse(executed, "Should not be executed");
        assertFalse(canceled, "Should not be canceled");
        assertEq(txExpiry, expiry, "Expiry should match");
    }

    function testSubmitTransactionWithInvalidExpiry() public {
        vm.prank(owner1);

        // Past expiry
        vm.expectRevert("Expiry must be in future");
        wallet.submitTransaction(recipient, 1 ether, "", block.timestamp - 1);

        vm.prank(owner1);
        // Too far in future
        vm.expectRevert("Expiry too far in future");
        wallet.submitTransaction(recipient, 1 ether, "", block.timestamp + 31 days);
    }

    function testSubmitTransactionByNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Not owner");
        wallet.submitTransaction(recipient, 1 ether, "", block.timestamp + 1 days);
    }

    function testConfirmTransaction() public {
        // Submit transaction
        vm.prank(owner1);
        uint256 txIndex = wallet.submitTransaction(recipient, 1 ether, "", block.timestamp + 1 days);

        // Confirm
        vm.prank(owner1);
        vm.expectEmit(true, true, false, false);
        emit TransactionConfirmed(txIndex, owner1);
        wallet.confirmTransaction(txIndex);

        (,,,,, uint256 confirmations,,,) = wallet.getTransaction(txIndex);
        assertEq(confirmations, 1, "Should have 1 confirmation");
        assertTrue(wallet.hasConfirmedTransaction(txIndex, owner1), "Owner1 should have confirmed");
    }

    function testConfirmTransactionWithMajority() public {
        // Submit transaction
        vm.prank(owner1);
        uint256 txIndex = wallet.submitTransaction(recipient, 1 ether, "", block.timestamp + 1 days);

        // Confirm by owner1
        vm.prank(owner1);
        wallet.confirmTransaction(txIndex);

        // Confirm by owner2 (majority reached)
        uint256 initialRecipientBalance = recipient.balance;

        vm.prank(owner2);
        vm.expectEmit(true, false, false, false);
        emit TransactionExecuted(txIndex);
        wallet.confirmTransaction(txIndex);

        (,,, bool executed,,,,,) = wallet.getTransaction(txIndex);
        assertTrue(executed, "Transaction should be executed");
        assertEq(recipient.balance, initialRecipientBalance + 1 ether, "Recipient should receive funds");
    }

    function testRejectTransaction() public {
        // Submit transaction
        vm.prank(owner1);
        uint256 txIndex = wallet.submitTransaction(recipient, 1 ether, "", block.timestamp + 1 days);

        // Reject
        vm.prank(owner1);
        vm.expectEmit(true, true, false, false);
        emit TransactionRejected(txIndex, owner1);
        wallet.rejectTransaction(txIndex);

        (,,,,,, uint256 rejections,,) = wallet.getTransaction(txIndex);
        assertEq(rejections, 1, "Should have 1 rejection");
        assertTrue(wallet.hasRejectedTransaction(txIndex, owner1), "Owner1 should have rejected");
    }

    function testRejectTransactionWithMajority() public {
        // Submit transaction
        vm.prank(owner1);
        uint256 txIndex = wallet.submitTransaction(recipient, 1 ether, "", block.timestamp + 1 days);

        // Reject by owner1
        vm.prank(owner1);
        wallet.rejectTransaction(txIndex);

        // Reject by owner2 (majority reached)
        vm.prank(owner2);
        vm.expectEmit(true, false, false, false);
        emit TransactionCanceled(txIndex);
        wallet.rejectTransaction(txIndex);

        (,,,, bool canceled,,,,) = wallet.getTransaction(txIndex);
        assertTrue(canceled, "Transaction should be canceled");
    }

    function testExecuteTransaction() public {
        // Submit transaction
        vm.prank(owner1);
        uint256 txIndex = wallet.submitTransaction(recipient, 1 ether, "", block.timestamp + 1 days);

        // Confirm by all owners
        vm.prank(owner1);
        wallet.confirmTransaction(txIndex);

        uint256 initialRecipientBalance = recipient.balance;

        vm.prank(owner2);
        vm.expectEmit(true, false, false, false);
        emit TransactionExecuted(txIndex);
        wallet.confirmTransaction(txIndex);

        assertEq(recipient.balance, initialRecipientBalance + 1 ether, "Recipient should receive funds");
    }

    function testExecuteTransactionWithoutMajority() public {
        // Submit transaction
        vm.prank(owner1);
        uint256 txIndex = wallet.submitTransaction(recipient, 1 ether, "", block.timestamp + 1 days);

        // Confirm by only one owner
        vm.prank(owner1);
        wallet.confirmTransaction(txIndex);

        // Try to execute
        vm.prank(owner1);
        vm.expectRevert("Not enough confirmations");
        wallet.executeTransaction(txIndex);
    }

    function testMarkTransactionExpired() public {
        // Submit transaction with short expiry
        vm.prank(owner1);
        uint256 txIndex = wallet.submitTransaction(recipient, 1 ether, "", block.timestamp + 1 hours);

        // Fast forward past expiry
        vm.warp(block.timestamp + 2 hours);

        // Mark as expired
        vm.expectEmit(true, false, false, false);
        emit TransactionExpired(txIndex);
        wallet.markTransactionExpired(txIndex);

        (,,,, bool canceled,,,,) = wallet.getTransaction(txIndex);
        assertTrue(canceled, "Transaction should be marked as expired");
    }

    function testMarkTransactionExpiredPrematurely() public {
        // Submit transaction
        vm.prank(owner1);
        uint256 txIndex = wallet.submitTransaction(recipient, 1 ether, "", block.timestamp + 1 days);

        // Try to mark as expired
        vm.expectRevert("Not expired yet");
        wallet.markTransactionExpired(txIndex);
    }

    // ============ Owner Proposal Tests ============
    function testProposeOwnerAdd() public {
        address newOwner = address(0x123);

        vm.prank(owner1);
        vm.expectEmit(true, true, true, false);
        emit OwnerProposed(0, newOwner, SafeTeaWallet.OwnerProposalType.Add);
        uint256 proposalIndex =
            wallet.proposeOwner(newOwner, SafeTeaWallet.OwnerProposalType.Add, block.timestamp + 7 days);

        assertEq(proposalIndex, 0, "Should be first proposal");
        assertEq(wallet.getOwnerProposalCount(), 1, "Proposal count should be 1");

        (address proposedOwner,,,,,,) = wallet.getOwnerProposal(0);
        assertEq(proposedOwner, newOwner, "Proposed owner should match");
    }

    function testProposeOwnerRemove() public {
        vm.prank(owner1);
        vm.expectEmit(true, true, true, false);
        emit OwnerProposed(0, owner2, SafeTeaWallet.OwnerProposalType.Remove);
        wallet.proposeOwner(owner2, SafeTeaWallet.OwnerProposalType.Remove, block.timestamp + 7 days);
    }

    function testProposeOwnerInvalid() public {
        // Propose existing owner
        vm.prank(owner1);
        vm.expectRevert("Already an owner");
        wallet.proposeOwner(owner2, SafeTeaWallet.OwnerProposalType.Add, block.timestamp + 7 days);

        // Propose non-owner for removal
        address anotherNonOwner = address(0x123);
        vm.prank(owner1);
        vm.expectRevert("Not an owner");
        wallet.proposeOwner(anotherNonOwner, SafeTeaWallet.OwnerProposalType.Remove, block.timestamp + 7 days);

        // Propose zero address
        vm.prank(owner1);
        vm.expectRevert("Zero address");
        wallet.proposeOwner(address(0), SafeTeaWallet.OwnerProposalType.Add, block.timestamp + 7 days);

        // Invalid expiry
        vm.prank(owner1);
        vm.expectRevert("Expiry must be in future");
        wallet.proposeOwner(address(0x123), SafeTeaWallet.OwnerProposalType.Add, block.timestamp - 1);

        vm.prank(owner1);
        vm.expectRevert("Expiry too far in future");
        wallet.proposeOwner(address(0x123), SafeTeaWallet.OwnerProposalType.Add, block.timestamp + 31 days);
    }

    function testConfirmOwnerProposal() public {
        // Propose new owner
        address newOwner = address(0x123);
        vm.prank(owner1);
        uint256 proposalIndex =
            wallet.proposeOwner(newOwner, SafeTeaWallet.OwnerProposalType.Add, block.timestamp + 7 days);

        // Confirm
        vm.prank(owner1);
        vm.expectEmit(true, true, false, false);
        emit OwnerProposalConfirmed(proposalIndex, owner1);
        wallet.confirmOwnerProposal(proposalIndex);

        (,,, uint256 confirmations,,,) = wallet.getOwnerProposal(proposalIndex);
        assertEq(confirmations, 1, "Should have 1 confirmation");
        assertTrue(wallet.hasConfirmedOwnerProposal(proposalIndex, owner1), "Owner1 should have confirmed");
    }

    function testConfirmOwnerProposalWithMajorityAdd() public {
        // Propose new owner
        address newOwner = address(0x123);
        vm.prank(owner1);
        uint256 proposalIndex =
            wallet.proposeOwner(newOwner, SafeTeaWallet.OwnerProposalType.Add, block.timestamp + 7 days);

        // Confirm by owner1
        vm.prank(owner1);
        wallet.confirmOwnerProposal(proposalIndex);

        // Confirm by owner2
        vm.prank(owner2);
        vm.expectEmit(true, true, false, false);
        emit OwnerAdded(proposalIndex, newOwner);
        wallet.confirmOwnerProposal(proposalIndex);

        assertTrue(wallet.isOwner(newOwner), "New owner should be added");
        assertEq(wallet.getOwnerCount(), 4, "Owner count should increase");
    }

    function testConfirmOwnerProposalWithMajorityRemove() public {
        // Propose to remove owner2
        vm.prank(owner1);
        uint256 proposalIndex =
            wallet.proposeOwner(owner2, SafeTeaWallet.OwnerProposalType.Remove, block.timestamp + 7 days);

        // Confirm by owner1
        vm.prank(owner1);
        wallet.confirmOwnerProposal(proposalIndex);

        // Confirm by owner3 (majority reached)
        vm.prank(owner3);
        vm.expectEmit(true, true, false, false);
        emit OwnerRemoved(proposalIndex, owner2);
        wallet.confirmOwnerProposal(proposalIndex);

        assertFalse(wallet.isOwner(owner2), "Owner2 should be removed");
        assertEq(wallet.getOwnerCount(), 2, "Owner count should decrease");
    }

    function testRejectOwnerProposal() public {
        // Propose new owner
        address newOwner = address(0x123);
        vm.prank(owner1);
        uint256 proposalIndex =
            wallet.proposeOwner(newOwner, SafeTeaWallet.OwnerProposalType.Add, block.timestamp + 7 days);

        // Reject
        vm.prank(owner1);
        vm.expectEmit(true, true, false, false);
        emit OwnerProposalRejected(proposalIndex, owner1);
        wallet.rejectOwnerProposal(proposalIndex);

        (,,,, uint256 rejections,,) = wallet.getOwnerProposal(proposalIndex);
        assertEq(rejections, 1, "Should have 1 rejection");
        assertTrue(wallet.hasRejectedOwnerProposal(proposalIndex, owner1), "Owner1 should have rejected");
    }

    function testRejectOwnerProposalWithMajority() public {
        // Propose new owner
        address newOwner = address(0x123);
        vm.prank(owner1);
        uint256 proposalIndex =
            wallet.proposeOwner(newOwner, SafeTeaWallet.OwnerProposalType.Add, block.timestamp + 7 days);

        // Reject by owner1
        vm.prank(owner1);
        wallet.rejectOwnerProposal(proposalIndex);

        // Reject by owner2 (majority reached)
        vm.prank(owner2);
        vm.expectEmit(true, false, false, false);
        emit OwnerProposalCanceled(proposalIndex);
        wallet.rejectOwnerProposal(proposalIndex);

        (,, bool canceled,,,,) = wallet.getOwnerProposal(proposalIndex);
        assertTrue(canceled, "Proposal should be canceled");
    }

    function testMarkOwnerProposalExpired() public {
        // Propose new owner with short expiry
        address newOwner = address(0x123);
        vm.prank(owner1);
        uint256 proposalIndex =
            wallet.proposeOwner(newOwner, SafeTeaWallet.OwnerProposalType.Add, block.timestamp + 1 hours);

        // Fast forward past expiry
        vm.warp(block.timestamp + 2 hours);

        // Mark as expired
        vm.expectEmit(true, false, false, false);
        emit OwnerProposalExpired(proposalIndex);
        wallet.markOwnerProposalExpired(proposalIndex);

        (,, bool canceled,,,,) = wallet.getOwnerProposal(proposalIndex);
        assertTrue(canceled, "Proposal should be marked as expired");
    }

    function testCannotRemoveLastOwner() public {
        // First remove owner2 and owner3
        vm.startPrank(owner1);
        uint256 proposal1 =
            wallet.proposeOwner(owner2, SafeTeaWallet.OwnerProposalType.Remove, block.timestamp + 7 days);
        wallet.confirmOwnerProposal(proposal1);
        vm.stopPrank();

        vm.startPrank(owner3);
        wallet.confirmOwnerProposal(proposal1);
        vm.stopPrank();

        vm.prank(owner2);
        vm.expectRevert("Not owner");
        wallet.confirmOwnerProposal(proposal1);

        // Now try to remove owner3 (would leave only owner1)
        vm.prank(owner1);
        uint256 proposal2 =
            wallet.proposeOwner(owner3, SafeTeaWallet.OwnerProposalType.Remove, block.timestamp + 7 days);

        // Confirm by owner1
        vm.prank(owner1);
        wallet.confirmOwnerProposal(proposal2);

        // Confirm by owner3 (should fail)
        vm.prank(owner3);
        vm.expectRevert("Cannot remove last owner");
        wallet.confirmOwnerProposal(proposal2);
    }

    // ============ View Function Tests ============
    function testGetMajorityThreshold() public {
        assertEq(wallet.getMajorityThreshold(), 2, "3 owners need 2 confirmations (majority)");

        // Add an owner to test threshold change
        vm.startPrank(owner1);
        uint256 proposalIndex =
            wallet.proposeOwner(address(0x123), SafeTeaWallet.OwnerProposalType.Add, block.timestamp + 7 days);
        wallet.confirmOwnerProposal(proposalIndex);
        vm.stopPrank();

        vm.startPrank(owner2);
        wallet.confirmOwnerProposal(proposalIndex);
        vm.stopPrank();

        assertEq(wallet.getMajorityThreshold(), 3, "4 owners need 3 confirmations (majority)");
    }

    function testIsTransactionExpired() public {
        vm.prank(owner1);
        uint256 txIndex = wallet.submitTransaction(recipient, 1 ether, "", block.timestamp + 1 hours);

        assertFalse(wallet.isTransactionExpired(txIndex), "Should not be expired yet");

        vm.warp(block.timestamp + 2 hours);
        assertTrue(wallet.isTransactionExpired(txIndex), "Should be expired now");
    }

    function testIsOwnerProposalExpired() public {
        vm.prank(owner1);
        uint256 proposalIndex =
            wallet.proposeOwner(address(0x123), SafeTeaWallet.OwnerProposalType.Add, block.timestamp + 1 hours);

        assertFalse(wallet.isOwnerProposalExpired(proposalIndex), "Should not be expired yet");

        vm.warp(block.timestamp + 2 hours);
        assertTrue(wallet.isOwnerProposalExpired(proposalIndex), "Should be expired now");
    }

    // ============ Edge Case Tests ============
    function testCannotDoubleVoteTransactions() public {
        vm.prank(owner1);
        uint256 txIndex = wallet.submitTransaction(recipient, 1 ether, "", block.timestamp + 1 days);

        // Confirm once
        vm.prank(owner1);
        wallet.confirmTransaction(txIndex);

        // Try to confirm again
        vm.prank(owner1);
        vm.expectRevert("Already confirmed");
        wallet.confirmTransaction(txIndex);

        // Try to reject after confirming
        vm.prank(owner1);
        vm.expectRevert("Already confirmed");
        wallet.rejectTransaction(txIndex);
    }

    function testCannotDoubleVoteOwnerProposals() public {
        vm.prank(owner1);
        uint256 proposalIndex =
            wallet.proposeOwner(address(0x123), SafeTeaWallet.OwnerProposalType.Add, block.timestamp + 7 days);

        // Confirm once
        vm.prank(owner1);
        wallet.confirmOwnerProposal(proposalIndex);

        // Try to confirm again
        vm.prank(owner1);
        vm.expectRevert("Already confirmed");
        wallet.confirmOwnerProposal(proposalIndex);

        // Try to reject after confirming
        vm.prank(owner1);
        vm.expectRevert("Already confirmed");
        wallet.rejectOwnerProposal(proposalIndex);
    }

    function testCannotExecuteCanceledTransaction() public {
        vm.prank(owner1);
        uint256 txIndex = wallet.submitTransaction(recipient, 1 ether, "", block.timestamp + 1 days);

        // Reject by majority to cancel
        vm.prank(owner1);
        wallet.rejectTransaction(txIndex);
        vm.prank(owner2);
        wallet.rejectTransaction(txIndex);
        vm.prank(owner3);
        vm.expectRevert("Already canceled");
        wallet.rejectTransaction(txIndex);

        // Try to execute
        vm.prank(owner1);
        vm.expectRevert("Already canceled");
        wallet.executeTransaction(txIndex);
    }

    function testCannotExecuteExpiredTransaction() public {
        vm.prank(owner1);
        uint256 txIndex = wallet.submitTransaction(recipient, 1 ether, "", block.timestamp + 1 hours);

        // Fast forward past expiry
        vm.warp(block.timestamp + 2 hours);

        // Try to execute
        vm.prank(owner1);
        vm.expectRevert("Transaction expired");
        wallet.executeTransaction(txIndex);
    }

    // ============ Receive Function Test ============
    function testReceiveFunction() public {
        uint256 initialBalance = address(wallet).balance;
        uint256 sendAmount = 1 ether;

        // Send ETH directly to wallet
        payable(address(wallet)).transfer(sendAmount);

        assertEq(address(wallet).balance, initialBalance + sendAmount, "Wallet should receive ETH");
    }
}
