# Smart Contract Integration Guide for Frontend Developers

## Introduction

This guide provides a step-by-step approach to integrating the project's smart contracts with the frontend. It details the order of contract integration, key functions to call, events to listen for, and data formats for inputs and outputs.

**Assumptions:**
*   You have the ABIs for all contracts.
*   You have the deployed contract addresses.
*   You are using a library like Ethers.js or Viem in TypeScript to interact with the contracts.

**Data Type Mapping (Solidity -> TypeScript):**
*   `address`: `string` (e.g., "0x123...")
*   `uint256`, `uint64`, `uint48`, `uint32`, `uint16`, `uint8`: `bigint` (use `BigInt("value")` or `ethers.BigNumber.from("value").toBigInt()` for Ethers.js v5, or handle as `string` for display and convert to `bigint` for contract calls). For simplicity in examples, `string` representations of numbers will be used, assuming conversion to `bigint` before contract interaction.
*   `bytes32`, `bytes4`, `bytes`: `string` (hexadecimal, e.g., "0xabc...")
*   `bool`: `boolean`
*   `string`: `string`
*   `tuple`: `object`
*   `array` (e.g., `address[]`): `Array<type>` (e.g., `string[]`)

---

## Integration Flow & Contract Details

The integration can be broken down into logical user flows and the contracts involved in each.

### Flow 0: System Setup & Initial Configuration (Primarily Backend/Admin)

*   **Action:** Core contracts are deployed and initialized by the admin/deployer. `ProjectFactory` has its dependent addresses (including `FeeRouter` and `RepaymentRouter` address, which is then cast to `IRepaymentRouter` for calls) set via `setAddresses`.
*   **Frontend Relevance:** The frontend will need the addresses of these core contracts to interact with them. Roles are set up during initialization or via an admin panel.

### Flow 1: Developer Onboarding & KYC

#### Contract: `DeveloperRegistry`

*   **Purpose:** Manages developer identities, KYC status, and funding history.
*   **Frontend Interaction:** Allows developers to submit KYC (or admins to do so on their behalf) and view their status.

**Functions:**

*   **`submitKYC(address developer, bytes32 kycHash, string kycDataLocation)`**
    *   **Purpose:** Submits KYC information for a developer. Typically called by an admin or a trusted KYC provider role.
    *   **Role Required:** `Constants.KYC_ADMIN_ROLE` (on `DeveloperRegistry`)
    *   **Inputs:**
        *   `developer` (`address`): The Ethereum address of the developer.
            *   Example: `"0x1234567890123456789012345678901234567890"`
        *   `kycHash` (`bytes32`): A hash of the developer's KYC documents.
            *   Example: `"0xabcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"`
        *   `kycDataLocation` (`string`): A URI or identifier pointing to the off-chain storage of the KYC documents (e.g., IPFS CID).
            *   Example: `"ipfs://QmXyZ..."`
    *   **Outputs:** None.
    *   **Frontend Interaction:** An admin interface might use this. A developer might initiate a request that leads an admin to call this.

*   **`setVerifiedStatus(address developer, bool verified)`**
    *   **Purpose:** Sets the KYC verification status for a developer. Called by an admin (KYC_ADMIN_ROLE).
    *   **Role Required:** `Constants.KYC_ADMIN_ROLE` (on `DeveloperRegistry`)
    *   **Inputs:**
        *   `developer` (`address`): The developer's address.
            *   Example: `"0x1234567890123456789012345678901234567890"`
        *   `verified` (`bool`): The verification status (`true` or `false`).
            *   Example: `true`
    *   **Outputs:** None.
    *   **Frontend Interaction:** Admin interface.

