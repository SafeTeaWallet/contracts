// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface ISafeTeaFactory {
    // Events
    event WalletCreated(address wallet, address[] owners);

    // Functions
    function allWallets(uint256 index) external view returns (address);
    function userWallets(address user, uint256 index) external view returns (address);

    function createWallet(address[] memory owners) external;
    function getUserWallets(address user) external view returns (address[] memory);
    function updateWalletOwners(address[] memory newOwners) external;
    function getAllWallets() external view returns (address[] memory);
}
