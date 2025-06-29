// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "./SafeTeaWallet.sol";

contract SafeTeaFactory {
    address[] public allWallets;
    mapping(address => address[]) public userWallets;
    mapping(address => bool) public isSafeTeaWallet;

    event WalletCreated(address indexed wallet, address[] owners);

    function createWallet(address[] memory owners) public returns (address walletAddress) {
        // Check for zero address in owners
        for (uint256 i = 0; i < owners.length; i++) {
            require(owners[i] != address(0), "Zero address");
        }

        // Check for duplicate owners using a more efficient method
        _validateNoDuplicates(owners);

        SafeTeaWallet wallet = new SafeTeaWallet(owners, address(this));
        walletAddress = address(wallet);

        // Update mappings
        isSafeTeaWallet[walletAddress] = true;
        allWallets.push(walletAddress);

        // Cache array length to save gas
        uint256 ownersLength = owners.length;
        for (uint256 i = 0; i < ownersLength; i++) {
            userWallets[owners[i]].push(walletAddress);
        }

        emit WalletCreated(walletAddress, owners);
        return walletAddress;
    }

    function getUserWallets(address user) public view returns (address[] memory) {
        return userWallets[user];
    }

    function updateWalletOwners(address[] memory newOwners) public {
        require(isSafeTeaWallet[msg.sender], "Only SafeTeaWallet");

        // Update the userWallets mapping
        for (uint256 i = 0; i < newOwners.length; i++) {
            userWallets[newOwners[i]].push(msg.sender);
        }
    }

    function getAllWallets() public view returns (address[] memory) {
        return allWallets;
    }

    function _validateNoDuplicates(address[] memory addresses) private pure {
        for (uint256 i = 0; i < addresses.length; i++) {
            for (uint256 j = i + 1; j < addresses.length; j++) {
                require(addresses[i] != addresses[j], "Duplicate owners");
            }
        }
    }
}
