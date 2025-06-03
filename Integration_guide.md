# Smart Contract Integration Guide for Frontend Developers

## Introduction

This guide provides a step-by-step approach to integrating the OnGrid Finance smart contracts with the frontend for developer and investor flows. It details the key functions to call, events to listen for, and data formats for inputs and outputs.

**Assumptions:**
*   You have the ABIs for all relevant contracts.
*   You have the deployed contract addresses for:
    *   `DeveloperRegistry` (Proxy)
    *   `DeveloperDepositEscrow`
    *   `ProjectFactory` (Proxy)
    *   `USDC Token`
    *   `LiquidityPoolManager` (Proxy)
    *   `RepaymentRouter`
    *   `FeeRouter` (Proxy)
    *   Individual `DirectProjectVault` addresses (obtained from `ProjectCreated` event)
*   You are using a library like Ethers.js or Viem in TypeScript to interact with the contracts.

**Data Type Mapping (Solidity -> TypeScript/JavaScript):**
*   `address`: `string` (e.g., "0x123...")
*   `uint256`, `uint64`, `uint48`, `uint32`, `uint16`, `uint8`: `bigint` (use `BigInt("value")` for contract calls if your library requires it, or pass as `string` / `number` if the library handles conversion. For display, format from `bigint`).
*   `bytes32`, `bytes4`, `bytes`: `string` (hexadecimal, e.g., "0xabc...")
*   `bool`: `boolean`
*   `string`: `string`
*   `tuple`: `object`
*   `array` (e.g., `address[]`): `Array<type>` (e.g., `string[]`)

---

## User Flow Integration

### Flow 1: Developer Project Creation

This flow allows developers to create new projects. The system will automatically route high-value projects to have a `DirectProjectVault` created, and low-value projects to be funded by the `LiquidityPoolManager`.

#### Prerequisites for the Developer
*   Must be KYC verified in the `DeveloperRegistry`.
*   Must have sufficient USDC balance for the 20% project deposit.
*   Must have approved the `DeveloperDepositEscrow` contract to spend their USDC for the deposit amount.

#### Integration Steps

1.  **Check Developer KYC Verification Status**
    *   **Action**: Before showing the project creation form, check if the connected developer's address is verified.
    *   **Contract Interaction**: Call `DeveloperRegistry.isVerified(developerAddress)`.
    *   **Expected Outcome**: Returns `true` if verified, `false` otherwise.
    *   **UI Indication**: If not verified, guide the developer through the KYC submission process (see Flow 1A). If verified, allow proceeding to the project creation form.
    *   **Testing**:
        *   Test with a verified developer address: Should allow access.
        *   Test with an unverified developer address: Should restrict access and show KYC guidance.

2.  **Developer Submits KYC Information (Off-Chain to Admin)**
    *   **Action**: Developer fills out a KYC form in the frontend. This data (documents, personal info) is securely transmitted to the admin team/dashboard for off-chain review and verification.
    *   **Contract Interaction**: None at this frontend step. This is an off-chain process. The frontend collects data and sends it to a backend/admin system.
    *   **UI Indication**: Confirmation that KYC information has been submitted for review. Inform the developer that an admin will review their submission.
    *   **Testing**: Ensure data is correctly captured and can be securely passed to the designated backend for admin review.

3.  **Admin Verifies KYC and Submits On-Chain (Admin Panel Action)**
    *   **Action**: (Performed by Admin via Admin Panel, not directly by frontend developer flow but frontend should be aware of this step for user guidance). Admin reviews KYC documents. If approved, admin calls `DeveloperRegistry.submitKYC()` with the developer's address, a hash of KYC data, and its off-chain location, followed by `DeveloperRegistry.setVerifiedStatus(developerAddress, true)`.
    *   **Frontend Monitoring**: Frontend can periodically poll `DeveloperRegistry.isVerified(developerAddress)` or listen for `KYCStatusChanged` event to update the developer's status.

4.  **Project Creation Form**
    *   **Context**: Developer is KYC verified.
    *   **Form Inputs from Developer**:
        *   `loanAmountRequested`: Total project cost (100% of the amount the project needs). This will be a `uint256` (pass as `bigint` or string).
        *   `requestedTenor`: Loan duration in days. This will be a `uint48` (pass as number or string).
        *   `metadataCID`: IPFS CID (or similar identifier) for project details. This will be a `string`.

