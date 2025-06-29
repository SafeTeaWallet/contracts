// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

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
        uint8 status; // 0: pending, 1: executed, 2: canceled
        uint16 confirmations;
        uint16 rejections;
        uint32 expiry;
        uint32 createdAt;
    }

    struct OwnerProposal {
        address proposedOwner;
        uint8 status; // 0: pending, 1: executed, 2: canceled
        OwnerProposalType proposalType;
        uint16 confirmations;
        uint16 rejections;
        uint32 expiry;
        uint32 createdAt;
    }

    mapping(address => bool) public isOwner;
    mapping(uint256 => mapping(address => uint8)) public txVotes; // 0: none, 1: confirm, 2: reject
    mapping(uint256 => mapping(address => uint8)) public proposalVotes; // 0: none, 1: confirm, 2: reject

    Transaction[] public transactions;
    OwnerProposal[] public ownerProposals;

    event TransactionSubmitted(uint256 indexed txIndex, address indexed to, uint256 value);
    event TransactionConfirmed(uint256 indexed txIndex, address indexed owner);
    event TransactionRejected(uint256 indexed txIndex, address indexed owner);
    event TransactionExecuted(uint256 indexed txIndex);
    event TransactionCanceled(uint256 indexed txIndex);
    event TransactionExpired(uint256 indexed txIndex);

    event OwnerProposed(uint256 indexed proposalIndex, address indexed proposedOwner, OwnerProposalType indexed proposalType);
    event OwnerProposalConfirmed(uint256 indexed proposalIndex, address indexed owner);
    event OwnerProposalRejected(uint256 indexed proposalIndex, address indexed owner);
    event OwnerAdded(uint256 indexed proposalIndex, address indexed newOwner);
    event OwnerRemoved(uint256 indexed proposalIndex, address indexed removedOwner);
    event OwnerProposalCanceled(uint256 indexed proposalIndex);
    event OwnerProposalExpired(uint256 indexed proposalIndex);

    error NotOwner();
    error TxNotExist();
    error ProposalNotExist();
    error AlreadyVoted();
    error AlreadyExecuted();
    error AlreadyCanceled();
    error Expired();
    error ZeroAddress();
    error NotUnique();
    error InvalidExpiry();
    error AlreadyOwner();
    error NotAnOwner();
    error InsufficientConfirmations();
    error NotExpired();
    error ExecutionFailed();
    error CannotRemoveLastOwner();

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotOwner();
        _;
    }

    modifier validTx(uint256 txIndex) {
        if (txIndex >= transactions.length) revert TxNotExist();
        Transaction storage txn = transactions[txIndex];
        if (txn.status != 0) revert AlreadyExecuted();
        if (block.timestamp > txn.expiry) revert Expired();
        _;
    }

    modifier validProposal(uint256 proposalIndex) {
        if (proposalIndex >= ownerProposals.length) revert ProposalNotExist();
        OwnerProposal storage proposal = ownerProposals[proposalIndex];
        if (proposal.status != 0) revert AlreadyExecuted();
        if (block.timestamp > proposal.expiry) revert Expired();
        _;
    }

    constructor(address[] memory _owners, address _factory) {
        if (_owners.length < 2) revert NotUnique();
        if (_factory == address(0)) revert ZeroAddress();

        safeTeaFactory = ISafeTeaFactory(_factory);

        for (uint256 i; i < _owners.length; ++i) {
            address owner = _owners[i];
            if (owner == address(0)) revert ZeroAddress();
            if (isOwner[owner]) revert NotUnique();
            isOwner[owner] = true;
            owners.push(owner);
        }
    }

    receive() external payable {}

    function getMajorityThreshold() public view returns (uint256) {
        return (owners.length >> 1) + 1;
    }

    function submitTransaction(address to, uint256 value, bytes memory data, uint256 _expiry)
        external
        onlyOwner
        returns (uint256 txIndex)
    {
        if (_expiry <= block.timestamp || _expiry > block.timestamp + 30 days) revert InvalidExpiry();

        txIndex = transactions.length;
        transactions.push(Transaction({
            to: to,
            value: value,
            data: data,
            status: 0,
            confirmations: 0,
            rejections: 0,
            expiry: uint32(_expiry),
            createdAt: uint32(block.timestamp)
        }));

        emit TransactionSubmitted(txIndex, to, value);
    }

    function confirmTransaction(uint256 txIndex) external onlyOwner validTx(txIndex) {
        if (txVotes[txIndex][msg.sender] != 0) revert AlreadyVoted();
        
        txVotes[txIndex][msg.sender] = 1;
        transactions[txIndex].confirmations++;

        emit TransactionConfirmed(txIndex, msg.sender);

        if (transactions[txIndex].confirmations >= getMajorityThreshold()) {
            _executeTransaction(txIndex);
        }
    }

    function rejectTransaction(uint256 txIndex) external onlyOwner validTx(txIndex) {
        if (txVotes[txIndex][msg.sender] != 0) revert AlreadyVoted();
        
        txVotes[txIndex][msg.sender] = 2;
        transactions[txIndex].rejections++;

        emit TransactionRejected(txIndex, msg.sender);

        if (transactions[txIndex].rejections >= getMajorityThreshold()) {
            transactions[txIndex].status = 2;
            emit TransactionCanceled(txIndex);
        }
    }

    function _executeTransaction(uint256 txIndex) internal {
        Transaction storage txn = transactions[txIndex];
        txn.status = 1;
        
        (bool success,) = txn.to.call{value: txn.value}(txn.data);
        if (!success) revert ExecutionFailed();

        emit TransactionExecuted(txIndex);
    }

    function executeTransaction(uint256 txIndex) external onlyOwner validTx(txIndex) {
        if (transactions[txIndex].confirmations < getMajorityThreshold()) revert InsufficientConfirmations();
        _executeTransaction(txIndex);
    }

    function markTransactionExpired(uint256 txIndex) external {
        if (txIndex >= transactions.length) revert TxNotExist();
        Transaction storage txn = transactions[txIndex];
        if (txn.status != 0) revert AlreadyExecuted();
        if (block.timestamp <= txn.expiry) revert NotExpired();
        
        txn.status = 2;
        emit TransactionExpired(txIndex);
    }

    function proposeOwner(address newOwner, OwnerProposalType proposalType, uint256 _expiry)
        external
        onlyOwner
        returns (uint256 proposalIndex)
    {
        if (newOwner == address(0)) revert ZeroAddress();
        if (_expiry <= block.timestamp || _expiry > block.timestamp + 30 days) revert InvalidExpiry();

        if (proposalType == OwnerProposalType.Add) {
            if (isOwner[newOwner]) revert AlreadyOwner();
        } else {
            if (!isOwner[newOwner]) revert NotAnOwner();
        }

        proposalIndex = ownerProposals.length;
        ownerProposals.push(OwnerProposal({
            proposedOwner: newOwner,
            status: 0,
            proposalType: proposalType,
            confirmations: 0,
            rejections: 0,
            expiry: uint32(_expiry),
            createdAt: uint32(block.timestamp)
        }));

        emit OwnerProposed(proposalIndex, newOwner, proposalType);
    }

    function confirmOwnerProposal(uint256 proposalIndex) external onlyOwner validProposal(proposalIndex) {
        if (proposalVotes[proposalIndex][msg.sender] != 0) revert AlreadyVoted();
        
        proposalVotes[proposalIndex][msg.sender] = 1;
        ownerProposals[proposalIndex].confirmations++;

        emit OwnerProposalConfirmed(proposalIndex, msg.sender);

        if (ownerProposals[proposalIndex].confirmations >= getMajorityThreshold()) {
            _executeOwnerProposal(proposalIndex);
        }
    }

    function rejectOwnerProposal(uint256 proposalIndex) external onlyOwner validProposal(proposalIndex) {
        if (proposalVotes[proposalIndex][msg.sender] != 0) revert AlreadyVoted();
        
        proposalVotes[proposalIndex][msg.sender] = 2;
        ownerProposals[proposalIndex].rejections++;

        emit OwnerProposalRejected(proposalIndex, msg.sender);

        if (ownerProposals[proposalIndex].rejections >= getMajorityThreshold()) {
            ownerProposals[proposalIndex].status = 2;
            emit OwnerProposalCanceled(proposalIndex);
        }
    }

    function _executeOwnerProposal(uint256 proposalIndex) internal {
        OwnerProposal storage proposal = ownerProposals[proposalIndex];
        proposal.status = 1;

        if (proposal.proposalType == OwnerProposalType.Add) {
            if (isOwner[proposal.proposedOwner]) revert AlreadyOwner();
            owners.push(proposal.proposedOwner);
            isOwner[proposal.proposedOwner] = true;
            emit OwnerAdded(proposalIndex, proposal.proposedOwner);
        } else {
            if (!isOwner[proposal.proposedOwner]) revert NotAnOwner();
            if (owners.length <= 2) revert CannotRemoveLastOwner();

            for (uint256 i; i < owners.length; ++i) {
                if (owners[i] == proposal.proposedOwner) {
                    owners[i] = owners[owners.length - 1];
                    owners.pop();
                    break;
                }
            }
            isOwner[proposal.proposedOwner] = false;
            emit OwnerRemoved(proposalIndex, proposal.proposedOwner);
        }

        safeTeaFactory.updateWalletOwners(owners);
    }

    function markOwnerProposalExpired(uint256 proposalIndex) external {
        if (proposalIndex >= ownerProposals.length) revert ProposalNotExist();
        OwnerProposal storage proposal = ownerProposals[proposalIndex];
        if (proposal.status != 0) revert AlreadyExecuted();
        if (block.timestamp <= proposal.expiry) revert NotExpired();
        
        proposal.status = 2;
        emit OwnerProposalExpired(proposalIndex);
    }

    // View functions
    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    function getOwnerCount() external view returns (uint256) {
        return owners.length;
    }

    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }

    function getOwnerProposalCount() external view returns (uint256) {
        return ownerProposals.length;
    }

    function getTransaction(uint256 index) external view returns (
        address to, uint256 value, bytes memory data, bool executed, bool canceled,
        uint256 confirmations, uint256 rejections, uint256 expiry, uint256 createdAt
    ) {
        if (index >= transactions.length) revert TxNotExist();
        Transaction storage txn = transactions[index];
        return (
            txn.to, txn.value, txn.data, txn.status == 1, txn.status == 2,
            txn.confirmations, txn.rejections, txn.expiry, txn.createdAt
        );
    }

    function getOwnerProposal(uint256 index) external view returns (
        address proposedOwner, bool executed, bool canceled,
        uint256 confirmations, uint256 rejections, uint256 expiry, uint256 createdAt
    ) {
        if (index >= ownerProposals.length) revert ProposalNotExist();
        OwnerProposal storage proposal = ownerProposals[index];
        return (
            proposal.proposedOwner, proposal.status == 1, proposal.status == 2,
            proposal.confirmations, proposal.rejections, proposal.expiry, proposal.createdAt
        );
    }

    function isTransactionExpired(uint256 txIndex) external view returns (bool) {
        if (txIndex >= transactions.length) revert TxNotExist();
        return block.timestamp > transactions[txIndex].expiry;
    }

    function isOwnerProposalExpired(uint256 proposalIndex) external view returns (bool) {
        if (proposalIndex >= ownerProposals.length) revert ProposalNotExist();
        return block.timestamp > ownerProposals[proposalIndex].expiry;
    }

    function hasConfirmedTransaction(uint256 txIndex, address owner) external view returns (bool) {
        return txVotes[txIndex][owner] == 1;
    }

    function hasRejectedTransaction(uint256 txIndex, address owner) external view returns (bool) {
        return txVotes[txIndex][owner] == 2;
    }

    function hasConfirmedOwnerProposal(uint256 proposalIndex, address owner) external view returns (bool) {
        return proposalVotes[proposalIndex][owner] == 1;
    }

    function hasRejectedOwnerProposal(uint256 proposalIndex, address owner) external view returns (bool) {
        return proposalVotes[proposalIndex][owner] == 2;
    }
}