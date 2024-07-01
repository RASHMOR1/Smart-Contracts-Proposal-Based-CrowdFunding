// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MainContract} from "../src/MainContract.sol";
import {MockUsdtContract} from "./mock/MockUsdtContract.sol";
import {IERC20} from "../src/MainContract.sol";

contract TestMainContract is Test {
    MainContract mainContract;
    address companyAddress;
    address company2Address;
    string proposal1URI;
    string proposal2URI;
    address user1;
    address user2;
    uint256 goal;
    address usdtTokenOwner;
    address mainContractOwner;

    MockUsdtContract usdtAddress;

    error MainContract__NotAllowedToPerformThisAction();
    error MainContract__ProposalIsInTheWrongStatus();
    error MainContract__ProposalIsOutdated();
    error MainContract__NotEnoughCommissionAccumulated();
    

    modifier createdProposals() {
        vm.startPrank(user1);
        mainContract.createProposal(companyAddress, proposal1URI);
        vm.stopPrank();

        vm.startPrank(user2);
        mainContract.createProposal(company2Address, proposal2URI);
        vm.stopPrank();

        _;
    }

    modifier proposalsAcceptedAndRejected() {
        vm.startPrank(companyAddress);
        mainContract.companyMakeDecision(1, MainContract.Decision.Rejected, goal, block.timestamp + 1000);
        vm.stopPrank();
        vm.startPrank(company2Address);
        mainContract.companyMakeDecision(2, MainContract.Decision.Accepted, goal, block.timestamp + 1000);
        vm.stopPrank();
        _;
    }

    modifier proposalFunded() {
        vm.startPrank(user2);
        mainContract.fundProposal(2, 100 * 10 ** usdtAddress.decimals());
        vm.stopPrank();
        _;
    }

    modifier accumulateCommission() {
        vm.startPrank(user1);
        for (uint256 i = 0; i < 40; i++) {
            mainContract.createProposal(companyAddress, proposal1URI);
        }
        vm.stopPrank();
        _;
    }

    function setUp() public {
        usdtTokenOwner = makeAddr("usdtTokenOwner");
        vm.deal(usdtTokenOwner, 10 ether);
        usdtAddress = new MockUsdtContract(10000000000 * 10 ** 18, usdtTokenOwner);
        companyAddress = makeAddr("company");
        vm.deal(companyAddress, 10 ether);
        company2Address = makeAddr("company2");
        vm.deal(company2Address, 10 ether);
        user1 = makeAddr("user1");
        vm.deal(user1, 10 ether);
        user2 = makeAddr("user2");
        vm.deal(user2, 10 ether);
        mainContractOwner = makeAddr("mainContractOwner");
        vm.deal(mainContractOwner, 10 ether);
        proposal1URI = "ksjdnfvdkjfvndkjfvndkj";
        proposal2URI = "djvnelceormkoecowec";
        goal = 100000;
        vm.startPrank(mainContractOwner);
        mainContract = new MainContract(address(usdtAddress));
        vm.stopPrank();
        vm.startPrank(usdtTokenOwner);
        usdtAddress.transfer(address(mainContract), 100 * 10 ** usdtAddress.decimals());
        usdtAddress.transfer(user1, 100000 * 10 ** usdtAddress.decimals());
        usdtAddress.transfer(user2, 1000 * 10 ** usdtAddress.decimals());
        usdtAddress.transfer(company2Address, 1000 * 10 ** usdtAddress.decimals());
        vm.stopPrank();
        vm.startPrank(user1);
        usdtAddress.approve(address(mainContract), 500 * 10 ** usdtAddress.decimals());
        vm.stopPrank();
        vm.startPrank(user2);
        usdtAddress.approve(address(mainContract), 500 * 10 ** usdtAddress.decimals());
        vm.stopPrank();
        vm.startPrank(company2Address);
        usdtAddress.approve(address(mainContract), 500 * 10 ** usdtAddress.decimals());
        vm.stopPrank();
        vm.startPrank(usdtTokenOwner);
        usdtAddress.approve(address(mainContract), 500000 * 10 ** usdtAddress.decimals());
        vm.stopPrank();
    }

    function test__InitializedCorrectly() public view {
        assert(mainContract.currentProposalId() == 1);
        assert(mainContract.proposalIdToDecisionStatus(1) == MainContract.Decision.Pending);
    }

    function test__ProposalCreatedCorrectly() public createdProposals {
        assert(mainContract.proposalIdToDecisionStatus(0) == MainContract.Decision.Pending);
        assert(mainContract.lastProposalSerialNumber(companyAddress) == 1);      
        assert(mainContract.returnSerialNumberOfTheProposalId(companyAddress, 0) == 1); 
        assert(keccak256(bytes(mainContract.proposalIdToURI(1))) == keccak256(bytes(proposal1URI)));
        assert(mainContract.proposalIdToCompanyAddress(1) == companyAddress); 
        assert(mainContract.proposalIdToDecisionStatus(1) == MainContract.Decision.Pending);
        assert(mainContract.lastProposalSerialNumber(company2Address) == 2);
        assert(mainContract.returnSerialNumberOfTheProposalId(company2Address, 0) == 2);
        assert(keccak256(bytes(mainContract.proposalIdToURI(2))) == keccak256(bytes(proposal2URI)));
        assert(mainContract.proposalIdToCompanyAddress(2) == company2Address);
        assert(mainContract.currentProposalId() == 3);
        assert(usdtAddress.balanceOf(address(mainContract)) == 120 * 10 ** usdtAddress.decimals());
    }

    function test__CompanyMakeDecision() public createdProposals proposalsAcceptedAndRejected {
        vm.startPrank(user1);
        vm.expectRevert(MainContract__NotAllowedToPerformThisAction.selector);
        mainContract.companyMakeDecision(1, MainContract.Decision.Rejected, goal, block.timestamp + 1000);
        vm.stopPrank();
        vm.startPrank(companyAddress);
        vm.expectRevert(MainContract__ProposalIsInTheWrongStatus.selector);
        mainContract.companyMakeDecision(1, MainContract.Decision.Rejected, goal, block.timestamp + 1000);
        vm.stopPrank();


        assert(mainContract.proposalIdToDecisionStatus(1) == MainContract.Decision.Rejected);
        assert(mainContract.proposalIdToDecisionStatus(2) == MainContract.Decision.Accepted);
        assert(mainContract.proposalIdToFundingGoal(1) == goal);
        assert(mainContract.proposalIdToDeadline(1) == block.timestamp + 1000);
        assert(mainContract.proposalIdToDeadline(2) == block.timestamp + 1000);
    }

    function test__FundProposal() public createdProposals proposalsAcceptedAndRejected proposalFunded {
        vm.startPrank(user1);
        vm.expectRevert(MainContract__ProposalIsInTheWrongStatus.selector);
        mainContract.fundProposal(1, 100);
        vm.stopPrank();

        vm.warp(block.timestamp + 1000000);
        vm.startPrank(company2Address);
        vm.expectRevert(MainContract__ProposalIsOutdated.selector);
        mainContract.fundProposal(2, 100);
        vm.stopPrank();
        uint256 totalFundedAmount = uint256(vm.load(address(mainContract), bytes32(uint256((2)))));
        assert(usdtAddress.balanceOf(address(mainContract)) == 220 * 10 ** usdtAddress.decimals());
        assert(mainContract.proposalIdToCurrentFunding(2) == 100 * 10 ** usdtAddress.decimals());
        assert(mainContract.returnAmountFundedOfTheAddress(2, user2) == 100 * 10 ** usdtAddress.decimals());
        console.log("totalFundedAmount:", totalFundedAmount);
        assert(totalFundedAmount == 100 * 10 ** usdtAddress.decimals());

    }

    function test__WithdrawCommissionNotEnoughCommission()
        public
        createdProposals
        proposalsAcceptedAndRejected
        proposalFunded
    {
        vm.startPrank(mainContractOwner);
        vm.expectRevert(MainContract__NotEnoughCommissionAccumulated.selector);
        mainContract.withdrawCommission();

        vm.stopPrank();
    }

    function test__WithdrawCommission()
        public
        createdProposals
        proposalsAcceptedAndRejected
        proposalFunded
        accumulateCommission
    {
        bytes32 totalFundedAmount = vm.load(address(mainContract), bytes32(uint256((2))));
        console.log("totalFundedAmount:", uint256(totalFundedAmount));
        vm.startPrank(mainContractOwner);
        mainContract.withdrawCommission();

        vm.stopPrank();

        assert(usdtAddress.balanceOf(mainContractOwner) == 220 * 10 ** usdtAddress.decimals());
        assert(
            usdtAddress.balanceOf(address(mainContract))
                == 300 * 10 ** usdtAddress.decimals() + uint256(totalFundedAmount)
        );
    }

    function test__RefundRejectedProposal() public createdProposals proposalsAcceptedAndRejected proposalFunded {
        vm.warp(block.timestamp + 1000000000);
        vm.startPrank(user1);
        mainContract.cleanOutdatedProposals(2);
        vm.stopPrank();
        vm.startPrank(user2);
        mainContract.refundOutdatedProposal(2);
        vm.stopPrank();
        assert(usdtAddress.balanceOf(user2) == 990 * 10 ** usdtAddress.decimals());
        assert(usdtAddress.balanceOf(address(mainContract)) == 1199 * 10 ** (usdtAddress.decimals() - 1));
        assert(mainContract.returnAmountFundedOfTheAddress(2, user2) == 0);
        assert(mainContract.proposalIdToDecisionStatus(2) == MainContract.Decision.Outdated);
        assert(mainContract.proposalIdToCurrentFunding(2) == 0);
    }

    function test__CleanOutdatedProposals() public createdProposals proposalsAcceptedAndRejected proposalFunded {
        vm.warp(block.timestamp + 1000000000);
        vm.startPrank(user1);
        mainContract.cleanOutdatedProposals(2);
        vm.stopPrank();
        assert(mainContract.proposalIdToDecisionStatus(2) == MainContract.Decision.Outdated);
        assert(usdtAddress.balanceOf(user1) == 999901 * 10 ** (usdtAddress.decimals() - 1));
        assert(usdtAddress.balanceOf(address(mainContract)) == 2199 * 10 ** (usdtAddress.decimals() - 1));
    }

    function test__CompanyExecutingProposal() public createdProposals proposalsAcceptedAndRejected proposalFunded {
        vm.startPrank(usdtTokenOwner);
        mainContract.fundProposal(2, 100000 * 10 ** usdtAddress.decimals());
        vm.stopPrank();
        vm.startPrank(company2Address);
        mainContract.companyExecutingProposal(2);
        vm.stopPrank();

        assert(mainContract.proposalIdToDecisionStatus(2) == MainContract.Decision.SuccessfullyFunded);
        assert(usdtAddress.balanceOf(company2Address) == 101100 * 10 ** usdtAddress.decimals());
        assert(usdtAddress.balanceOf(address(mainContract)) == 120 * 10 ** usdtAddress.decimals());
    }
}
