// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title Errors
 * @dev Defines custom errors for the OnGrid Finance protocol to provide
 * more gas-efficient and descriptive revert messages.
 */
library Errors {
    // --- Access Control ---
    error NotAuthorized(address caller, bytes32 role);
    error CallerNotDeveloper(address caller, uint256 projectId);
    error CallerNotFundingSource(address caller, address expectedSource);

    // --- State & Validity Checks ---
    error InvalidAmount(uint256 amount);
    error AmountCannotBeZero();
    error AddressCannotBeZero();
    error StringCannotBeEmpty();
    error InvalidAddress(address addr);
    error InvalidValue(string reason);
    error ValueOutOfRange(string variable, uint256 value, uint256 min, uint256 max);
    error AlreadyInitialized();
    error NotInitialized();
    error FundingNotOpen();
    error FundingClosed();
    error LoanAlreadyClosed();
    error LoanNotClosed();
    error DeadlinePassed();
    error InvalidState(string reason);
    error ZeroAddressNotAllowed();

    // --- KYC & Verification ---
    error NotVerified(address developer);
    error AlreadyVerified(address developer);
    error KYCHashAlreadyExists(address developer, bytes32 kycHash);

    // --- Deposits & Escrow ---
    error DepositInsufficient(uint256 required, uint256 provided);
    error DepositAlreadyExists(uint256 projectId);
    error DepositNotFound(uint256 projectId);
    error DepositAlreadyReleased(uint256 projectId);
    error EscrowNotFundedSufficiently(uint256 required, uint256 available);
    error EscrowAlreadyFunded(uint256 projectId);
    error MilestoneAlreadySet(uint8 index);
    error MilestoneNotAuthorized(uint8 index);
    error MilestoneAlreadyWithdrawn(uint8 index);
    error MilestoneAmountExceedsAllocation(uint256 milestoneAmount, uint256 remainingAllocation);
    error MilestoneIndexOutOfBounds(uint8 index, uint8 maxIndex);
    error TotalMilestoneAmountMismatch(uint256 totalMilestones, uint256 totalAllocated);
    error ExceedsTotalAllocation(uint256 amount, uint256 totalAllocated);
    error WithdrawAmountExceedsAvailable(uint256 withdrawAmount, uint256 availableAmount);

    // --- Funding & Investment ---
    error FundingCapReached(uint256 limit);
    error InvestmentBelowMinimum(uint256 minimum);
    error InsufficientLiquidity();
    error CannotInvestZero();

    // --- Repayment & Claims ---
    error NothingToClaim();
    error NothingToRepay();
    error RepaymentAmountInvalid(uint256 amount);

    // --- Pools ---
    error PoolDoesNotExist(uint256 poolId);
    error PoolAlreadyExists(uint256 poolId);
    error InsufficientShares(uint256 required, uint256 available);
    error CannotRedeemZeroShares();

    // --- Oracle ---
    error OracleDataNotAvailable(uint256 projectId);
    error InvalidOracleData(string reason);
    error TargetContractNotSet(uint256 projectId);

    // --- UUPS ---
    error NotImplementingFunction(bytes4 functionSelector);
} 