*   **`getDeveloperInfo(address developer)`**
    *   **Purpose:** Retrieves all information about a developer.
    *   **Inputs:**
        *   `developer` (`address`): The developer's address.
            *   Example: `"0x1234567890123456789012345678901234567890"`
    *   **Outputs:**
        *   `DevInfo` (tuple/object):
            *   `kycDataHash` (`bytes32`): Hash of KYC data.
            *   `isVerified` (`bool`): Verification status.
            *   `timesFunded` (`uint32`): Number of times the developer has had projects funded.
            *   Example Output:
                ```json
                {
                  "kycDataHash": "0xabcdef...",
                  "isVerified": true,
                  "timesFunded": "2"
                }
                ```
    *   **Frontend Interaction:** Display developer profile information, KYC status.

*   **`isVerified(address developer)`**
    *   **Purpose:** Checks if a developer is KYC verified.
    *   **Inputs:**
        *   `developer` (`address`): The developer's address.
            *   Example: `"0x1234567890123456789012345678901234567890"`
    *   **Outputs:**
        *   `bool`: `true` if verified, `false` otherwise.
            *   Example: `true`
    *   **Frontend Interaction:** Conditional rendering based on verification status.

*   **`getKycDataLocation(address developer)`**
    *   **Purpose:** Retrieves the off-chain location of the developer's KYC data.
    *   **Inputs:**
        *   `developer` (`address`): The developer's address.
            *   Example: `"0x1234567890123456789012345678901234567890"`
    *   **Outputs:**
        *   `string`: The KYC data location string.
            *   Example: `"ipfs://QmXyZ..."`
    *   **Frontend Interaction:** Potentially used by admins to access KYC documents.

*   **`getTimesFunded(address developer)`**
    *   **Purpose:** Retrieves how many times a developer has had a project funded.
    *   **Inputs:**
        *   `developer` (`address`): The developer's address.
            *   Example: `"0x1234567890123456789012345678901234567890"`
    *   **Outputs:**
        *   `uint32`: Number of funded projects.
            *   Example: `"2"`
    *   **Frontend Interaction:** Display developer's track record.

**Events:**

*   **`KYCSubmitted(address developer, bytes32 kycHash)`**
    *   **Purpose:** Signals that KYC data has been submitted for a developer.
    *   **Data:**
        *   `developer` (`address`): The developer's address.
        *   `kycHash` (`bytes32`): The hash of the submitted KYC data.
    *   **Frontend Interaction:** Update UI to show KYC "Pending Review" status.

*   **`KYCStatusChanged(address developer, bool isVerified)`**
    *   **Purpose:** Signals a change in a developer's KYC verification status.
    *   **Data:**
        *   `developer` (`address`): The developer's address.
        *   `isVerified` (`bool`): The new verification status.
    *   **Frontend Interaction:** Update UI to reflect new KYC status (Verified/Not Verified).

*   **`DeveloperFundedCounterIncremented(address developer, uint32 newCount)`**
    *   **Purpose:** Signals that a developer's funded project counter has increased.
    *   **Data:**
        *   `developer` (`address`): The developer's address.
        *   `newCount` (`uint32`): The new count of funded projects.
    *   **Frontend Interaction:** Update developer profile/track record.

---

### Flow 2: Project Creation (Developer Interaction with `ProjectFactory`)

This flow describes how a verified developer creates a project listing, which can then be funded either as a high-value direct vault or through a liquidity pool.

#### Contract: `ProjectFactory`

*   **Purpose:** Developer entry point for listing projects. Verifies KYC, handles the 20% deposit, and then either deploys a `DirectProjectVault` (for high-value projects) or submits the project to `LiquidityPoolManager` (for low-value projects).
*   **Frontend Interaction:** Developers (after KYC verification) use this to create projects.

**Functions:**

