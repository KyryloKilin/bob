// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

using stdStorage for StdStorage;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {stdStorage, StdStorage, Test, console} from "forge-std/Test.sol";
import {Bridge} from "../src/bridge.sol";
import {Utilities} from "./utils/Utilities.sol";

contract BridgeTest is Bridge, Test {
    Utilities internal utils;
    address payable[] internal users;
    address internal alice;
    address internal bob;

    constructor() Bridge(2) {}

    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);

        alice = users[0];
        vm.label(alice, "Alice");
        bob = users[1];
        vm.label(bob, "Bob");
    }

    function testMint() public {
        uint256 _amount = 1000;

        vm.deal(alice, _amount);
        vm.startPrank(alice);
        uint256 balanceBefore = address(this).balance;
        (bool _success, ) = address(this).call{value: _amount}(
            abi.encodeWithSignature("mintZbtc()", alice)
        );
        assertTrue(_success, "deposited payment.");

        // zbtc minted
        assertEqDecimal(balanceOf(alice), _amount / 5 / 2, decimals());
        // col has been transferred to contract
        assertEqDecimal(
            address(this).balance,
            balanceBefore + _amount,
            decimals()
        );
    }

    function testLiquidate() public {
        uint256 _amount = 1000;

        vm.deal(alice, _amount);
        vm.startPrank(alice);
        (bool _success, ) = address(this).call{value: _amount}(
            abi.encodeWithSignature("mintZbtc()", alice)
        );
        assertTrue(_success);

        // liquidate 25% of what was minted
        assertEqDecimal(balanceOf(alice), 100, decimals());
        this.liquidate(25);
        assertEqDecimal(balanceOf(alice), 75, decimals());
        assertEqDecimal(address(alice).balance, btcToCol(25), decimals());
    }

    function testWithdraw() public {
        uint256 _amount = 1000;

        vm.deal(alice, _amount);
        vm.startPrank(alice);
        (bool _success, ) = address(this).call{value: _amount}(
            abi.encodeWithSignature("mintZbtc()", alice)
        );
        assertTrue(_success);

        assertEq(collateralThreshold, 2);
        stdstore
            .target(address(this))
            .sig(this.collateralThreshold.selector)
            .checked_write(1);
        assertEq(collateralThreshold, 1); // sanity check that writing to storage worked

        uint256 lockedBefore = suppliedCollateral[alice];
        this.withdrawFreeCol();
        assertEq(suppliedCollateral[alice], lockedBefore / 2);
    }

    function testRedeem() public {
        uint256 amountCol = 1000;

        uint256 zbtcAmount = 100;
        uint256 btcAmount = 50;

        vm.deal(alice, amountCol);
        vm.startPrank(alice);
        (bool _success, ) = address(this).call{value: amountCol}(
            abi.encodeWithSignature("mintZbtc()", alice)
        );
        assertTrue(_success, "deposited payment.");

        BitcoinAddress memory btcAddress = BitcoinAddress({bitcoinAddress: 1});
        this.requestRedeem(zbtcAmount, btcAmount, btcAddress);

        // RedeemRequest memory redeemRequest = redeemRequests(0);
        assertEq(redeemRequests[0].amountZbtc, zbtcAmount);
        assertEq(redeemRequests[0].amountBtc, btcAmount);
        assertTrue(redeemRequests[0].open);

        vm.startPrank(bob);
        this.acceptRedeem(0);
        assertFalse(redeemRequests[0].open);

        TransactionProof memory proof = TransactionProof({dummy: 1});
        assertEqDecimal(balanceOf(bob), 0, decimals());
        this.executeRedeem(0, proof);
        assertEqDecimal(balanceOf(bob), zbtcAmount, decimals());
    }
}
