// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RegenStaker } from "src/regen/RegenStaker.sol";
import { Staker } from "staker/Staker.sol";
import { MockERC20Staking } from "test/mocks/MockERC20Staking.sol";
import { MockEarningPowerCalculator } from "test/mocks/MockEarningPowerCalculator.sol";
import { TokenizedAllocationMechanism } from "src/mechanisms/TokenizedAllocationMechanism.sol";
import { OctantQFMechanism } from "src/mechanisms/mechanism/OctantQFMechanism.sol";
import { AllocationConfig } from "src/mechanisms/BaseAllocationMechanism.sol";
import { Whitelist } from "src/utils/Whitelist.sol";
import { IWhitelist } from "src/utils/IWhitelist.sol";

/// @title RegenStakerBase Voting Power Assignment Test
/// @notice Proves that voting power in allocation mechanisms is assigned to the contributor (msg.sender),
///         not necessarily the deposit owner. This is INTENDED BEHAVIOR per REG-019.
/// @dev This test definitively shows:
///      - When owner contributes: owner gets voting power
///      - When claimer contributes: claimer gets voting power (NOT the owner)
///      This demonstrates the trust model where claimers can direct voting power using owner's rewards
contract RegenStakerBaseVotingPowerAssignmentTest is Test {
    RegenStaker public regenStaker;
    MockERC20Staking public token;
    MockEarningPowerCalculator public earningPowerCalculator;
    OctantQFMechanism public allocationMechanism;
    Whitelist public stakerWhitelist;
    Whitelist public contributionWhitelist;
    Whitelist public allocationWhitelist;

    address public admin = makeAddr("admin");
    address public owner;
    uint256 private ownerPk;
    address public claimer;
    uint256 private claimerPk;
    address public delegatee = makeAddr("delegatee");

    uint256 public constant STAKE_AMOUNT = 100e18;
    uint256 public constant REWARD_AMOUNT = 1000e18;
    uint128 public constant REWARD_DURATION = 30 days;
    uint256 public constant CONTRIBUTION_AMOUNT = 10e18;

    Staker.DepositIdentifier public depositId;

    function setUp() public {
        // Create addresses with private keys for signature generation
        (owner, ownerPk) = makeAddrAndKey("owner");
        (claimer, claimerPk) = makeAddrAndKey("claimer");

        // Deploy infrastructure
        token = new MockERC20Staking(18);
        earningPowerCalculator = new MockEarningPowerCalculator();

        // Deploy real allocation mechanism
        TokenizedAllocationMechanism impl = new TokenizedAllocationMechanism();
        AllocationConfig memory cfg = AllocationConfig({
            asset: IERC20(address(token)),
            name: "TestAlloc",
            symbol: "TA",
            votingDelay: 1,
            votingPeriod: 30 days,
            quorumShares: 1,
            timelockDelay: 1,
            gracePeriod: 100,
            owner: admin
        });
        allocationMechanism = new OctantQFMechanism(address(impl), cfg, 1, 1, address(0));

        // Deploy and configure whitelists
        vm.startPrank(admin);
        stakerWhitelist = new Whitelist();
        contributionWhitelist = new Whitelist();
        allocationWhitelist = new Whitelist();

        // Add both owner and claimer to necessary whitelists
        stakerWhitelist.addToWhitelist(owner);
        stakerWhitelist.addToWhitelist(claimer);
        contributionWhitelist.addToWhitelist(owner);
        contributionWhitelist.addToWhitelist(claimer);
        allocationWhitelist.addToWhitelist(address(allocationMechanism));
        vm.stopPrank();

        // Deploy RegenStaker with same token for stake/reward
        vm.prank(admin);
        regenStaker = new RegenStaker(
            IERC20(address(token)), // rewardsToken
            token, // stakeToken
            earningPowerCalculator,
            0, // maxBumpTip
            admin,
            REWARD_DURATION,
            0, // maxClaimFee
            1e18, // minimumStakeAmount
            IWhitelist(address(stakerWhitelist)),
            IWhitelist(address(contributionWhitelist)),
            IWhitelist(address(allocationWhitelist))
        );

        // Fund and create deposit with claimer designation
        token.mint(owner, STAKE_AMOUNT);
        token.mint(address(regenStaker), REWARD_AMOUNT);

        vm.startPrank(owner);
        token.approve(address(regenStaker), STAKE_AMOUNT);
        depositId = regenStaker.stake(STAKE_AMOUNT, delegatee, claimer);
        vm.stopPrank();

        // Setup rewards
        vm.startPrank(admin);
        regenStaker.setRewardNotifier(admin, true);
        regenStaker.notifyRewardAmount(REWARD_AMOUNT);
        vm.stopPrank();

        // Accumulate rewards
        vm.warp(block.timestamp + REWARD_DURATION / 4);
    }

    /// @notice Test that when OWNER contributes, OWNER gets voting power
    /// @dev This is the expected base case - contributor gets voting power
    function testVotingPower_OwnerContribute_OwnerGetsVotingPower() public {
        // Create signature for owner to contribute
        bytes32 domainSeparator = TokenizedAllocationMechanism(address(allocationMechanism)).DOMAIN_SEPARATOR();
        uint256 nonce = TokenizedAllocationMechanism(address(allocationMechanism)).nonces(owner);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 typeHash = keccak256(
            bytes("Signup(address user,address payer,uint256 deposit,uint256 nonce,uint256 deadline)")
        );
        bytes32 structHash = keccak256(
            abi.encode(typeHash, owner, address(regenStaker), CONTRIBUTION_AMOUNT, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);

        // Owner contributes their own deposit's rewards
        vm.prank(owner);
        uint256 contributed = regenStaker.contribute(
            depositId,
            address(allocationMechanism),
            CONTRIBUTION_AMOUNT,
            deadline,
            v,
            r,
            s
        );

        // Verify contribution succeeded
        assertEq(contributed, CONTRIBUTION_AMOUNT, "Contribution amount mismatch");

        // CRITICAL ASSERTION: Owner gets the voting power
        uint256 ownerVotingPower = TokenizedAllocationMechanism(address(allocationMechanism)).getRemainingVotingPower(
            owner
        );
        assertEq(ownerVotingPower, CONTRIBUTION_AMOUNT, "Owner should have voting power equal to contribution");

        // CRITICAL ASSERTION: Claimer has NO voting power
        uint256 claimerVotingPower = TokenizedAllocationMechanism(address(allocationMechanism)).getRemainingVotingPower(
            claimer
        );
        assertEq(claimerVotingPower, 0, "Claimer should have no voting power when owner contributes");
    }

    /// @notice Test that when CLAIMER contributes, CLAIMER gets voting power (NOT owner)
    /// @dev This proves the intended behavior where voting power follows the contributor
    function testVotingPower_ClaimerContribute_ClaimerGetsVotingPower() public {
        // Create signature for claimer to contribute
        bytes32 domainSeparator = TokenizedAllocationMechanism(address(allocationMechanism)).DOMAIN_SEPARATOR();
        uint256 nonce = TokenizedAllocationMechanism(address(allocationMechanism)).nonces(claimer);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 typeHash = keccak256(
            bytes("Signup(address user,address payer,uint256 deposit,uint256 nonce,uint256 deadline)")
        );
        bytes32 structHash = keccak256(
            abi.encode(typeHash, claimer, address(regenStaker), CONTRIBUTION_AMOUNT, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimerPk, digest);

        // Claimer contributes owner's deposit's rewards
        vm.prank(claimer);
        uint256 contributed = regenStaker.contribute(
            depositId,
            address(allocationMechanism),
            CONTRIBUTION_AMOUNT,
            deadline,
            v,
            r,
            s
        );

        // Verify contribution succeeded
        assertEq(contributed, CONTRIBUTION_AMOUNT, "Contribution amount mismatch");

        // CRITICAL ASSERTION: Claimer gets the voting power
        uint256 claimerVotingPower = TokenizedAllocationMechanism(address(allocationMechanism)).getRemainingVotingPower(
            claimer
        );
        assertEq(claimerVotingPower, CONTRIBUTION_AMOUNT, "Claimer should have voting power equal to contribution");

        // CRITICAL ASSERTION: Owner has NO voting power (despite rewards coming from their deposit!)
        uint256 ownerVotingPower = TokenizedAllocationMechanism(address(allocationMechanism)).getRemainingVotingPower(
            owner
        );
        assertEq(ownerVotingPower, 0, "Owner should have no voting power when claimer contributes");
    }

    /// @notice Test that both owner and claimer can contribute separately and each gets their own voting power
    /// @dev This proves voting power accumulates per contributor, regardless of reward source
    function testVotingPower_BothContribute_EachGetsOwnVotingPower() public {
        uint256 halfContribution = CONTRIBUTION_AMOUNT / 2;

        // First: Owner contributes half
        _contributeAsOwner(halfContribution);

        // Second: Claimer contributes the other half
        _contributeAsClaimer(halfContribution);

        // CRITICAL ASSERTIONS: Each has voting power matching their own contribution
        uint256 ownerVotingPower = TokenizedAllocationMechanism(address(allocationMechanism)).getRemainingVotingPower(
            owner
        );
        uint256 claimerVotingPower = TokenizedAllocationMechanism(address(allocationMechanism)).getRemainingVotingPower(
            claimer
        );

        assertEq(ownerVotingPower, halfContribution, "Owner voting power should match their contribution");
        assertEq(claimerVotingPower, halfContribution, "Claimer voting power should match their contribution");

        // Both used the same deposit's rewards, but each got their own voting power
        assertEq(
            ownerVotingPower + claimerVotingPower,
            CONTRIBUTION_AMOUNT,
            "Total voting power should equal total contributions"
        );
    }

    // Helper function to reduce stack depth
    function _contributeAsOwner(uint256 amount) internal {
        bytes32 domainSeparator = TokenizedAllocationMechanism(address(allocationMechanism)).DOMAIN_SEPARATOR();
        uint256 nonce = TokenizedAllocationMechanism(address(allocationMechanism)).nonces(owner);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 typeHash = keccak256(
            bytes("Signup(address user,address payer,uint256 deposit,uint256 nonce,uint256 deadline)")
        );
        bytes32 structHash = keccak256(abi.encode(typeHash, owner, address(regenStaker), amount, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);

        vm.prank(owner);
        uint256 contributed = regenStaker.contribute(
            depositId,
            address(allocationMechanism),
            amount,
            deadline,
            v,
            r,
            s
        );
        assertEq(contributed, amount, "Owner contribution mismatch");
    }

    // Helper function to reduce stack depth
    function _contributeAsClaimer(uint256 amount) internal {
        bytes32 domainSeparator = TokenizedAllocationMechanism(address(allocationMechanism)).DOMAIN_SEPARATOR();
        uint256 nonce = TokenizedAllocationMechanism(address(allocationMechanism)).nonces(claimer);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 typeHash = keccak256(
            bytes("Signup(address user,address payer,uint256 deposit,uint256 nonce,uint256 deadline)")
        );
        bytes32 structHash = keccak256(abi.encode(typeHash, claimer, address(regenStaker), amount, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimerPk, digest);

        vm.prank(claimer);
        uint256 contributed = regenStaker.contribute(
            depositId,
            address(allocationMechanism),
            amount,
            deadline,
            v,
            r,
            s
        );
        assertEq(contributed, amount, "Claimer contribution mismatch");
    }

    /// @notice Test that attempting to contribute without proper signature fails
    /// @dev Ensures voting power assignment requires valid authorization
    function testVotingPower_WrongSignature_Reverts() public {
        // Create signature for owner but try to use it as claimer
        bytes32 domainSeparator = TokenizedAllocationMechanism(address(allocationMechanism)).DOMAIN_SEPARATOR();
        uint256 nonce = TokenizedAllocationMechanism(address(allocationMechanism)).nonces(owner);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 typeHash = keccak256(
            bytes("Signup(address user,address payer,uint256 deposit,uint256 nonce,uint256 deadline)")
        );
        // Sign for owner as user
        bytes32 structHash = keccak256(
            abi.encode(typeHash, owner, address(regenStaker), CONTRIBUTION_AMOUNT, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);

        // Claimer tries to contribute but passes owner's signature - should fail
        vm.prank(claimer);
        vm.expectRevert(); // Will revert due to signature mismatch
        regenStaker.contribute(depositId, address(allocationMechanism), CONTRIBUTION_AMOUNT, deadline, v, r, s);

        // Verify no voting power was assigned
        uint256 claimerVotingPower = TokenizedAllocationMechanism(address(allocationMechanism)).getRemainingVotingPower(
            claimer
        );
        assertEq(claimerVotingPower, 0, "Claimer should have no voting power after failed contribution");
    }
}