*   **`createProject(ProjectParams calldata params)`**
    *   **Purpose:** Allows a verified developer (`msg.sender`) to create a new project.
    *   **Inputs (`params` struct):**
        *   `loanAmountRequested` (`uint256`): The total cost of the project (100%) in USDC smallest unit.
        *   `requestedTenor` (`uint48`): Duration of the loan in days.
        *   `metadataCID` (`string`): IPFS CID or similar for project details.
    *   **Outputs:** `uint256 projectId`.
    *   **Frontend Interaction:** Developer provides project details in a form. The frontend calls this function.
    *   **Internal Logic Summary:**
        1.  Validates inputs and developer KYC status.
        2.  Generates `projectId`.
        3.  Calculates `depositAmount` (20% of `loanAmountRequested`) and `financedAmount` (80%).
        4.  Calls `DeveloperDepositEscrow.fundDeposit(projectId, developer, depositAmount)`. (Requires `ProjectFactory` to have `DEPOSIT_FUNDER_ROLE` on `DeveloperDepositEscrow`).
        5.  **Routing based on `totalProjectCost` (`params.loanAmountRequested`):**
            *   **High-Value Project (>= `HIGH_VALUE_THRESHOLD`):**
                *   Calls internal `_deployAndInitializeHighValueProject` which:
                    *   Deploys new `DevEscrow` (initialized with `financedAmount`).
                    *   Deploys new `DirectProjectVault`.
                    *   Initializes `DirectProjectVault` (passing `adminAddress`, `repaymentRouterAddress`, `riskOracleAdapterAddress`, etc. The `DEV_ESCROW_ROLE` grant within the vault is commented out as `triggerDrawdown` is not used).
                    *   Grants `RELEASER_ROLE` on `DeveloperDepositEscrow` to the new `DirectProjectVault`.
                    *   Calls `IRiskRateOracleAdapter(riskOracleAdapterAddress).setTargetContract(projectId, vaultAddress, 0)`.
                    *   Calls `feeRouter.setProjectDetails(projectId, params.loanAmountRequested, developer, block.timestamp)`.
                    *   Calls `feeRouter.setRepaymentSchedule(projectId, ...)` with a calculated weekly schedule.
                    *   Calls `IRepaymentRouter(repaymentRouterAddress).setFundingSource(projectId, vaultAddress, 0)`.
            *   **Low-Value Project (< `HIGH_VALUE_THRESHOLD`):**
                *   Prepares `ILiquidityPoolManager.ProjectParams` with `financedAmount` (80%) as `loanAmountRequested` and `params.loanAmountRequested` (100%) as `totalProjectCost`.
                *   Calls `LiquidityPoolManager.registerAndFundProject(projectId, developer, poolParams)`.
                *   If `LiquidityPoolManager` successfully funds (returns `success = true`), `ProjectFactory` calls `DeveloperDepositEscrow.transferDepositToProject(projectId)` to return the 20% deposit to the developer.
        6.  Calls `DeveloperRegistry.incrementFundedCounter(developer)`. (Requires `ProjectFactory` to have `PROJECT_HANDLER_ROLE` on `DeveloperRegistry`).

**Events:**

*   **`ProjectCreated(uint256 indexed projectId, address indexed developer, address vaultAddress, address devEscrowAddress, uint256 loanAmount)`** (For high-value projects, `loanAmount` here is the `financedAmount` - 80%)
    *   **Frontend Interaction:** Store `vaultAddress` and `devEscrowAddress`. Update UI.
*   **`LowValueProjectSubmitted(uint256 indexed projectId, address indexed developer, uint256 poolId, uint256 loanAmount, bool success)`** (`loanAmount` here is the `financedAmount` - 80%)
    *   **Frontend Interaction:** Update UI based on submission success to LPM.

---

### Flow 3: Investing in a Project (Direct Vault)

Investors interact with a specific `DirectProjectVault` instance created in Flow 2.

#### Contract: `DirectProjectVault` (Instance)

*   **Purpose:** Manages investments, loan lifecycle, repayments, and claims for a single project.
*   **Frontend Interaction:** Investors deposit USDC to fund the project.

**Functions:**

