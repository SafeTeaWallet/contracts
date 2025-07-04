SafeTea Smart Contracts
=======================

SafeTea is a minimal, secure, and gas-efficient multi-signature wallet built with Solidity and tested using Foundry. It allows multiple owners to manage ETH and ERC20 assets with on-chain proposal and confirmation workflows.

Features
--------

*   Multi-owner governance
*   Proposal system for ETH and ERC20 transfers
*   Owner addition/removal with confirmations
*   Proposal expiration for time-based safety
*   Gas-optimized Solidity code

Tech Stack
----------

*   Solidity ^0.8.0
*   [Foundry](https://book.getfoundry.sh/) for testing
*   Minimal dependencies (no full OpenZeppelin required)

Setup
-----

    git clone https://github.com/yourusername/safetea-wallet.git
    cd safetea-wallet
    forge install
    forge build
    forge test

Contracts
---------

*   `SafeTea.sol` – Core multisig wallet logic
*   `ISafeTeaFactory.sol` – Interface for wallet factory
*   `SafeTeaFactory.sol` – Factory to deploy new SafeTea wallets

Testing
-------

    forge test --coverage

Includes unit tests for:

*   ETH transfers
*   ERC20 token transfers
*   Owner proposals and confirmations
*   Execution and expiration handling

Security Considerations
-----------------------

*   Reentrancy-safe proposal execution
*   On-chain validation and access control
*   Transparent events for every proposal

License
-------

MIT © 2025 SafeTea Team