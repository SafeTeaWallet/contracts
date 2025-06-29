// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/SafeTeaWallet.sol";
import "../src/Mock/MockERC20.sol";

contract SafeTeaERC20Test is Test {
    SafeTeaWallet safeTea;
    MockERC20 token;

    address alice = address(0x1);
    address bob = address(0x2);
    address carol = address(0x3);
    address recipient = address(0xdead);

    address[] owners = new address[](3);

    function setUp() public {
        owners[0] = alice;
        owners[1] = bob;
        owners[2] = carol;

        safeTea = new SafeTeaWallet(owners, address(this));
        token = new MockERC20();

        // Fund wallet with tokens
        token.transfer(address(safeTea), 1000 ether);
    }

    function testSendERC20Token() public {
        uint256 amount = 100 ether;

        // Prepare calldata for ERC20 transfer: transfer(address to, uint amount)
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, amount);

        // Submit tx (by Alice)
        vm.prank(alice);
        uint256 expiry = block.timestamp + 1 days;
        safeTea.submitTransaction(address(token), 0, data, expiry);

        // Confirm by Alice and Bob
        vm.prank(alice);
        safeTea.confirmTransaction(0);

        vm.prank(bob);
        safeTea.confirmTransaction(0);

        // Check token balance
        uint256 balance = token.balanceOf(recipient);
        assertEq(balance, amount);
    }
}
