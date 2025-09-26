// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { RegenStakerWithoutDelegateSurrogateVotes } from "src/regen/RegenStakerWithoutDelegateSurrogateVotes.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { RegenStakerBase } from "src/regen/RegenStakerBase.sol";
import { Staker } from "staker/Staker.sol";

contract RegenSameTokenHandler is Test {
    RegenStakerWithoutDelegateSurrogateVotes public staker;
    MockERC20 public token;
    address public admin;
    address public notifier;
    address public user;

    constructor(
        RegenStakerWithoutDelegateSurrogateVotes _staker,
        MockERC20 _token,
        address _admin,
        address _notifier,
        address _user
    ) {
        staker = _staker;
        token = _token;
        admin = _admin;
        notifier = _notifier;
        user = _user;
    }

    function stake(uint256 amount) external {
        amount = bound(amount, 1e9, 1_000_000e18);
        token.mint(user, amount);
        vm.startPrank(user);
        token.approve(address(staker), amount);
        staker.stake(amount, user);
        vm.stopPrank();
    }

    function compound(uint256 depositId) external {
        vm.warp(block.timestamp + ((depositId % 7) + 1) * 1 days);
        vm.prank(user);
        staker.compoundRewards(Staker.DepositIdentifier.wrap(depositId % 4));
    }

    function notify(uint256 rewardAmt, uint256 transferAmt) external {
        rewardAmt = bound(rewardAmt, 1, 1_000_000e18);
        transferAmt = bound(transferAmt, 0, rewardAmt);
        token.mint(notifier, transferAmt);
        vm.startPrank(notifier);
        if (transferAmt > 0) token.transfer(address(staker), transferAmt);
        if (transferAmt >= rewardAmt) {
            staker.notifyRewardAmount(rewardAmt);
        } else {
            vm.expectRevert(RegenStakerBase.InsufficientRewardBalance.selector);
            staker.notifyRewardAmount(rewardAmt);
        }
        vm.stopPrank();
    }
}