5.  **Calculate and Approve USDC for Deposit**
    *   **Action**:
        1.  Calculate the deposit amount: `depositAmount = (loanAmountRequested * DEVELOPER_DEPOSIT_BPS) / BASIS_POINTS_DENOMINATOR`. (`DEVELOPER_DEPOSIT_BPS` is `2000`, `BASIS_POINTS_DENOMINATOR` is `10000` from `Constants.sol`).
        2.  Developer's wallet must approve the `DeveloperDepositEscrow` contract address to spend this `depositAmount` of their USDC.
    *   **Contract Interaction**: Call `USDC_TOKEN_CONTRACT.approve(DEVELOPER_DEPOSIT_ESCROW_ADDRESS, depositAmount)`.
    *   **UI Indication**: Prompt for approval, show transaction status.
    *   **Testing**: Verify the `Approval` event from the USDC token contract. Check allowance using `USDC_TOKEN_CONTRACT.allowance(developerAddress, DEVELOPER_DEPOSIT_ESCROW_ADDRESS)`.

6.  **Call `createProject` on `ProjectFactory`**
    *   **Action**: Developer submits the project creation form.
    *   **Contract Interaction**: Call `ProjectFactory.createProject(params)` where `params` is a struct:
        ```
        {
          loanAmountRequested: BigInt(totalProjectCost), // e.g., 100000e6 for $100,000
          requestedTenor: tenorInDays, // e.g., 365
          metadataCID: "ipfs://YourMetadataCID"
        }
        ```
    *   **UI Indication**: Show transaction pending, success, or failure.
    *   **Testing**:
        *   Transaction completes successfully.
        *   Listen for either `ProjectCreated` (for high-value projects) or `LowValueProjectSubmitted` (for low-value projects) events from `ProjectFactory`.
        *   Verify `DeveloperDepositEscrow` received the 20% deposit by checking its `DepositFunded` event and its USDC balance change (if feasible).
        *   Verify `DeveloperRegistry.incrementFundedCounter(developerAddress)` was effectively called (listen for `DeveloperFundedCounterIncremented` event).

7.  **Handle `createProject` Outcome (Event-Driven)**
    *   **`ProjectCreated` Event (High-Value Project)**:
        *   **Args**: `projectId`, `developer`, `vaultAddress`, `devEscrowAddress`, `loanAmount` (this `loanAmount` is the 80% financed portion).
        *   **Action**: Store `projectId`, `vaultAddress`, and `devEscrowAddress`. The project now has a dedicated `DirectProjectVault` at `vaultAddress` ready for investor funding. The `loanAmount` here is the amount investors need to collectively provide to the vault.
    *   **`LowValueProjectSubmitted` Event (Low-Value Project)**:
        *   **Args**: `projectId`, `developer`, `poolId`, `loanAmount` (this `loanAmount` is the 80% financed portion), `success`.
        *   **Action**:
            *   If `success` is `true` and `poolId` is non-zero: The project was immediately funded by the `LiquidityPoolManager` from `poolId`. The 20% deposit should have been released back to the developer (verify by `DepositReleased` event from `DeveloperDepositEscrow`).
            *   If `success` is `false` or `poolId` is zero: The project was registered but couldn't be funded immediately (e.g., insufficient liquidity in suitable pools). It might be funded later if pool liquidity changes. The deposit remains in escrow.
    *   **UI Indication**: Display project ID, status (e.g., "Vault Created, Awaiting Funding" or "Funded by Pool X" or "Submitted to Pools, Awaiting Funding").

### Flow 2: Investor Funding a High-Value Project (via `DirectProjectVault`)

#### Prerequisites for the Investor
*   The `DirectProjectVault` address is known (from `ProjectCreated` event).
*   Investor must have sufficient USDC balance.
*   Investor must have approved the specific `DirectProjectVault` address to spend their USDC for the investment amount.

#### Integration Steps

1.  **Display Project & Vault Funding Status**
    *   **Action**: Show details of the project and its funding progress.
    *   **Contract Interactions (on `DirectProjectVault` at `vaultAddress`)**:
        *   `DirectProjectVault.getTotalAssetsInvested()`: Current amount invested.
        *   `DirectProjectVault.getLoanAmount()`: Target funding amount (this is the 80% financed portion).
        *   `DirectProjectVault.isFundingClosed()`: Indicates if the vault is still accepting investments.
        *   `DirectProjectVault.getCurrentAprBps()`: Current Annual Percentage Rate for the loan.
        *   (Optional) `DirectProjectVault.developer()`, `DirectProjectVault.projectId()`, `DirectProjectVault.loanTenor()`.
    *   **UI Indication**: Display project metadata (fetch from IPFS using CID stored in `ProjectFactory` or `DevEscrow`), funding progress bar, APR, tenor, etc. Disable investment if `isFundingClosed` is `true`.
    *   **Testing**: Ensure displayed data accurately reflects the vault's state.

