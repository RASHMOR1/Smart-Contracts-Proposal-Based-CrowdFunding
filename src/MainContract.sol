// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzepplein/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20WithDecimals} from "./interfaces/IERC20WithDecimals.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


contract MainContract is Ownable, ReentrancyGuard {
    error MainContract__NotAllowedToPerformThisAction();
  
    error MainContract__ProposalDoesNotExist();
    error MainContract__ProposalIsOutdated();
    error MainContract__ProposalIsInTheWrongStatus();
    error MainContract__ProposalIsStillActive();
    error MainContract__NotEnoughCommissionAccumulated();

    using SafeERC20 for IERC20;

    enum Decision {
        Pending,
        Accepted, // proposition is accepted and proposition can be funded
        Rejected,
        SuccessfullyFunded, // funding is collected by the company and proposition will be executed
        Outdated
    }

    uint256 public currentProposalId = 1;
    address immutable usdtTokenAddress;
    uint256 immutable usdtDecimals;
    uint256 private totalFundedAmount;

    mapping(address => mapping(uint256 => uint256)) internal companyAddressToProposalSerialNumberToProposalId;
    mapping(address => uint256) public lastProposalSerialNumber;
    mapping(uint256 => Decision) public proposalIdToDecisionStatus;
    mapping(uint256 => string) public proposalIdToURI;
    mapping(uint256 => address) public proposalIdToCompanyAddress;
    mapping(uint256 => uint256) public proposalIdToFundingGoal;
    mapping(uint256 => uint256) public proposalIdToCurrentFunding;
    mapping(uint256 => mapping(address => uint256)) internal proposalIdToContributorAddressToAmountFunded;
    mapping(uint256 => uint256) public proposalIdToDeadline;

    event MainContract__ProposalCreated(uint256 indexed proposalId, address indexed toCompanyAddress, address indexed fromAddress, string proposalURI, Decision decisionStatus, uint256 fundingGoal, uint256 currentFunding, uint256 deadline);
    event MainContract__ProposalStatusChanged(uint256 indexed proposalId, Decision decisionStatus);
    event MainContract__ProposalFunded(uint256 indexed proposalId, uint256 indexed fundingAmount);
    event MainContract__CommissionWithdrawn(uint256 indexed commissionAmount);
    event MainContract__RefundIssued(uint256 indexed proposalId, address indexed recipient, uint256 indexed amount);
    event MainContract__CompanyExecutingProposal(
        uint256 indexed proposalId, uint256 indexed currentFunding,  Decision decisionStatus, uint256 timeStamp
    );
    event MainContract__ProposalFundingGoalAndDeadlineUpdated(uint256 indexed proposalId, uint256 fundingGoal, uint256 deadline);

    constructor(address _usdtTokenAddress) Ownable(msg.sender) {
        usdtTokenAddress = _usdtTokenAddress;
        usdtDecimals = IERC20WithDecimals(usdtTokenAddress).decimals();
    }

    // each proposal creation requires a commission of 10 USDT
    function createProposal(address toCompanyAddress, string memory proposalURI) external {
        uint256 currentProposalIdMemory = currentProposalId;
        proposalIdToURI[currentProposalIdMemory] = proposalURI;
        companyAddressToProposalSerialNumberToProposalId[toCompanyAddress][lastProposalSerialNumber[toCompanyAddress]] =
            currentProposalIdMemory;
        lastProposalSerialNumber[toCompanyAddress] = currentProposalIdMemory;

        proposalIdToCompanyAddress[currentProposalIdMemory] = toCompanyAddress;
        unchecked {
            ++currentProposalId;
        }

        IERC20(usdtTokenAddress).safeTransferFrom(msg.sender, address(this), 10 * 10 ** usdtDecimals);
        emit MainContract__ProposalCreated(currentProposalIdMemory, toCompanyAddress, msg.sender, proposalURI, Decision.Pending, 0, 0, 0);
    }

    function companyMakeDecision(uint256 proposalId, Decision decision, uint256 fundingGoal, uint256 deadline)
        external
    {
        if (msg.sender != proposalIdToCompanyAddress[proposalId]) {
            revert MainContract__NotAllowedToPerformThisAction();
        }
        if (proposalIdToDecisionStatus[proposalId] != Decision.Pending) {
            revert MainContract__ProposalIsInTheWrongStatus();
        }
        proposalIdToDecisionStatus[proposalId] = decision;
        proposalIdToFundingGoal[proposalId] = fundingGoal;
        proposalIdToDeadline[proposalId] = deadline;
        emit MainContract__ProposalStatusChanged(proposalId, decision);
        emit MainContract__ProposalFundingGoalAndDeadlineUpdated(proposalId, fundingGoal, deadline);
    }

    // need to check that funding amount is equal to the amount that is being sent
    function fundProposal(uint256 proposalId, uint256 fundingAmount) external {
        if (currentProposalId <= proposalId) {
            revert MainContract__ProposalDoesNotExist();
        }
        if (proposalIdToDecisionStatus[proposalId] != Decision.Accepted) {
            revert MainContract__ProposalIsInTheWrongStatus();
        }
        if (block.timestamp > proposalIdToDeadline[proposalId]) {
            revert MainContract__ProposalIsOutdated();
        }
        proposalIdToCurrentFunding[proposalId] += fundingAmount;
        proposalIdToContributorAddressToAmountFunded[proposalId][msg.sender] = fundingAmount;
        totalFundedAmount += fundingAmount;
        IERC20(usdtTokenAddress).safeTransferFrom(msg.sender, address(this), fundingAmount);
        emit MainContract__ProposalFunded(proposalId, fundingAmount);
    }

    // The owner is prohibited from withdrawing the entire commission, as the contract must retain a minimum balance (at least $300) to cover the costs associated with removing outdated proposals
    function withdrawCommission() external onlyOwner nonReentrant {
        uint256 commissionAccumulated = IERC20(usdtTokenAddress).balanceOf(address(this));
        if (commissionAccumulated < 300 * 10 ** usdtDecimals) {
            revert MainContract__NotEnoughCommissionAccumulated();
        }
        uint256 commissionAllowedToWithdraw = commissionAccumulated - 300 * 10 ** usdtDecimals - totalFundedAmount;

        IERC20(usdtTokenAddress).safeTransfer(msg.sender, commissionAllowedToWithdraw);
        emit MainContract__CommissionWithdrawn(commissionAllowedToWithdraw);
    }

    function refundOutdatedProposal(uint256 proposalId) external nonReentrant {
        if (proposalIdToDecisionStatus[proposalId] != Decision.Outdated) {
            revert MainContract__ProposalIsInTheWrongStatus();
        }
        uint256 amountToTransfer = proposalIdToContributorAddressToAmountFunded[proposalId][msg.sender];
        totalFundedAmount -= amountToTransfer;
        proposalIdToContributorAddressToAmountFunded[proposalId][msg.sender] = 0;
        proposalIdToCurrentFunding[proposalId] -= amountToTransfer;

        IERC20(usdtTokenAddress).safeTransfer(msg.sender, amountToTransfer);
        emit MainContract__RefundIssued(proposalId, msg.sender, amountToTransfer);
    }

    // The function doesn’t verify if the funding goal has been achieved. The company has the ability to initiate the execution of the proposal without meeting the goal, thereby collecting all the funds that have been raised.

    function companyExecutingProposal(uint256 proposalId) external nonReentrant {
        if (msg.sender != proposalIdToCompanyAddress[proposalId]) {
            revert MainContract__NotAllowedToPerformThisAction();
        }
        if (proposalIdToDecisionStatus[proposalId] != Decision.Accepted) {
            revert MainContract__ProposalIsInTheWrongStatus();
        }
        proposalIdToDecisionStatus[proposalId] = Decision.SuccessfullyFunded;
        uint256 amountToWithdraw = proposalIdToCurrentFunding[proposalId];
        proposalIdToCurrentFunding[proposalId] = 0;
        totalFundedAmount -= amountToWithdraw;

        IERC20(usdtTokenAddress).safeTransfer(msg.sender, amountToWithdraw);
        emit MainContract__CompanyExecutingProposal(proposalId, amountToWithdraw, Decision.SuccessfullyFunded,   block.timestamp);
    }

    //anyone can clean outdated proposals and recieve 0.1$ as a compensation
    function cleanOutdatedProposals(uint256 proposalId) external nonReentrant {
        if (proposalIdToDeadline[proposalId] > block.timestamp) {
            revert MainContract__ProposalIsStillActive();
        }
        if (proposalIdToDecisionStatus[proposalId] != Decision.Accepted) {
            revert MainContract__ProposalIsInTheWrongStatus();
        }
        proposalIdToDecisionStatus[proposalId] = Decision.Outdated;
        IERC20(usdtTokenAddress).safeTransfer(msg.sender, 1 * 10 ** (usdtDecimals - 1));
        emit MainContract__ProposalStatusChanged(proposalId, Decision.Outdated);
    }

    // view functions

    function returnSerialNumberOfTheProposalId(address companyAddress, uint256 serialNumber)
        external
        view
        returns (uint256)
    {
        return companyAddressToProposalSerialNumberToProposalId[companyAddress][serialNumber];
    }

    function returnAmountFundedOfTheAddress(uint256 proposalId, address contributorAddress)
        external
        view
        returns (uint256)
    {
        return proposalIdToContributorAddressToAmountFunded[proposalId][contributorAddress];
    }

    // What happens when a proposal becomes outdated without gathering sufficient funds?
    // ----- Contributors have the option to invoke the refundOutdatedProposal function and reclaim their contributions.

    // What if a proposal has collected the necessary funds but the company hasn't initiated the executeProposal function?
    // ----- If the company doesn't initiate the companyExecutingProposal function, it implies that they have rescinded their initial acceptance and no longer wish to execute the proposal. The company won't receive the collected funds and once the proposal becomes outdated, contributors will be able to reclaim their funds.

    // What occurs if the funding collected surpasses the goal?
    // ----- In such a scenario, the company will receive all the funds collected by the proposal, which includes the goal amount plus any additional funds raised.
}