*   **`invest(uint256 amount)`**
    *   **Purpose:** Allows an investor to deposit USDC into the vault.
    *   **Inputs:**
        *   `amount` (`uint256`): The amount of USDC to invest.
            *   Example: `"1000000000"` (for 1,000 USDC, assuming 6 decimals)
    *   **Outputs:** None.
    *   **Frontend Interaction:** User inputs investment amount, approves USDC transfer to the vault, then calls this function.
    *   **Pre-requisite:** Investor must have approved the `DirectProjectVault` contract to spend their USDC.

*   **`getTotalAssetsInvested()`**
    *   **Purpose:** Gets the total amount of USDC currently invested in the vault (by investors).
    *   **Outputs:** `uint256`.

*   **`getLoanAmount()`**
    *   **Purpose:** Gets the target loan amount to be funded by investors (the 80% financed portion).
    *   **Outputs:** `uint256`.

*   **`isFundingClosed()`**
    *   **Purpose:** Checks if the funding period for this vault is closed.
    *   **Outputs:** `bool`.

**Events:**

*   **`Invested(address indexed investor, uint256 amountInvested, uint256 totalAssetsInvested)`**

---

### Flow 4: Funding Closure & Fund Disbursement (Direct Vault)

Once a `DirectProjectVault`'s funding goal is met or an admin closes it.

#### Contract: `DirectProjectVault` (Instance)

**Functions:**

*   **`closeFundingManually()`**
    *   **Purpose:** Manually closes the funding period. Called by an admin/authorized role. Can also be triggered if `invest` hits the `loanAmount`.
    *   **Role Required:** `Constants.DEFAULT_ADMIN_ROLE` (on the specific `DirectProjectVault` instance).
    *   **Frontend Interaction:** Admin action.
    *   **Internal Action (`_closeFunding()`):**
        1.  Sets `fundingClosed = true`, `loanStartTime = block.timestamp`.
        2.  Transfers `totalAssetsInvested` (investor funds - 80%) directly to the `developer`.
        3.  Calls `DeveloperDepositEscrow.transferDepositToProject(projectId)` (to transfer the 20% developer deposit also to the `developer`). Requires Vault to have `RELEASER_ROLE` on `DeveloperDepositEscrow`.
        4.  Calls `DevEscrow.notifyFundingComplete(totalAssetsInvested + developerDeposit)` with the total project cost (100%).

**Events:**

*   **`FundingClosed(uint256 projectId, uint256 totalAssetsInvested)`**
*   **`DrawdownExecuted(uint256 projectId, address indexed developer, uint256 amount)`**
    *   **Note:** The `triggerDrawdown` function in `DirectProjectVault` which previously emitted this event is now commented out. This event will not be emitted by the Vault under the current direct disbursement model from `_closeFunding`. The concept of a separate drawdown post-funding closure is no longer applicable for the Vault.

#### Contract: `DevEscrow` (Instance for the Project)

*   **Purpose:** Record-keeping for funds allocated and disbursed to the developer. It is notified by the funding source (`DirectProjectVault` or `LiquidityPoolManager`) when funds are sent to the developer.
*   **Frontend Interaction:** Mostly indirect; status updates based on its events.

**Functions:**

*   **`notifyFundingComplete(uint256 amount)`**
    *   **Purpose:** Signals that funds have been sent to the developer and the funding/loan is active. Called by `DirectProjectVault` (via `_closeFunding`) or `LiquidityPoolManager` (via `registerAndFundProject`).
    *   **Role Required:** `Constants.DEFAULT_ADMIN_ROLE` (on the `DevEscrow` instance, which is granted to the funding source like `DirectProjectVault` or `LPM` during `DevEscrow` initialization).
    *   **Inputs:** `amount` (`uint256`): Total amount successfully transferred/made available to the developer (e.g., 100% of project cost).
    *   **Frontend Interaction:** System internal call.

**Events:**

*   **`FundingComplete(address indexed developer, uint256 amount)` (on `DevEscrow`)**
    *   **Frontend Interaction:** Update project status to "Funds Disbursed" / "Loan Active".

#### Contract: `DeveloperDepositEscrow`

