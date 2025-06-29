// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Interfaces/ISafeTeaFactory.sol";

contract SafeTeaWallet {
    address[] public owners;
    ISafeTeaFactory public safeTeaFactory;

    enum OwnerProposalType {
        Add,
        Remove
    }

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        bool canceled;
        uint256 confirmations;
        uint256 rejections;
        uint256 expiry;
        uint256 createdAt;
    }

    struct OwnerProposal {
        address proposedOwner;
        bool executed;
        bool canceled;
        OwnerProposalType proposalType;
        uint256 confirmations;
        uint256 rejections;
        uint256 expiry;
        uint256 createdAt;
    }

    mapping(address => bool) public isOwner;
    mapping(uint256 => mapping(address => bool)) public transactionConfirmed;
    mapping(uint256 => mapping(address => bool)) public transactionRejected;
    mapping(uint256 => mapping(address => bool)) public ownerProposalConfirmed;
    mapping(uint256 => mapping(address => bool)) public ownerProposalRejected;

    Transaction[] public transactions;
    OwnerProposal[] public ownerProposals;

    event TransactionSubmitted(uint256 indexed txIndex, address indexed to, uint256 value);
    event TransactionConfirmed(uint256 indexed txIndex, address indexed owner);
    event TransactionRejected(uint256 indexed txIndex, address indexed owner);
    event TransactionExecuted(uint256 indexed txIndex);
    event TransactionCanceled(uint256 indexed txIndex);
    event TransactionExpired(uint256 indexed txIndex);

    event OwnerProposed(
        uint256 indexed proposalIndex, address indexed proposedOwner, OwnerProposalType indexed proposalType
    );
    event OwnerProposalConfirmed(uint256 indexed proposalIndex, address indexed owner);
    event OwnerProposalRejected(uint256 indexed proposalIndex, address indexed owner);
    event OwnerAdded(uint256 indexed proposalIndex, address indexed newOwner);
    event OwnerRemoved(uint256 indexed proposalIndex, address indexed removedOwner);
    event OwnerProposalCanceled(uint256 indexed proposalIndex);
    event OwnerProposalExpired(uint256 indexed proposalIndex);

    modifier onlyOwner() {
        require(isOwner[msg.sender], "Not owner");
        _;
    }

    modifier txExists(uint256 txIndex) {
        require(txIndex < transactions.length, "Tx doesn't exist");
        _;
    }

    modifier proposalExists(uint256 proposalIndex) {
        require(proposalIndex < ownerProposals.length, "Proposal doesn't exist");
        _;
    }

    modifier notTxConfirmed(uint256 txIndex) {
        require(!transactionConfirmed[txIndex][msg.sender], "Already confirmed");
        _;
    }

    modifier notTxRejected(uint256 txIndex) {
        require(!transactionRejected[txIndex][msg.sender], "Already rejected");
        _;
    }

    modifier notProposalConfirmed(uint256 proposalIndex) {
        require(!ownerProposalConfirmed[proposalIndex][msg.sender], "Already confirmed");
        _;
    }

    modifier notProposalRejected(uint256 proposalIndex) {
        require(!ownerProposalRejected[proposalIndex][msg.sender], "Already rejected");
        _;
    }

    modifier notExecuted(uint256 txIndex) {
        require(!transactions[txIndex].executed, "Already executed");
        _;
    }

    modifier notCanceled(uint256 txIndex) {
        require(!transactions[txIndex].canceled, "Already canceled");
        _;
    }

    modifier notExpired(uint256 txIndex) {
        require(block.timestamp <= transactions[txIndex].expiry, "Transaction expired");
        _;
    }

    modifier notProposalExecuted(uint256 proposalIndex) {
        require(!ownerProposals[proposalIndex].executed, "Already executed");
        _;
    }

    modifier notProposalCanceled(uint256 proposalIndex) {
        require(!ownerProposals[proposalIndex].canceled, "Already canceled");
        _;
    }

    modifier notProposalExpired(uint256 proposalIndex) {
        require(block.timestamp <= ownerProposals[proposalIndex].expiry, "Proposal expired");
        _;
    }

    constructor(address[] memory _owners, address _factory) {
        require(_owners.length > 0, "Owners required");
        require(_owners.length >= 2, "Minimum 2 owners required for majority voting");
        require(_factory != address(0), "Zero address");

        safeTeaFactory = ISafeTeaFactory(_factory);

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "Zero address");
            require(!isOwner[owner], "Not unique");

            isOwner[owner] = true;
            owners.push(owner);
        }
    }

    receive() external payable {}

    // Calculate majority threshold (51% of owners)
    function getMajorityThreshold() public view returns (uint256) {
        return (owners.length / 2) + 1;
    }

    function submitTransaction(address to, uint256 value, bytes memory data, uint256 _expiry)
        public
        onlyOwner
        returns (uint256 txIndex)
    {
        require(_expiry > block.timestamp, "Expiry must be in future");
        require(_expiry <= block.timestamp + 30 days, "Expiry too far in future");

        txIndex = transactions.length;
        transactions.push(
            Transaction({
                to: to,
                value: value,
                data: data,
                executed: false,
                canceled: false,
                confirmations: 0,
                rejections: 0,
                expiry: _expiry,
                createdAt: block.timestamp
            })
        );

        emit TransactionSubmitted(txIndex, to, value);
        return txIndex;
    }

    function confirmTransaction(uint256 txIndex)
        public
        onlyOwner
        txExists(txIndex)
        notTxConfirmed(txIndex)
        notTxRejected(txIndex)
        notExecuted(txIndex)
        notCanceled(txIndex)
        notExpired(txIndex)
    {
        transactionConfirmed[txIndex][msg.sender] = true;
        transactions[txIndex].confirmations += 1;

        emit TransactionConfirmed(txIndex, msg.sender);

        // Execute if majority reached
        if (transactions[txIndex].confirmations >= getMajorityThreshold()) {
            _executeTransaction(txIndex);
        }
    }

    function rejectTransaction(uint256 txIndex)
        public
        onlyOwner
        txExists(txIndex)
        notTxConfirmed(txIndex)
        notTxRejected(txIndex)
        notExecuted(txIndex)
        notCanceled(txIndex)
        notExpired(txIndex)
    {
        transactionRejected[txIndex][msg.sender] = true;
        transactions[txIndex].rejections += 1;

        emit TransactionRejected(txIndex, msg.sender);

        // Cancel if majority rejected
        if (transactions[txIndex].rejections >= getMajorityThreshold()) {
            transactions[txIndex].canceled = true;
            emit TransactionCanceled(txIndex);
        }
    }

    function _executeTransaction(uint256 txIndex) internal {
        Transaction storage txn = transactions[txIndex];

        txn.executed = true;
        (bool success,) = txn.to.call{value: txn.value}(txn.data);
        require(success, "Transaction execution failed");

        emit TransactionExecuted(txIndex);
    }

    function executeTransaction(uint256 txIndex)
        public
        onlyOwner
        txExists(txIndex)
        notExecuted(txIndex)
        notCanceled(txIndex)
        notExpired(txIndex)
    {
        require(transactions[txIndex].confirmations >= getMajorityThreshold(), "Not enough confirmations");

        _executeTransaction(txIndex);
    }

    // Mark expired transactions
    function markTransactionExpired(uint256 txIndex)
        public
        txExists(txIndex)
        notExecuted(txIndex)
        notCanceled(txIndex)
    {
        require(block.timestamp > transactions[txIndex].expiry, "Not expired yet");
        transactions[txIndex].canceled = true;
        emit TransactionExpired(txIndex);
    }

    // Propose new owner
    function proposeOwner(address newOwner, OwnerProposalType proposalType, uint256 _expiry)
        public
        onlyOwner
        returns (uint256 proposalIndex)
    {
        // Input validation
        require(newOwner != address(0), "Zero address");
        require(_expiry > block.timestamp, "Expiry must be in future");
        require(_expiry <= block.timestamp + 30 days, "Expiry too far in future");

        // Additional validation based on proposal type
        if (proposalType == OwnerProposalType.Add) {
            require(!isOwner[newOwner], "Already an owner");
        } else if (proposalType == OwnerProposalType.Remove) {
            require(isOwner[newOwner], "Not an owner");
        }

        // Create new proposal
        proposalIndex = ownerProposals.length;
        ownerProposals.push(
            OwnerProposal({
                proposedOwner: newOwner,
                executed: false,
                canceled: false,
                proposalType: proposalType,
                confirmations: 0,
                rejections: 0,
                expiry: _expiry,
                createdAt: block.timestamp
            })
        );

        emit OwnerProposed(proposalIndex, newOwner, proposalType);
        return proposalIndex;
    }

    function confirmOwnerProposal(uint256 proposalIndex)
        public
        onlyOwner
        proposalExists(proposalIndex)
        notProposalConfirmed(proposalIndex)
        notProposalRejected(proposalIndex)
        notProposalExecuted(proposalIndex)
        notProposalCanceled(proposalIndex)
        notProposalExpired(proposalIndex)
    {
        ownerProposalConfirmed[proposalIndex][msg.sender] = true;
        ownerProposals[proposalIndex].confirmations += 1;

        emit OwnerProposalConfirmed(proposalIndex, msg.sender);

        // Execute if majority reached
        if (ownerProposals[proposalIndex].confirmations >= getMajorityThreshold()) {
            _executeOwnerProposal(proposalIndex);
        }
    }

    function rejectOwnerProposal(uint256 proposalIndex)
        public
        onlyOwner
        proposalExists(proposalIndex)
        notProposalConfirmed(proposalIndex)
        notProposalRejected(proposalIndex)
        notProposalExecuted(proposalIndex)
        notProposalCanceled(proposalIndex)
        notProposalExpired(proposalIndex)
    {
        ownerProposalRejected[proposalIndex][msg.sender] = true;
        ownerProposals[proposalIndex].rejections += 1;

        emit OwnerProposalRejected(proposalIndex, msg.sender);

        // Cancel if majority rejected
        if (ownerProposals[proposalIndex].rejections >= getMajorityThreshold()) {
            ownerProposals[proposalIndex].canceled = true;
            emit OwnerProposalCanceled(proposalIndex);
        }
    }

    function _executeOwnerProposal(uint256 proposalIndex) internal {
        OwnerProposal storage proposal = ownerProposals[proposalIndex];

        require(!proposal.executed, "Proposal already executed");
        require(block.timestamp <= proposal.expiry, "Proposal expired");

        proposal.executed = true;

        if (proposal.proposalType == OwnerProposalType.Add) {
            // Add the new owner
            require(!isOwner[proposal.proposedOwner], "Already an owner");
            owners.push(proposal.proposedOwner);
            isOwner[proposal.proposedOwner] = true;
            emit OwnerAdded(proposalIndex, proposal.proposedOwner);
        } else if (proposal.proposalType == OwnerProposalType.Remove) {
            // Remove the owner
            require(isOwner[proposal.proposedOwner], "Not an owner");
            require(owners.length > 2, "Cannot remove last owner");

            // Find and remove the owner from the array
            for (uint256 i = 0; i < owners.length; i++) {
                if (owners[i] == proposal.proposedOwner) {
                    // Swap with last element and pop
                    owners[i] = owners[owners.length - 1];
                    owners.pop();
                    break;
                }
            }

            isOwner[proposal.proposedOwner] = false;
            emit OwnerRemoved(proposalIndex, proposal.proposedOwner);
        }

        // Update wallet owners in factory
        safeTeaFactory.updateWalletOwners(owners);
    }

    // Mark expired owner proposals
    function markOwnerProposalExpired(uint256 proposalIndex)
        public
        proposalExists(proposalIndex)
        notProposalExecuted(proposalIndex)
        notProposalCanceled(proposalIndex)
    {
        require(block.timestamp > ownerProposals[proposalIndex].expiry, "Not expired yet");
        ownerProposals[proposalIndex].canceled = true;
        emit OwnerProposalExpired(proposalIndex);
    }

    // View functions
    function getOwners() public view returns (address[] memory) {
        return owners;
    }

    function getOwnerCount() public view returns (uint256) {
        return owners.length;
    }

    function getTransactionCount() public view returns (uint256) {
        return transactions.length;
    }

    function getOwnerProposalCount() public view returns (uint256) {
        return ownerProposals.length;
    }

    function getTransaction(uint256 index)
        public
        view
        returns (
            address to,
            uint256 value,
            bytes memory data,
            bool executed,
            bool canceled,
            uint256 confirmations,
            uint256 rejections,
            uint256 expiry,
            uint256 createdAt
        )
    {
        require(index < transactions.length, "Transaction doesn't exist");
        Transaction storage txn = transactions[index];
        return (
            txn.to,
            txn.value,
            txn.data,
            txn.executed,
            txn.canceled,
            txn.confirmations,
            txn.rejections,
            txn.expiry,
            txn.createdAt
        );
    }

    function getOwnerProposal(uint256 index)
        public
        view
        returns (
            address proposedOwner,
            bool executed,
            bool canceled,
            uint256 confirmations,
            uint256 rejections,
            uint256 expiry,
            uint256 createdAt
        )
    {
        require(index < ownerProposals.length, "Proposal doesn't exist");
        OwnerProposal storage proposal = ownerProposals[index];
        return (
            proposal.proposedOwner,
            proposal.executed,
            proposal.canceled,
            proposal.confirmations,
            proposal.rejections,
            proposal.expiry,
            proposal.createdAt
        );
    }

    function isTransactionExpired(uint256 txIndex) public view returns (bool) {
        require(txIndex < transactions.length, "Transaction doesn't exist");
        return block.timestamp > transactions[txIndex].expiry;
    }

    function isOwnerProposalExpired(uint256 proposalIndex) public view returns (bool) {
        require(proposalIndex < ownerProposals.length, "Proposal doesn't exist");
        return block.timestamp > ownerProposals[proposalIndex].expiry;
    }

    function hasConfirmedTransaction(uint256 txIndex, address owner) public view returns (bool) {
        return transactionConfirmed[txIndex][owner];
    }

    function hasRejectedTransaction(uint256 txIndex, address owner) public view returns (bool) {
        return transactionRejected[txIndex][owner];
    }

    function hasConfirmedOwnerProposal(uint256 proposalIndex, address owner) public view returns (bool) {
        return ownerProposalConfirmed[proposalIndex][owner];
    }

    function hasRejectedOwnerProposal(uint256 proposalIndex, address owner) public view returns (bool) {
        return ownerProposalRejected[proposalIndex][owner];
    }
}
