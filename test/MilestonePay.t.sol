// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MilestonePay, IERC20} from "../src/MilestonePay.sol";
import {MockUSDC} from "./MockUSDC.sol";

contract MilestonePayTest is Test {
    MockUSDC usdc;
    MilestonePay pay;
    address client = makeAddr("client");
    address freelancer = makeAddr("freelancer");
    address arbiter = makeAddr("arbiter");
    address rando = makeAddr("rando");

    uint64 constant REVIEW = 3 days;

    function setUp() public {
        usdc = new MockUSDC();
        pay = new MilestonePay(IERC20(address(usdc)));
        usdc.mint(client, 1_000e6);
        vm.prank(client);
        usdc.approve(address(pay), type(uint256).max);
    }

    function _amounts() internal pure returns (uint128[] memory a) {
        a = new uint128[](3);
        a[0] = 100e6;
        a[1] = 200e6;
        a[2] = 300e6;
    }

    function _create() internal returns (uint256 id) {
        vm.prank(client);
        id = pay.createJob(freelancer, arbiter, _amounts(), REVIEW, uint64(block.timestamp + 30 days), "Landing page");
    }

    function test_createPullsFunds() public {
        uint256 id = _create();
        assertEq(id, 1);
        assertEq(usdc.balanceOf(address(pay)), 600e6);
        assertEq(usdc.balanceOf(client), 400e6);
        assertEq(pay.milestoneCount(id), 3);
        assertEq(uint8(pay.milestone(id, 0).status), uint8(MilestonePay.Status.Funded));
    }

    function test_createRejectsBadParams() public {
        uint128[] memory a = _amounts();
        vm.startPrank(client);
        vm.expectRevert(MilestonePay.BadParams.selector);
        pay.createJob(address(0), arbiter, a, REVIEW, uint64(block.timestamp + 1 days), "x");
        vm.expectRevert(MilestonePay.BadParams.selector);
        pay.createJob(client, arbiter, a, REVIEW, uint64(block.timestamp + 1 days), "x");
        vm.expectRevert(MilestonePay.BadParams.selector);
        pay.createJob(freelancer, freelancer, a, REVIEW, uint64(block.timestamp + 1 days), "x");
        vm.expectRevert(MilestonePay.BadParams.selector);
        pay.createJob(freelancer, arbiter, new uint128[](0), REVIEW, uint64(block.timestamp + 1 days), "x");
        vm.expectRevert(MilestonePay.BadParams.selector);
        pay.createJob(freelancer, arbiter, a, 10 minutes, uint64(block.timestamp + 1 days), "x");
        vm.expectRevert(MilestonePay.BadParams.selector);
        pay.createJob(freelancer, arbiter, a, REVIEW, uint64(block.timestamp), "x");
        a[1] = 0;
        vm.expectRevert(MilestonePay.BadParams.selector);
        pay.createJob(freelancer, arbiter, a, REVIEW, uint64(block.timestamp + 1 days), "x");
        vm.stopPrank();
    }

    function test_happyPath_submitApprove() public {
        uint256 id = _create();
        vm.prank(freelancer);
        pay.submit(id, 0, keccak256("v1"));
        vm.prank(client);
        pay.approve(id, 0);
        assertEq(usdc.balanceOf(freelancer), 100e6);
        assertEq(uint8(pay.milestone(id, 0).status), uint8(MilestonePay.Status.Paid));
        // cannot pay twice
        vm.prank(client);
        vm.expectRevert(MilestonePay.BadStatus.selector);
        pay.approve(id, 0);
    }

    function test_timeoutClaim() public {
        uint256 id = _create();
        vm.prank(freelancer);
        pay.submit(id, 1, keccak256("v1"));
        vm.prank(freelancer);
        vm.expectRevert(MilestonePay.TooEarly.selector);
        pay.claimAfterTimeout(id, 1);
        vm.warp(block.timestamp + REVIEW);
        vm.prank(freelancer);
        pay.claimAfterTimeout(id, 1);
        assertEq(usdc.balanceOf(freelancer), 200e6);
    }

    function test_disputeBlocksTimeoutAndArbiterSplits() public {
        uint256 id = _create();
        vm.prank(freelancer);
        pay.submit(id, 2, keccak256("v1"));
        vm.prank(client);
        pay.dispute(id, 2);
        vm.warp(block.timestamp + REVIEW + 1);
        vm.prank(freelancer);
        vm.expectRevert(MilestonePay.BadStatus.selector);
        pay.claimAfterTimeout(id, 2);
        vm.prank(rando);
        vm.expectRevert(MilestonePay.NotArbiter.selector);
        pay.resolve(id, 2, 5000);
        vm.prank(arbiter);
        pay.resolve(id, 2, 7000);
        assertEq(usdc.balanceOf(freelancer), 210e6);
        assertEq(usdc.balanceOf(client), 400e6 + 90e6);
    }

    function test_disputeTooLate() public {
        uint256 id = _create();
        vm.prank(freelancer);
        pay.submit(id, 0, keccak256("v1"));
        vm.warp(block.timestamp + REVIEW);
        vm.prank(client);
        vm.expectRevert(MilestonePay.TooLate.selector);
        pay.dispute(id, 0);
    }

    function test_reopenThenResubmit() public {
        uint256 id = _create();
        vm.prank(freelancer);
        pay.submit(id, 0, keccak256("v1"));
        vm.prank(client);
        pay.dispute(id, 0);
        vm.prank(client);
        pay.reopen(id, 0);
        vm.prank(freelancer);
        pay.submit(id, 0, keccak256("v2"));
        assertEq(pay.milestone(id, 0).deliverable, keccak256("v2"));
    }

    function test_refundUnsubmittedOnlyAfterDeadline() public {
        uint256 id = _create();
        vm.prank(client);
        vm.expectRevert(MilestonePay.TooEarly.selector);
        pay.refundUnsubmitted(id, 0);
        vm.prank(freelancer);
        pay.submit(id, 1, keccak256("v1"));
        vm.warp(block.timestamp + 31 days);
        vm.startPrank(client);
        pay.refundUnsubmitted(id, 0);
        vm.expectRevert(MilestonePay.BadStatus.selector);
        pay.refundUnsubmitted(id, 1); // submitted work cannot be clawed back
        vm.stopPrank();
        assertEq(usdc.balanceOf(client), 500e6);
    }

    function test_releaseToClient() public {
        uint256 id = _create();
        vm.prank(freelancer);
        pay.releaseToClient(id, 0);
        assertEq(usdc.balanceOf(client), 500e6);
    }

    function test_accessControl() public {
        uint256 id = _create();
        vm.startPrank(rando);
        vm.expectRevert(MilestonePay.NotFreelancer.selector);
        pay.submit(id, 0, bytes32(0));
        vm.expectRevert(MilestonePay.NotClient.selector);
        pay.approve(id, 0);
        vm.expectRevert(MilestonePay.NotClient.selector);
        pay.dispute(id, 0);
        vm.expectRevert(MilestonePay.NotFreelancer.selector);
        pay.releaseToClient(id, 0);
        vm.expectRevert(MilestonePay.NotClient.selector);
        pay.refundUnsubmitted(id, 0);
        vm.stopPrank();
        vm.prank(client);
        vm.expectRevert(MilestonePay.BadParams.selector);
        pay.approve(id, 9);
    }

    function test_noArbiterMeansNoResolve() public {
        vm.prank(client);
        uint256 id = pay.createJob(freelancer, address(0), _amounts(), REVIEW, uint64(block.timestamp + 1 days), "x");
        vm.prank(freelancer);
        pay.submit(id, 0, bytes32(0));
        vm.prank(client);
        pay.dispute(id, 0);
        vm.prank(address(0));
        vm.expectRevert(MilestonePay.NotArbiter.selector);
        pay.resolve(id, 0, 10_000);
        // parties can still settle: client approves or freelancer releases
        vm.prank(freelancer);
        pay.releaseToClient(id, 0);
    }

    function test_blocklistedFreelancerPayoutReverts() public {
        uint256 id = _create();
        vm.prank(freelancer);
        pay.submit(id, 0, bytes32(0));
        usdc.setBlocked(freelancer, true);
        vm.prank(client);
        vm.expectRevert(MilestonePay.TransferFailed.selector);
        pay.approve(id, 0);
        // funds stay safe in escrow, status unchanged
        assertEq(uint8(pay.milestone(id, 0).status), uint8(MilestonePay.Status.Submitted));
        assertEq(usdc.balanceOf(address(pay)), 600e6);
    }

    /// Escrow is always fully backed: balance == sum of unsettled milestones.
    function testFuzz_solvency(uint128 a0, uint128 a1, uint16 bps, uint8 path) public {
        a0 = uint128(bound(a0, 1, 400e6));
        a1 = uint128(bound(a1, 1, 400e6));
        bps = uint16(bound(bps, 0, 10_000));
        uint128[] memory a = new uint128[](2);
        a[0] = a0;
        a[1] = a1;
        vm.prank(client);
        uint256 id = pay.createJob(freelancer, arbiter, a, REVIEW, uint64(block.timestamp + 10 days), "f");
        vm.prank(freelancer);
        pay.submit(id, 0, bytes32(0));
        if (path % 3 == 0) {
            vm.prank(client);
            pay.approve(id, 0);
        } else if (path % 3 == 1) {
            vm.prank(client);
            pay.dispute(id, 0);
            vm.prank(arbiter);
            pay.resolve(id, 0, bps);
        } else {
            vm.warp(block.timestamp + REVIEW);
            vm.prank(freelancer);
            pay.claimAfterTimeout(id, 0);
        }
        assertEq(usdc.balanceOf(address(pay)), a1);
        assertEq(usdc.balanceOf(client) + usdc.balanceOf(freelancer) + usdc.balanceOf(address(pay)), 1_000e6);
    }
}