*   **`fundDeposit(uint256 projectId, address developer, uint256 amount)`**: Called by `ProjectFactory` to lock the developer's deposit.
*   **`transferDepositToProject(uint256 projectId)`**: Called by `ProjectFactory` (for LPM projects) or `DirectProjectVault` (for vault projects) when the main loan is funded, to return the developer's 20% deposit to the developer.
*   **Event: `DepositFunded(...)`**
*   **Event: `DepositReleased(...)`** (See Loan Closure)

---

### Flow 5: Project Funding (Liquidity Pool)

LPs invest in general pools. `LiquidityPoolManager` then allocates funds from these pools to specific low-value projects, triggered by `ProjectFactory`.

#### Contract: `LiquidityPoolManager`

*   **Purpose:** Manages liquidity pools and allocates funds to low-value projects.
*   **Frontend Interaction:** LPs invest/redeem. `ProjectFactory` triggers project funding.

**Functions (LP Interaction):**

*   **`createPool(uint256 poolId_unused, string calldata name)`** (Role: `DEFAULT_ADMIN_ROLE`) - Creates a new pool. `poolId` is now managed internally.
*   **`depositToPool(uint256 poolId, uint256 amount)`** - LP deposits USDC.
*   **`redeem(uint256 poolId, uint256 shares)`** - LP redeems shares for USDC.

**Functions (Project Funding - called by `ProjectFactory`):**

*   **`registerAndFundProject(uint256 projectId, address developer, ILiquidityPoolManager.ProjectParams calldata params)`**
    *   **Purpose:** `ProjectFactory` calls this to attempt funding a low-value project.
    *   **Role Required:** `Constants.PROJECT_HANDLER_ROLE` (on `LiquidityPoolManager`, granted to `ProjectFactory`).
    *   **Inputs (`params` struct from `ProjectFactory`):
        *   `loanAmountRequested` (`uint256`): The 80% financed portion.
        *   `totalProjectCost` (`uint256`): The 100% total project cost.
        *   `requestedTenor` (`uint48`): Loan duration in days.
        *   `metadataCID` (`string`): Project metadata.
    *   **Outputs:** `(bool success, uint256 poolId)`.
    *   **Internal Logic Summary (if a suitable pool is found):**
        1.  Deploys and initializes `DevEscrow` for the project (LPM is admin of this DevEscrow, pauser is LPM itself).
        2.  Creates a `LoanRecord` for the `loanAmountRequested` (80%).
        3.  Transfers `loanAmountRequested` (80%) from the pool to the `developer`.
        4.  Calls `DevEscrow.notifyFundingComplete(params.totalProjectCost)` with the 100% amount.
        5.  Calls `FeeRouter.setProjectDetails(projectId, params.totalProjectCost, developer, block.timestamp)`.
        6.  Calls `FeeRouter.setRepaymentSchedule(projectId, ...)` with a calculated weekly schedule.
        7.  Calls `DeveloperRegistry.incrementFundedCounter(developer)`.
        8.  Calls `IRepaymentRouter(repaymentRouter).setFundingSource(projectId, address(this), poolId)`.
        9.  Calls `IRiskRateOracleAdapter(riskOracleAdapter).setTargetContract(projectId, address(this), poolId)`.
        *   The `ProjectFactory` (caller) is responsible for calling `DeveloperDepositEscrow.transferDepositToProject(projectId)` if this function returns `success = true`.

**View Functions:**
*   **`getPoolInfo(uint256 poolId)`**
*   **`getPoolLoanRecord(uint256 poolId, uint256 projectId)`**
*   **`getUserShares(uint256 poolId, address user)`**