2.  **Approve USDC for Investment**
    *   **Action**: Investor decides an `investmentAmount` and approves the `DirectProjectVault` to spend it.
    *   **Contract Interaction**: `USDC_TOKEN_CONTRACT.approve(VAULT_ADDRESS, investmentAmount)`.
    *   **UI Indication**: Prompt for approval, show transaction status.
    *   **Testing**: Verify `Approval` event. Check `USDC_TOKEN_CONTRACT.allowance(investorAddress, VAULT_ADDRESS)`.

3.  **Invest in the `DirectProjectVault`**
    *   **Action**: Investor confirms the investment.
    *   **Contract Interaction**: `DirectProjectVault(VAULT_ADDRESS).invest(investmentAmount)`.
    *   **UI Indication**: Show transaction pending, success (display shares/amount invested), or failure (e.g., cap reached).
    *   **Testing**:
        *   Transaction completes successfully.
        *   `Invested` event emitted from the vault with correct `investor`, `amountInvested`, and new `totalAssetsInvested`.
        *   Investor's USDC balance decreases. Vault's USDC balance increases.
        *   `DirectProjectVault.investorShares(investorAddress)` and `DirectProjectVault.totalShares` are updated.
        *   If `totalAssetsInvested` reaches `loanAmount`, the `FundingClosed` event should be emitted (possibly in the same transaction or a subsequent one if an admin closes it manually).

4.  **Monitor Funding Completion**
    *   **Action**: Listen for the `FundingClosed` event from the specific `DirectProjectVault`.
    *   **Event**: `FundingClosed(projectId, totalAssetsInvested)`
    *   **UI Indication**: Update vault status to "Funding Complete, Loan Active". Display loan start time.
    *   **Testing**: After funding is closed (either by reaching cap or manual admin call), ensure `DirectProjectVault.isFundingClosed()` is `true` and `DirectProjectVault.loanStartTime()` is set.

### Flow 3: Investor Pool Participation (via `LiquidityPoolManager`)

#### Prerequisites for the Investor
*   Investor must have sufficient USDC balance.
*   Investor must have approved the `LiquidityPoolManager` contract address to spend their USDC.

#### Integration Steps

1.  **Display Available Liquidity Pools**
    *   **Action**: Show a list of available pools for investment.
    *   **Contract Interactions**:
        *   `LiquidityPoolManager.poolCount()`: Get the total number of pools.
        *   Iterate from `poolId = 1` to `poolCount`:
            *   `LiquidityPoolManager.getPoolInfo(poolId)`: Returns `PoolInfo` struct (`exists`, `name`, `totalAssets`, `totalShares`). Only display if `exists` is `true`.
            *   (Optional) `LiquidityPoolManager.poolRiskLevels(poolId)` and `LiquidityPoolManager.poolAprRates(poolId)` to display risk/return profile.
    *   **UI Indication**: List pools with their names, total assets, current liquidity, risk level, and potentially an estimated yield or the base APR.
    *   **Testing**: Ensure all existing pools are listed correctly.

2.  **Approve USDC for Pool Deposit**
    *   **Action**: Investor chooses a `poolId`, an `amount` to deposit, and approves `LiquidityPoolManager` to spend it.
    *   **Contract Interaction**: `USDC_TOKEN_CONTRACT.approve(LIQUIDITY_POOL_MANAGER_ADDRESS, amount)`.
    *   **UI Indication**: Prompt for approval, show transaction status.
    *   **Testing**: Verify `Approval` event. Check allowance.

3.  **Deposit to a Liquidity Pool**
    *   **Action**: Investor confirms deposit into the selected `poolId`.
    *   **Contract Interaction**: `LiquidityPoolManager.depositToPool(poolId, amount)`
    *   **Expected Outcome**: Returns the amount of LP shares minted.
    *   **UI Indication**: Show transaction status. On success, display LP shares received and update user's share balance for that pool.
    *   **Testing**:
        *   Transaction completes successfully and returns a non-zero shares amount.
        *   `PoolDeposit` event emitted with correct `poolId`, `investor`, `assetsDeposited`, `sharesMinted`.
        *   Investor's USDC balance decreases. `LiquidityPoolManager`'s USDC balance increases.
        *   `LiquidityPoolManager.getUserShares(poolId, investorAddress)` reflects new share balance.
        *   `LiquidityPoolManager.getPoolInfo(poolId)` shows updated `totalAssets` and `totalShares`.

4.  **Redeem LP Shares from a Pool**
    *   **Action**: Investor chooses a `poolId` and an amount of `shares` to redeem.
    *   **Pre-check**: Call `LiquidityPoolManager.getUserShares(poolId, investorAddress)` to ensure they have enough shares. Calculate preview of assets to be received: `assets = (sharesToRedeem * poolInfo.totalAssets) / poolInfo.totalShares`.
    *   **Contract Interaction**: `LiquidityPoolManager.redeem(poolId, shares)`
    *   **Expected Outcome**: Returns the amount of USDC assets withdrawn.
    *   **UI Indication**: Show transaction status. On success, display assets received. Update user's share balance and pool's liquidity.
    *   **Testing**:
        *   Transaction completes successfully and returns a non-zero assets amount.
        *   `PoolRedeem` event emitted with correct `poolId`, `redeemer`, `sharesBurned`, `assetsWithdrawn`.
        *   Investor's USDC balance increases. `LiquidityPoolManager`'s USDC balance decreases.
        *   `LiquidityPoolManager.getUserShares(poolId, investorAddress)` reflects reduced share balance.
        *   `LiquidityPoolManager.getPoolInfo(poolId)` shows updated `totalAssets` and `totalShares`.

### Flow 4: Developer Loan Repayment (via `RepaymentRouter`)

Developers repay loans for both high-value (Vault) and low-value (Pool) projects through the central `RepaymentRouter`.

#### Prerequisites for the Developer
*   `projectId` of the loan is known.
*   Developer must have sufficient USDC for the repayment `amount`.
*   Developer must have approved the `RepaymentRouter` contract address to spend their USDC.

#### Integration Steps

1.  **Display Loan Repayment Status and Next Payment Due**
    *   **Action**: Show the developer outstanding loan details.
    *   **Contract Interactions**:
        *   Identify `fundingSourceAddress` and `poolIdForCall` (0 for vaults) for the `projectId` using:
            *   `RepaymentRouter.getFundingSource(projectId)`
            *   `RepaymentRouter.getPoolId(projectId)`
        *   Call `IFundingSource(fundingSourceAddress).getOutstandingPrincipal(poolIdForCall, projectId)` to get the current outstanding principal. (Note: `IFundingSource` is an internal interface in `RepaymentRouter`; frontend will call the `getOutstandingPrincipal` on the actual vault or LPM address).
            *   For Vaults: `DirectProjectVault(vaultAddress).getOutstandingPrincipal(0, projectId)` (or simply `getLoanAmount() - getPrincipalRepaid()`).
            *   For Pools: `LiquidityPoolManager(lpmAddress).getOutstandingPrincipal(poolId, projectId)`.
        *   Call `FeeRouter.getNextPaymentInfo(projectId)` to get `dueDate` and `paymentAmount`.
        *   (Optional) Display if loan is closed/inactive:
            *   For Vaults: `DirectProjectVault.isLoanClosed()`
            *   For Pools: `LiquidityPoolManager.getPoolLoanRecord(poolId, projectId).isActive`
    *   **UI Indication**: Display outstanding principal, next payment due date, and suggested payment amount.
    *   **Testing**: Ensure data matches on-chain state from the respective funding source and `FeeRouter`.

2.  **Approve USDC for Repayment**
    *   **Action**: Developer decides a `repaymentAmount` and approves `RepaymentRouter` to spend it.
    *   **Contract Interaction**: `USDC_TOKEN_CONTRACT.approve(REPAYMENT_ROUTER_ADDRESS, repaymentAmount)`.
    *   **UI Indication**: Prompt for approval, show transaction status.
    *   **Testing**: Verify `Approval` event and allowance.

3.  **Make Repayment via `RepaymentRouter`**
    *   **Action**: Developer confirms the repayment.
    *   **Contract Interaction**: `RepaymentRouter.repay(projectId, repaymentAmount)`.
    *   **UI Indication**: Show transaction pending, success, or failure.
    *   **Testing**:
        *   Transaction completes successfully.
        *   `RepaymentRouted` event emitted from `RepaymentRouter` with breakdown of fees, principal, interest.
        *   `FeeRouted` event emitted from `FeeRouter`.
        *   Developer's USDC balance decreases.
        *   The respective funding source (`DirectProjectVault` or `LiquidityPoolManager`) should emit a `RepaymentReceived` event (or similar internal event if not explicitly emitted for external consumers but state should update).
        *   Check updated `principalRepaid` on the funding source.
        *   `FeeRouter.projectFeeInfo(projectId).lastMgmtFeeTimestamp` should be updated.
        *   `FeeRouter.updatePaymentSchedule(projectId)` is called internally, so `FeeRouter.getNextPaymentInfo(projectId)` should show an updated due date.