**Events:**
*   **`PoolCreated(uint256 indexed poolId, string name, address indexed creator)`** (Updated event signature)
*   **`PoolDeposit(uint256 indexed poolId, address indexed investor, uint256 assetsDeposited, uint256 sharesMinted)`**
*   **`PoolRedeem(uint256 indexed poolId, address indexed redeemer, uint256 sharesBurned, uint256 assetsWithdrawn)`**
*   **`PoolProjectFunded(uint256 indexed poolId, uint256 indexed projectId, address indexed developer, address devEscrow, uint256 amountFunded, uint16 aprBps, address indexed liquidityPoolManagerAddress)`** (`amountFunded` here is the 80% portion from the pool)

---

### Flow 6: Loan Repayment

Developers (or an automated system) make repayments, which are routed through `RepaymentRouter`.

#### Contract: `RepaymentRouter`

*   **Purpose:** Central point for handling loan repayments. It receives repayments, interacts with `FeeRouter` to calculate and process transaction and management fees, and routes the net repayment to the appropriate `ProjectVault` or `LiquidityPoolManager`.
*   **Frontend Interaction:** Developer interface for making repayments, or an automated system call.

**Functions:**

*   **`repay(uint256 projectId, uint256 amount)`** (Function name changed from `processRepayment` in some earlier internal docs, consistently `repay` in contract code)
    *   **Purpose:** Processes a loan repayment for a specific project.
    *   **Inputs:**
        *   `projectId` (`uint256`): The ID of the project for which repayment is made.
        *   `amount` (`uint256`): The total repayment amount in USDC.
    *   **Outputs:** None.
    *   **Frontend Interaction:** Developer repayment interface. Requires USDC approval from the payer (developer/project entity) to the `RepaymentRouter`.
    *   **Internal Calls & Logic:**
        1.  Pulls `amount` of USDC from `msg.sender` (payer).
        2.  Looks up the `fundingSourceAddress` and `poolId` for the `projectId`.
        3.  Calls `IFundingSource(fundingSourceAddress).getOutstandingPrincipal(poolId, projectId)` to fetch the current outstanding principal of the loan.
        4.  Calculates `txFee = FeeRouter.calculateTransactionFee(amount)`.
        5.  Calculates `mgmtFee = FeeRouter.calculateManagementFee(projectId, outstandingPrincipal)` (if `outstandingPrincipal > 0`).
        6.  `totalFeeCollected = txFee + mgmtFee`.
        7.  **Fee Handling:**
            *   If `totalFeeCollected >= amount`, the entire `amount` is transferred to `FeeRouter`, `FeeRouter.routeFees(amount)` is called, and the process may emit `RepaymentRouted` with zero principal/interest and exit.
            *   Otherwise, `totalFeeCollected` is transferred to `FeeRouter`, and `FeeRouter.routeFees(totalFeeCollected)` is called.
        8.  If `mgmtFee > 0`, `FeeRouter.updateLastMgmtFeeTimestamp(projectId)` is called.
        9.  `netRepaymentAmount = amount - totalFeeCollected`.
        10. Calls `IFundingSource(fundingSourceAddress).handleRepayment(poolId, projectId, netRepaymentAmount)`. This function on the target vault/LPM returns `(principalPaid, interestPaid)`.
        11. Emits `RepaymentRouted` event with gross amount, total fees, principal, and interest paid.

**Events:**

*   **`RepaymentRouted(uint256 indexed projectId, address indexed payer, uint256 totalAmountRepaid, uint256 feeAmount, uint256 principalAmount, uint256 interestAmount, address indexed fundingSource)`** (Event name updated from `RepaymentProcessed` in previous guide draft)
    *   **Purpose:** Signals that a repayment has been processed and routed, including fee details.
    *   **Frontend Interaction:** Confirm repayment, update loan status, display fee breakdown.

#### Contract: `FeeRouter`

*   **Purpose:** Calculates and distributes protocol fees.
*   **Frontend Interaction:** Primarily via `RepaymentRouter`. View functions can be used to display fee structures.

**Functions (relevant for viewing/calculation):**