4.  **Monitor Loan Closure**
    *   **For Vaults**: Listen for `LoanClosed` event from the specific `DirectProjectVault`.
    *   **For Pool Loans**: Monitor `LiquidityPoolManager.getPoolLoanRecord(poolId, projectId).isActive` becoming `false`.
    *   **UI Indication**: Update loan status to "Closed" or "Fully Repaid".

### Flow 5: Investor Claiming Yield & Principal from `DirectProjectVault`

#### Prerequisites for the Investor
*   Investor has invested in a `DirectProjectVault` that has received repayments.
*   The `DirectProjectVault` address is known.

#### Integration Steps

1.  **Display Claimable Amounts**
    *   **Action**: Show the investor how much principal and yield they can currently claim from a specific vault.
    *   **Contract Interactions (on `DirectProjectVault` at `VAULT_ADDRESS`)**:
        *   `DirectProjectVault.claimablePrincipal(investorAddress)`
        *   `DirectProjectVault.claimableYield(investorAddress)`
        *   (Optional) `DirectProjectVault.isLoanClosed()` to indicate if all funds are expected to be claimable.
    *   **UI Indication**: Display claimable principal and yield amounts. Enable claim buttons if amounts are greater than zero.
    *   **Testing**: Ensure amounts match expected distributions based on repayments and investor's share.

2.  **Claim Principal and/or Yield**
    *   **Option A: Claim Both (Redeem)**
        *   **Action**: Investor clicks a "Redeem All" or "Claim All" button.
        *   **Contract Interaction**: `DirectProjectVault(VAULT_ADDRESS).redeem()`
        *   **Expected Outcome**: Returns `principalAmount` and `yieldAmount` claimed.
    *   **Option B: Claim Principal Only**
        *   **Action**: Investor clicks "Claim Principal".
        *   **Contract Interaction**: `DirectProjectVault(VAULT_ADDRESS).claimPrincipal()`
    *   **Option C: Claim Yield Only**
        *   **Action**: Investor clicks "Claim Yield".
        *   **Contract Interaction**: `DirectProjectVault(VAULT_ADDRESS).claimYield()`
    *   **UI Indication**: Show transaction status. On success, update investor's USDC balance and reduce their displayed claimable amounts for that vault.
    *   **Testing**:
        *   Transaction completes successfully.
        *   `PrincipalClaimed` and/or `YieldClaimed` events emitted from the vault with correct `investor` and `amountClaimed`.
        *   Investor's USDC balance increases by the claimed amount(s).
        *   `DirectProjectVault.principalClaimedByInvestor(investorAddress)` and `DirectProjectVault.interestClaimedByInvestor(investorAddress)` are updated.
        *   Subsequent calls to `claimablePrincipal` / `claimableYield` should show reduced or zero amounts for what was just claimed.

## General Event Monitoring and UI Updates

To provide a responsive user experience, the frontend should actively listen for key events from the relevant smart contracts and update the UI accordingly. This includes:

*   **Global Events**:
    *   `ProjectFactory`: `ProjectCreated`, `LowValueProjectSubmitted`
*   **Vault-Specific Events (for a given `vaultAddress`)**:
    *   `DirectProjectVault`: `Invested`, `FundingClosed`, `RepaymentReceived`, `YieldClaimed`, `PrincipalClaimed`, `RiskParamsUpdated`, `LoanClosed`
*   **Liquidity Pool Manager Events**:
    *   `LiquidityPoolManager`: `PoolCreated`, `PoolDeposit`, `PoolRedeem`, `PoolProjectFunded`, `PoolRepaymentReceived`, `LoanDefaulted`
*   **Developer Deposit Events**:
    *   `DeveloperDepositEscrow`: `DepositFunded`, `DepositReleased` (especially after successful low-value project funding), `DepositSlashed`
*   **Repayment & Fee Events**:
    *   `RepaymentRouter`: `RepaymentRouted`
    *   `FeeRouter`: `FeeRouted`
*   **KYC Events**:
    *   `DeveloperRegistry`: `KYCStatusChanged`, `KYCSubmitted` (less critical for direct UI update, more for admin awareness), `DeveloperFundedCounterIncremented`

Setting up robust event listeners will ensure the UI dynamically reflects the on-chain state of projects, investments, and user balances.