*   **`calculateCapitalRaisingFee(uint256 projectId, address developer)`**
*   **`calculateManagementFee(uint256 projectId, uint256 outstandingPrincipal)`**
*   **`calculateTransactionFee(uint256 transactionAmount)`**
    *   **Frontend Interaction:** Display estimated fees before a transaction (e.g., before repayment).

*   **`getProjectFeeDetails(uint256 projectId)`**
    *   **Frontend Interaction:** Display detailed fee-related information for a project.
*   **`getNextPaymentInfo(uint256 projectId)`**

**Events:**

*   **`FeeRouted(address repaymentRouter, uint256 totalFeeAmount, uint256 protocolTreasuryAmount, uint256 carbonTreasuryAmount)`**
    *   **Frontend Interaction:** Could be used for admin dashboards to track fee flows.

#### Contract: `DirectProjectVault` (Instance) / `LiquidityPoolManager`

**Functions (called by `RepaymentRouter` via `IFundingSource` interface):**

*   **`handleRepayment(uint256 poolId, uint256 projectId, uint256 netAmountReceived)`**
    *   **Purpose:** Processes the net repayment amount received from the `RepaymentRouter`. Accrues interest (for Vaults), updates principal and interest repaid.
    *   **Outputs:** `(uint256 principalPaid, uint256 interestPaid)`
*   **`getOutstandingPrincipal(uint256 poolId, uint256 projectId)`** (View function)
    *   **Purpose:** Called by `RepaymentRouter` to get the outstanding principal for management fee calculation.
    *   **Outputs:** `uint256 outstandingPrincipal`

**Events (on `DirectProjectVault`):**

*   **`RepaymentReceived(uint256 projectId, address indexed payer, uint256 principalAmount, uint256 interestAmount)`**
    *   **Frontend Interaction:** Update outstanding loan balance, accrued interest, and amounts available for investor claims.

**Events (on `LiquidityPoolManager`):**

*   **`PoolRepaymentReceived(uint256 indexed poolId, uint256 indexed projectId, address indexed payer, uint256 principalReceived, uint256 interestReceived)`**

---

### Flow 7: Investor Claims (Direct Vault)

Investors claim their share of repaid principal and accrued yield from `DirectProjectVault` instances.

#### Contract: `DirectProjectVault` (Instance)

**Functions:**

*   **`claimablePrincipal(address investor)`**
    *   **Purpose:** Calculates the amount of principal an investor can currently claim.
    *   **Inputs:**
        *   `investor` (`address`): The investor's address.
    *   **Outputs:** `uint256` (claimable principal amount).
    *   **Frontend Interaction:** Display this amount to the investor.

*   **`claimableYield(address investor)`**
    *   **Purpose:** Calculates the amount of yield an investor can currently claim.
    *   **Inputs:**
        *   `investor` (`address`): The investor's address.
    *   **Outputs:** `uint256` (claimable yield amount).
    *   **Frontend Interaction:** Display this amount to the investor.

*   **`claimPrincipal()`**
    *   **Purpose:** Investor claims their available principal.
    *   **Inputs:** None (caller is the investor).
    *   **Outputs:** None.
    *   **Frontend Interaction:** Button for investors to claim principal.

*   **`claimYield()`**
    *   **Purpose:** Investor claims their available yield.
    *   **Inputs:** None (caller is the investor).
    *   **Outputs:** None.
    *   **Frontend Interaction:** Button for investors to claim yield.

*   **`redeem()`** (claims both principal and yield)

**Events:**

*   **`PrincipalClaimed(address indexed investor, uint256 amountClaimed)`**
    *   **Frontend Interaction:** Confirm principal claim, update investor's claimed amounts.
*   **`YieldClaimed(address indexed investor, uint256 amountClaimed)`**
    *   **Frontend Interaction:** Confirm yield claim, update investor's claimed amounts.

---

### Flow 8: Loan Closure

When a loan is fully repaid or its term ends and is settled.

#### Contract: `DirectProjectVault` / `LiquidityPoolManager`

**Functions:**

*   **`closeLoan()` (on `DirectProjectVault`)**
    *   **Purpose:** Marks the loan as closed. Typically called after full repayment.
    *   **Role Required:** `Constants.DEFAULT_ADMIN_ROLE` or `Constants.REPAYMENT_HANDLER_ROLE` (on the specific `DirectProjectVault` instance).
    *   **Internal Action:** Calls `DeveloperDepositEscrow.releaseDeposit(projectId)`.

**Events:**

*   **`LoanClosed(uint256 projectId, uint256 finalPrincipalRepaid, uint256 finalInterestAccrued)` (on `DirectProjectVault`)**
    *   **Frontend Interaction:** Update project status to "Loan Closed".
*   For `LiquidityPoolManager` funded loans, the `LoanRecord.isActive` flag is set to `false` upon full repayment within `handleRepayment`.

#### Contract: `DeveloperDepositEscrow`

**Functions (called by `DirectProjectVault` or Admin):**

*   **`releaseDeposit(uint256 projectId)`**
    *   **Purpose:** Releases the developer's deposit back to them.
    *   **Role Required (when called by `DirectProjectVault`):** The `DirectProjectVault` instance must have `Constants.RELEASER_ROLE` on `DeveloperDepositEscrow`.

**Events:**

*   **`DepositReleased(uint256 indexed projectId, address indexed developer, uint256 amount)`**

---

### Flow 9: Risk Oracle Interaction & Parameter Updates

The `RiskRateOracleAdapter` allows an authorized oracle to update risk parameters (like APR) for projects.

**Oracle Target Configuration:**
*   **For `DirectProjectVault` funded projects:** `ProjectFactory` automatically calls `RiskRateOracleAdapter.setTargetContract(projectId, directProjectVaultAddress, 0)` during vault creation.
*   **For `LiquidityPoolManager` funded projects:** `LiquidityPoolManager` automatically calls `RiskRateOracleAdapter.setTargetContract(projectId, liquidityPoolManagerAddress, poolId)` when it successfully funds a project.
*   **Permission Note:** These automated calls by `ProjectFactory` and `LiquidityPoolManager` to `RiskRateOracleAdapter.setTargetContract` are possible because `setTargetContract` is protected by `Constants.PROJECT_HANDLER_ROLE`, and both `ProjectFactory` and `LiquidityPoolManager` are granted this role on `RiskRateOracleAdapter` during deployment (as detailed in `role_granting.md`).

#### Contract: `RiskRateOracleAdapter`

*   **Purpose:** Serves as an on-chain interface for an off-chain oracle service or authorized admin to push risk parameter updates to funding contracts.
*   **Frontend Interaction (Admin Panel/Oracle Interface):** This section is primarily for an admin panel or a dedicated interface for the entity holding the `RISK_ORACLE_ROLE` or `DEFAULT_ADMIN_ROLE`.

**Functions (Configuration & Data Input - Admin/Oracle Role):**

*   **`setTargetContract(uint256 projectId, address targetContract, uint256 poolId)`**
    *   **Role Required:** `Constants.PROJECT_HANDLER_ROLE` (Typically called automatically by `ProjectFactory` or `LiquidityPoolManager`). Can also be called by any other address holding this role for manual configuration/updates.
*   **`pushRiskParams(uint256 projectId, uint16 aprBps, uint48 tenor)`**
    *   **Role Required:** `Constants.RISK_ORACLE_ROLE`.
*   **`getProjectRiskLevel(uint256 projectId)` / `setProjectRiskLevel(uint256 projectId, uint16 riskLevel)`**
    *   **Role Required:** `Constants.RISK_ORACLE_ROLE` for `setProjectRiskLevel`.

*(Other functions like `initialize`, `setAssessmentInterval`, `requestPeriodicAssessment`, `triggerBatchRiskAssessment`, and events `TargetContractSet`, `RiskParamsPushed`, etc., remain relevant as described in contract comments or previous guide versions.)*

This revised guide should better reflect the updated contract interactions.