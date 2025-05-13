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

*   **Action:** Core contracts are deployed and initialized by the admin/deployer.
*   **Frontend Relevance:** The frontend will need the addresses of these core contracts to interact with them. Roles are set up during initialization. The admin panel will be used for many of these initialization calls.

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

### Flow 2: Project Creation (Direct Vault via `ProjectFactory`)

This flow involves an admin or an authorized entity creating a new project funding vault.

#### Contract: `ProjectFactory`

*   **Purpose:** Creates instances of `DirectProjectVault` and associated `DevEscrow` contracts.
*   **Frontend Interaction:** An admin interface would allow users with appropriate permissions to initiate project creation.

**Functions:**

*   **`createProjectVault(address developer, uint256 projectId, uint256 financedAmount, uint48 loanTenor, uint16 initialAprBps, address depositEscrowAddress, uint256 developerDepositAmount)`**
    *   **Purpose:** Creates a new `DirectProjectVault` for a project, a `DevEscrow` for it, and sets up necessary links with other core contracts.
    *   **Role Required:** `Constants.DEFAULT_ADMIN_ROLE` (on `ProjectFactory`, as specific `CREATOR_ROLE` is not in `Constants.json`). The `ProjectFactory` contract itself needs appropriate roles on other contracts it calls (see internal calls).
    *   **Inputs:**
        *   `developer` (`address`): The developer's address for the project.
            *   Example: `"0xDevAddress..."`
        *   `projectId` (`uint256`): A unique ID for the project.
            *   Example: `"101"`
        *   `financedAmount` (`uint256`): The total amount to be financed for the project (USDC).
            *   Example: `"50000000000"` (for 50,000 USDC, assuming 6 decimals)
        *   `loanTenor` (`uint48`): Duration of the loan in seconds.
            *   Example: `"2592000"` (for 30 days)
        *   `initialAprBps` (`uint16`): Initial Annual Percentage Rate in Basis Points (1% = 100 BPS).
            *   Example: `"1000"` (for 10% APR)
        *   `depositEscrowAddress` (`address`): Address of the `DeveloperDepositEscrow` contract.
            *   Example: `"0xDeveloperDepositEscrowAddress..."`
        *   `developerDepositAmount` (`uint256`): The amount of deposit required from the developer.
            *   Example: `"10000000000"` (for 10,000 USDC)
    *   **Outputs:**
        *   `address`: The address of the newly created `DirectProjectVault`.
            *   Example: `"0xNewDirectProjectVaultAddress..."`
    *   **Frontend Interaction:** Admin panel form for project creation. On success, the frontend should listen for the `ProjectVaultCreated` event.
    *   **Internal Calls (by `ProjectFactory`):**
        1.  Deploys new `DirectProjectVault`.
        2.  Deploys new `DevEscrow`.
        3.  Calls `DirectProjectVault.initialize(...)`.
        4.  Calls `DevEscrow.initialize(...)`.
        5.  Calls `DeveloperDepositEscrow.fundDeposit(projectId, developer, developerDepositAmount)`. (Requires `ProjectFactory` to have `Constants.DEPOSIT_FUNDER_ROLE` on `DeveloperDepositEscrow`)
        6.  Calls `FeeRouter.setProjectDetails(...)`. (Requires `ProjectFactory` to have `Constants.PROJECT_HANDLER_ROLE` on `FeeRouter`)
        7.  Calls `RepaymentRouter.registerProject(...)`. (Requires `ProjectFactory` to have `Constants.PROJECT_HANDLER_ROLE` on `RepaymentRouter`)
        8.  Calls `DeveloperRegistry.incrementFundedCounter(developer)`. (Requires `ProjectFactory` to have `Constants.PROJECT_HANDLER_ROLE` on `DeveloperRegistry`)
        9.  Grants the new `DirectProjectVault` instance the `Constants.RELEASER_ROLE` on `DeveloperDepositEscrow`. (Requires `ProjectFactory` to be admin of `RELEASER_ROLE` on `DeveloperDepositEscrow` - achieved by making `DEPOSIT_FUNDER_ROLE` the admin of `RELEASER_ROLE`).

**Events:**

*   **`ProjectVaultCreated(uint256 projectId, address indexed vaultAddress, address indexed developer, address devEscrowAddress, uint256 loanAmount)`**
    *   **Purpose:** Signals that a new project vault and its associated escrow have been created.
    *   **Data:**
        *   `projectId` (`uint256`): The ID of the project.
        *   `vaultAddress` (`address`): Address of the new `DirectProjectVault`.
        *   `developer` (`address`): Address of the developer.
        *   `devEscrowAddress` (`address`): Address of the new `DevEscrow` for this project.
        *   `loanAmount` (`uint256`): The loan amount for the project.
    *   **Frontend Interaction:** Store the `vaultAddress` and `devEscrowAddress` for the project. Update UI to show the new project available for investment.

---

### Flow 3: Investing in a Project (Direct Vault)

Investors interact with a specific `DirectProjectVault` instance.

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
    *   **Purpose:** Gets the total amount of USDC currently invested in the vault.
    *   **Inputs:** None.
    *   **Outputs:**
        *   `uint256`: Total assets invested.
            *   Example: `"25000000000"`
    *   **Frontend Interaction:** Display progress towards funding goal.

*   **`getLoanAmount()`**
    *   **Purpose:** Gets the target loan amount for this project.
    *   **Inputs:** None.
    *   **Outputs:**
        *   `uint256`: Target loan amount.
            *   Example: `"50000000000"`
    *   **Frontend Interaction:** Display funding goal.

*   **`isFundingClosed()`**
    *   **Purpose:** Checks if the funding period for this vault is closed.
    *   **Inputs:** None.
    *   **Outputs:**
        *   `bool`: `true` if funding is closed, `false` otherwise.
    *   **Frontend Interaction:** Disable investment if `true`.

**Events:**

*   **`Invested(address indexed investor, uint256 amountInvested, uint256 totalAssetsInvested)`**
    *   **Purpose:** Signals that an investor has successfully invested.
    *   **Data:**
        *   `investor` (`address`): The investor's address.
        *   `amountInvested` (`uint256`): The amount invested in this transaction.
        *   `totalAssetsInvested` (`uint256`): The new total amount invested in the vault.
    *   **Frontend Interaction:** Confirm investment to the user, update total investment display.

---

### Flow 4: Funding Closure & Drawdown (Direct Vault)

Once the funding goal is met or an admin closes it, the funds are made available to the developer via the `DevEscrow`.

#### Contract: `DirectProjectVault` (Instance)

**Functions:**

*   **`closeFundingManually()`**
    *   **Purpose:** Manually closes the funding period. Called by an admin/authorized role. (Can also be triggered if `invest` hits the `loanAmount`).
    *   **Role Required:** `Constants.DEFAULT_ADMIN_ROLE` (on the specific `DirectProjectVault` instance).
    *   **Inputs:** None.
    *   **Outputs:** None.
    *   **Frontend Interaction:** Admin action.
    *   **Internal Action:** Sets `fundingClosed = true`, `loanStartTime = block.timestamp`. Calls `DeveloperDepositEscrow.transferDepositToProject(projectId)` and then `devEscrow.triggerDrawdown(totalAssetsInvested)`.

**Events:**

*   **`FundingClosed(uint256 projectId, uint256 totalAssetsInvested)`**
    *   **Purpose:** Signals that the funding period for the project has closed.
    *   **Data:**
        *   `projectId` (`uint256`): Project ID.
        *   `totalAssetsInvested` (`uint256`): Total funds raised.
    *   **Frontend Interaction:** Update project status to "Funding Closed", "Loan Active".

#### Contract: `DevEscrow` (Instance for the Project)

*   **Purpose:** Record-keeping for funds allocated and disbursed to the developer. In the "direct funding" model, it doesn't hold funds itself but is notified of transfers.
*   **Frontend Interaction:** Mostly indirect; status updates based on its events.

**Functions:**

*   **`triggerDrawdown(uint256 amount)` (Called by `DirectProjectVault` via `closeFundingManually`)**
    *   **Purpose:** The `DirectProjectVault` calls this on the `DevEscrow` to signal that the developer's deposit has been transferred (if applicable to the vault) and the loan funds are ready for the developer (or have been sent). This function in `DevEscrow` now primarily serves to call `notifyFundingComplete` on itself, reflecting the new direct-to-developer funding model.
    *   **Inputs:**
        *   `amount` (`uint256`): The amount considered "drawn down" for the project (typically `totalAssetsInvested` from the vault).
    *   **Outputs:** None.

*   **`notifyFundingComplete(uint256 amount)` (Called by `ProjectFactory`, `LiquidityPoolManager`, or by `triggerDrawdown` in `DevEscrow`)**
    *   **Purpose:** Signals that funds have been *sent* to the developer and the funding/loan is active.
    *   **Inputs:**
        *   `amount` (`uint256`): The amount successfully transferred to the developer.
    *   **Outputs:** None.
    *   **Frontend Interaction:** An admin action (if called by Factory/LPM) or an internal trigger.

**Events:**

*   **`FundingComplete(address indexed developer, uint256 amount)` (on `DevEscrow`)**
    *   **Purpose:** Emitted when `notifyFundingComplete` is successfully called, confirming funds are with the developer.
    *   **Data:**
        *   `developer` (`address`): Developer's address.
        *   `amount` (`uint256`): Amount sent to the developer.
    *   **Frontend Interaction:** Update project status to "Funds Disbursed" / "Loan Active".

*   **`DrawdownExecuted(uint256 projectId, address indexed developer, uint256 amount)` (on `DirectProjectVault`)**
    *   **Purpose:** Signals that the drawdown process (which includes transferring the dev deposit and notifying the DevEscrow) has been executed by the vault.
    *   **Data:**
        *   `projectId` (`uint256`): Project ID.
        *   `developer` (`address`): Developer's address.
        *   `amount` (`uint256`): Amount involved in the drawdown (typically `totalAssetsInvested`).
    *   **Frontend Interaction:** Confirm to admin that drawdown logic was triggered.

#### Contract: `DeveloperDepositEscrow`

**Functions (called by `ProjectFactory` during `createProjectVault` or by `DirectProjectVault` during `closeFundingManually`):**

*   **`fundDeposit(uint256 projectId, address developer, uint256 amount)`**
    *   **Purpose:** Called by `ProjectFactory` to lock the developer's deposit.
    *   **Role Required (when called by `ProjectFactory`):** The `ProjectFactory` contract must have `Constants.DEPOSIT_FUNDER_ROLE` on `DeveloperDepositEscrow`.
    *   **Inputs:** See `ProjectFactory.createProjectVault`'s relevant parameters.
    *   **Frontend Interaction:** Indirect, via `ProjectFactory`.

*   **`transferDepositToProject(uint256 projectId)`**
    *   **Purpose:** Called by `DirectProjectVault` (or potentially an admin role for pool-funded projects) when the main loan is funded and disbursed to the developer. This function transfers the developer's 20% deposit to the project itself (e.g., to the `DirectProjectVault` contract, which then includes it in the `totalDebt` and makes it part of the funds managed by the vault for the developer's project usage).
    *   **Role Required (when called by `DirectProjectVault`):** The `DirectProjectVault` instance needs `Constants.RELEASER_ROLE` on `DeveloperDepositEscrow` (granted by `ProjectFactory` during vault creation).
    *   **Inputs:**
        *   `projectId` (`uint256`): The ID of the project.
    *   **Outputs:**
        *   `uint256`: The amount transferred.
    *   **Frontend Interaction:** Triggered by `DirectProjectVault.closeFundingManually`.

**Events:**

*   **`DepositFunded(uint256 indexed projectId, address indexed developer, uint256 amount)`**
    *   **Frontend Interaction:** Confirm deposit locked for the project.
*   **`DepositReleased(uint256 indexed projectId, address indexed developer, uint256 amount)`** (See Loan Closure)
*   **`DepositSlashed(...)`** (Admin action, not primary user flow)

---

### Flow 5: Project Funding (Liquidity Pool via `LiquidityPoolManager`)

This flow involves LPs investing in a general pool, and then the `LiquidityPoolManager` allocating funds from that pool to specific projects.

#### Contract: `LiquidityPoolManager`

*   **Purpose:** Manages creation of and investments into liquidity pools, and allocates funds from these pools to projects.
*   **Frontend Interaction:** LPs invest/redeem from pools. Admins/System allocate funds to projects.

**Functions:**

*   **`createLiquidityPool(address usdcToken, address feeRouter, address developerRegistry, address repaymentRouter, address devEscrowImplementation, address developerDepositEscrow)`**
    *   **Purpose:** Admin creates a new liquidity pool.
    *   **Role Required:** `Constants.DEFAULT_ADMIN_ROLE` (on `LiquidityPoolManager`, as specific `POOL_CREATOR_ROLE` is not in `Constants.json`).
    *   **Inputs:** Addresses of various system contracts.
    *   **Outputs:** `address` of the new `LiquidityPool`.
    *   **Frontend Interaction:** Admin interface.

*   **`investInPool(uint256 poolId, uint256 amount)`**
    *   **Purpose:** Investor invests USDC into a specific liquidity pool.
    *   **Inputs:**
        *   `poolId` (`uint256`): ID of the pool to invest in.
            *   Example: `"1"`
        *   `amount` (`uint256`): Amount of USDC to invest.
            *   Example: `"5000000000"` (for 5,000 USDC)
    *   **Outputs:** None.
    *   **Frontend Interaction:** LP investment interface. Requires USDC approval.

*   **`redeemFromPool(uint256 poolId, uint256 shares)`**
    *   **Purpose:** Investor redeems their shares from a pool for USDC.
    *   **Inputs:**
        *   `poolId` (`uint256`): ID of the pool.
        *   `shares` (`uint256`): Amount of pool shares to redeem.
            *   Example: `"4950000000"`
    *   **Outputs:** None.
    *   **Frontend Interaction:** LP redemption interface.

*   **`allocateFundsToProject(uint256 poolId, uint256 projectId, address developer, uint256 financedAmount, uint48 loanTenor, uint16 initialAprBps, uint256 developerDepositAmount)`**
    *   **Purpose:** Allocates funds from a pool to a specific project. This involves creating a `DevEscrow` for the project, transferring funds directly to the developer, and notifying relevant contracts.
    *   **Role Required:** `Constants.DEFAULT_ADMIN_ROLE` (on `LiquidityPoolManager`). The `LiquidityPoolManager` contract itself needs appropriate roles on other contracts it calls.
    *   **Inputs:** Similar to `ProjectFactory.createProjectVault` but specifies `poolId`.
        *   `poolId` (`uint256`): ID of the funding pool.
        *   ... other params like `projectId`, `developer`, `financedAmount`, etc.
    *   **Outputs:** `address` of the new `DevEscrow` contract for the project.
    *   **Frontend Interaction:** Admin/System action.
    *   **Internal Calls:**
        1.  Deploys new `DevEscrow`.
        2.  Calls `DevEscrow.initialize(...)`.
        3.  *Transfers `financedAmount` directly from `LiquidityPool` to `developer`.*
        4.  Calls `DevEscrow.notifyFundingComplete(financedAmount)`.
        5.  Calls `DeveloperDepositEscrow.fundDeposit(...)`. (Requires `LiquidityPoolManager` to have `Constants.DEPOSIT_FUNDER_ROLE` on `DeveloperDepositEscrow`)
        6.  Calls `FeeRouter.setProjectDetails(...)`. (Requires `LiquidityPoolManager` to have `Constants.PROJECT_HANDLER_ROLE` on `FeeRouter`)
        7.  Calls `RepaymentRouter.registerProject(...)`. (Requires `LiquidityPoolManager` to have `Constants.PROJECT_HANDLER_ROLE` on `RepaymentRouter`)
        8.  Calls `DeveloperRegistry.incrementFundedCounter(developer)`. (Requires `LiquidityPoolManager` to have `Constants.PROJECT_HANDLER_ROLE` on `DeveloperRegistry`)

*   **`getPoolDetails(uint256 poolId)`**
    *   **Frontend Interaction:** Display pool information (total assets, total shares, etc.).

*   **`getInvestorPoolBalance(uint256 poolId, address investor)`**
    *   **Frontend Interaction:** Display an investor's share balance in a pool.

**Events:**

*   **`PoolCreated(uint256 indexed poolId, address indexed poolAddress, address usdcToken)`**
*   **`InvestmentMade(uint256 indexed poolId, address indexed investor, uint256 amountDeposited, uint256 sharesReceived)`**
*   **`RedemptionMade(uint256 indexed poolId, address indexed investor, uint256 sharesRedeemed, uint256 amountWithdrawn)`**
*   **`FundsAllocatedToProject(uint256 indexed poolId, uint256 indexed projectId, address developer, uint256 amountAllocated, address devEscrowAddress)`**

---

### Flow 6: Loan Repayment

Developers (or an automated system) make repayments, which are routed through `RepaymentRouter`.

#### Contract: `RepaymentRouter`

*   **Purpose:** Central point for handling loan repayments. It receives repayments and routes them to the appropriate `ProjectVault` or `LiquidityPoolManager`, and also triggers fee processing via `FeeRouter`.
*   **Frontend Interaction:** Developer interface for making repayments, or an automated system call.

**Functions:**

*   **`processRepayment(uint256 projectId, uint256 amount)`**
    *   **Purpose:** Processes a loan repayment for a specific project.
    *   **Inputs:**
        *   `projectId` (`uint256`): The ID of the project for which repayment is made.
            *   Example: `"101"`
        *   `amount` (`uint256`): The total repayment amount in USDC.
            *   Example: `"550000000"` (for 550 USDC)
    *   **Outputs:** None.
    *   **Frontend Interaction:** Developer repayment interface. Requires USDC approval from the payer (developer/project entity) to the `RepaymentRouter`.
    *   **Internal Calls:**
        1.  Calculates transaction fee using `FeeRouter.calculateTransactionFee()`.
        2.  Calculates management fee using `FeeRouter.calculateManagementFee()`.
        3.  Transfers USDC for fees from payer to `FeeRouter`.
        4.  Calls `FeeRouter.routeFees()` with the total fee amount.
        5.  Calls `FeeRouter.updateLastMgmtFeeTimestamp()`.
        6.  Determines if the project is vault-funded or pool-funded.
        7.  Calls `DirectProjectVault.handleRepayment()` or `LiquidityPoolManager.processRepaymentToPool()` with the net repayment amount (total - fees).
        8.  Calls `FeeRouter.updatePaymentSchedule()`.

**Events:**

*   **`RepaymentProcessed(uint256 indexed projectId, address indexed payer, uint256 totalAmountPaid, uint256 netAmountToProject, uint256 feeAmount)`**
    *   **Purpose:** Signals that a repayment has been processed.
    *   **Frontend Interaction:** Confirm repayment, update loan status.

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

#### Contract: `DirectProjectVault` (Instance)

**Functions (called by `RepaymentRouter`):**

*   **`handleRepayment(uint256, uint256 _projectId, uint256 netAmountReceived)`** (Note: ABI shows first param unnamed, likely `msg.sender` from router)
    *   **Purpose:** Processes the net repayment amount received from the `RepaymentRouter`. Accrues interest, updates principal and interest repaid, and distributes funds internally for investor claims.
    *   **Outputs:**
        *   `principalPaid` (`uint256`)
        *   `interestPaid` (`uint256`)

**Events:**

*   **`RepaymentReceived(uint256 projectId, address indexed payer, uint256 principalAmount, uint256 interestAmount)`**
    *   **Frontend Interaction:** Update outstanding loan balance, accrued interest, and amounts available for investor claims.

#### Contract: `LiquidityPoolManager`

**Functions (called by `RepaymentRouter`):**

*   **`processRepaymentToPool(uint256 poolId, uint256 projectId, uint256 amount)`**
    *   **Purpose:** Handles repayments for projects funded by a liquidity pool.
    *   **Frontend Interaction:** Indirectly via `RepaymentRouter`.

**Events:**

*   **`RepaymentProcessedToPool(uint256 indexed poolId, uint256 indexed projectId, uint256 amountRepaid)`**

---

### Flow 7: Investor Claims (Direct Vault)

Investors claim their share of repaid principal and accrued yield.

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

*   **`redeem()`**
    *   **Purpose:** Investor claims both available principal and yield in one transaction.
    *   **Inputs:** None (caller is the investor).
    *   **Outputs:**
        *   `principalAmount` (`uint256`)
        *   `yieldAmount` (`uint256`)
    *   **Frontend Interaction:** Button for investors to redeem all claimable funds.

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
    *   **Role Required:** `Constants.DEFAULT_ADMIN_ROLE` (on the specific `DirectProjectVault` instance).
    *   **Inputs:** None.
    *   **Outputs:** None.
    *   **Frontend Interaction:** Admin action or triggered by full repayment logic.
    *   **Internal Action:** Calls `DeveloperDepositEscrow.releaseDeposit(projectId)`.

**Events:**

*   **`LoanClosed(uint256 projectId, uint256 finalPrincipalRepaid, uint256 finalInterestAccrued)` (on `DirectProjectVault`)**
    *   **Frontend Interaction:** Update project status to "Loan Closed".

#### Contract: `DeveloperDepositEscrow`

**Functions (called by `DirectProjectVault` or Admin):**

*   **`releaseDeposit(uint256 projectId)`**
    *   **Purpose:** Releases the developer's deposit back to them.
    *   **Role Required (when called by `DirectProjectVault`):** The `DirectProjectVault` instance must have `Constants.RELEASER_ROLE` on `DeveloperDepositEscrow`.
    *   **Role Required (when called by Admin):** `Constants.RELEASER_ROLE` on `DeveloperDepositEscrow`.
    *   **Inputs:**
        *   `projectId` (`uint256`): The project ID.
    *   **Outputs:** None.
    *   **Frontend Interaction:** Triggered by `DirectProjectVault.closeLoan()`.

**Events:**

*   **`DepositReleased(uint256 indexed projectId, address indexed developer, uint256 amount)`**
    *   **Frontend Interaction:** Notify developer/admin that deposit has been released.

---

### Flow 9: Risk Oracle Interaction & Parameter Updates

The `RiskRateOracleAdapter` allows an authorized oracle to update risk parameters (like APR) for projects. This flow details interactions primarily driven by an oracle role or an admin acting as one.

#### Contract: `RiskRateOracleAdapter`

*   **Purpose:** Serves as an on-chain interface for an off-chain oracle service or authorized admin to push risk parameter updates to funding contracts (`DirectProjectVault` or `LiquidityPoolManager`).
*   **Frontend Interaction (Admin Panel/Oracle Interface):** This section is primarily for an admin panel or a dedicated interface for the entity holding the `RISK_ORACLE_ROLE` or `DEFAULT_ADMIN_ROLE`.
*   **Frontend Interaction (User Requesting Admin Service):** Regular users do not directly interact with these functions. Project risk parameters are typically updated based on off-chain analysis or automated processes managed by the oracle/admin.

**Functions (Configuration & Data Input - Admin/Oracle Role):**

*   **`initialize(address _admin)`**
    *   **Purpose:** Initializes the contract, setting the initial admin. Called once upon deployment.
    *   **Role Required:** Deployer.
    *   **Inputs:**
        *   `_admin` (`address`): The address to grant `DEFAULT_ADMIN_ROLE`, `UPGRADER_ROLE`, and `ORACLE_CONFIG_ROLE` (or similar, based on your `Constants.sol`).
            *   Example: `"0xAdminAddress..."`
    *   **Outputs:** None.
    *   **Admin Panel Interaction:** Part of the initial deployment and setup script.

*   **`setTargetContract(uint256 projectId, address targetContract, uint256 poolId)`**
    *   **Purpose:** Links a `projectId` to its managing contract (either a `DirectProjectVault` or the `LiquidityPoolManager`) and, if applicable, its `poolId`. This is crucial for `pushRiskParams` to know where to send updates.
    *   **Role Required:** `Constants.DEFAULT_ADMIN_ROLE` (on `RiskRateOracleAdapter`, as specific `CONFIG_ROLE` is not in `Constants.json`).
    *   **Inputs:**
        *   `projectId` (`uint256`): The unique ID of the project.
            *   Example: `"101"`
        *   `targetContract` (`address`): The address of the `DirectProjectVault` or `LiquidityPoolManager` managing this project.
            *   Example: `"0xDirectProjectVaultAddress..."`
        *   `poolId` (`uint256`): If `targetContract` is `LiquidityPoolManager`, this is the ID of the pool. Otherwise, set to `0`.
            *   Example: `"0"` (for a Direct Vault) or `"1"` (for a pool-funded project)
    *   **Outputs:** None.
    *   **Admin Panel Interaction:** An interface where an admin can associate a new project (created by `ProjectFactory` or `LiquidityPoolManager`) with this oracle adapter. This is typically done after a project's funding vehicle is created.

*   **`setProjectRiskLevel(uint256 projectId, uint16 riskLevel)`**
    *   **Purpose:** Allows an authorized entity (`RISK_ORACLE_ROLE`) to set/update a specific risk level for a project. This risk level might be used by off-chain logic or influence on-chain parameters like APR indirectly.
    *   **Role Required:** `Constants.RISK_ORACLE_ROLE` (on `RiskRateOracleAdapter`).
    *   **Inputs:**
        *   `projectId` (`uint256`): The project ID.
            *   Example: `"101"`
        *   `riskLevel` (`uint16`): The risk level (e.g., 1-5, or based on your defined scale).
            *   Example: `"2"` (representing a specific risk category)
    *   **Outputs:** None.
    *   **Admin Panel Interaction:** An interface for the risk oracle or a designated admin to input/update the risk level for a project after an assessment.

*   **`pushRiskParams(uint256 projectId, uint16 aprBps, uint48 tenor)`**
    *   **Purpose:** The primary function for the `RISK_ORACLE_ROLE` to push updated risk parameters (APR and optionally tenor) to the project's funding contract.
    *   **Role Required:** `Constants.RISK_ORACLE_ROLE` (on `RiskRateOracleAdapter`).
    *   **Inputs:**
        *   `projectId` (`uint256`): The project ID.
            *   Example: `"101"`
        *   `aprBps` (`uint16`): The new Annual Percentage Rate in Basis Points.
            *   Example: `"1250"` (for 12.50% APR)
        *   `tenor` (`uint48`): The new loan tenor in seconds. (Use `0` if tenor is not being updated or is immutable post-funding).
            *   Example: `"2592000"` (30 days) or `"0"`
    *   **Outputs:** None.
    *   **Admin Panel Interaction:** The core function for the risk oracle to update a project's terms. The interface should allow selection of `projectId` and input of new `aprBps` and `tenor`.
    *   **Internal Action:** This function will look up the `targetContract` for the `projectId` and call `updateRiskParams` on that `DirectProjectVault` or `LiquidityPoolManager`.

*   **`setAssessmentInterval(uint256 newInterval)`**
    *   **Purpose:** Admin sets the default interval (in seconds) for how often periodic risk assessments should ideally occur.
    *   **Role Required:** `Constants.DEFAULT_ADMIN_ROLE` (on `RiskRateOracleAdapter`).
    *   **Inputs:**
        *   `newInterval` (`uint256`): The new interval in seconds.
            *   Example: `"604800"` (for 1 week)
    *   **Outputs:** None.
    *   **Admin Panel Interaction:** A settings page in the admin panel.

**Functions (Triggering & Viewing - Admin/Oracle Role):**

*   **`requestPeriodicAssessment(uint256 projectId)`**
    *   **Purpose:** An authorized entity (`RISK_ORACLE_ROLE`) can request an assessment if the `assessmentInterval` has passed. Emits an event that an off-chain oracle service would listen to, prompting it to perform an assessment and potentially call `pushRiskParams`.
    *   **Role Required:** `Constants.RISK_ORACLE_ROLE` (on `RiskRateOracleAdapter`).
    *   **Inputs:**
        *   `projectId` (`uint256`): The project to assess.
            *   Example: `"101"`
    *   **Outputs:** None.
    *   **Admin Panel Interaction:** An interface for the oracle/admin to manually trigger the assessment request for a specific project if needed, or this could be part of an automated off-chain job.

*   **`triggerBatchRiskAssessment()`**
    *   **Purpose:** Admin/`RISK_ORACLE_ROLE` can trigger a batch assessment. This emits an event for an off-chain service to process assessments for multiple (or all due) projects.
    *   **Role Required:** `Constants.RISK_ORACLE_ROLE` (on `RiskRateOracleAdapter`).
    *   **Inputs:** None.
    *   **Outputs:** None.
    *   **Admin Panel Interaction:** A button in the admin interface for batch operations, or an automated job.

*   **`getProjectRiskLevel(uint256 projectId)`** (View)
    *   **Frontend Interaction:** Display current risk level on a project's detail page in the admin panel.

*   **`getTargetContract(uint256 projectId)`** (View)
    *   **Frontend Interaction:** Admin panel reference.

*   **`getPoolId(uint256 projectId)`** (View)
    *   **Frontend Interaction:** Admin panel reference, especially if the target is `LiquidityPoolManager`.

*   **`assessmentInterval()`** (View)
*   **`lastAssessmentTimestamp(uint256 projectId)`** (View)
    *   **Frontend Interaction:** Display for informational purposes in the admin panel or for oracle interfaces to determine if a new assessment is due.

**Events (Relevant to Admin/Oracle Actions):**

*   **`TargetContractSet(uint256 indexed projectId, address indexed targetContract, address indexed setter, uint256 poolId)`** (*Assuming poolId is added based on setTargetContract params*)
    *   **Purpose:** Confirms a project has been linked to its funding contract and pool (if any).
    *   **Admin Panel Interaction:** Log this event for audit trails. Update UI to show the project is configured for risk updates.

*   **`ProjectRiskLevelSet(uint256 indexed projectId, uint16 riskLevel)`**
    *   **Purpose:** Confirms a new risk level has been recorded for a project.
    *   **Admin Panel Interaction:** Update UI in the admin panel showing the project's current risk level.

*   **`RiskParamsPushed(uint256 indexed projectId, address indexed targetContract, address indexed oracle, uint16 aprBps, uint48 tenor)`**
    *   **Purpose:** Confirms that new risk parameters have been attempted to be pushed to the target contract.
    *   **Admin Panel Interaction:** Log for auditing. The frontend should also listen for corresponding events from the `DirectProjectVault` (`RiskParamsUpdated`) or `LiquidityPoolManager` to confirm the update was accepted by the target.

*   **`PeriodicAssessmentRequested(uint256 indexed projectId, uint256 timestamp, address targetContract, uint256 poolId)`**
    *   **Purpose:** Signals that an off-chain assessment for a project should be initiated.
    *   **Admin Panel Interaction:** Could update a project's status to "Assessment Requested" or be used by an off-chain oracle monitoring system.

*   **`AssessmentIntervalUpdated(uint256 oldInterval, uint256 newInterval)`**
*   **`BatchRiskAssessmentTriggered(uint256 timestamp)`**
    *   **Admin Panel Interaction:** Log these for admin audit.

---

### Flow 10: Advanced Admin & Governance Operations

This section covers administrative functions across various contracts, typically managed through an admin panel.

#### A. Role Management (General - Applicable to most contracts)

*   **Contracts:** `DeveloperRegistry`, `DeveloperDepositEscrow`, `DirectProjectVault`, `LiquidityPoolManager`, `FeeRouter`, `RiskRateOracleAdapter`, `MockUSDC`, `PausableGovernor`.
*   **Purpose:** Manage permissions for different administrative actions.
*   **Frontend Interaction (Admin Panel):** A dedicated section for role management. Admins with `DEFAULT_ADMIN_ROLE` (or specific admin roles for a particular role) can grant or revoke roles for other addresses.
*   **Frontend Interaction (User Requesting Admin Service):** Users don't directly request roles. Access is determined by their function within the platform (e.g., a KYC officer gets `KYC_ADMIN_ROLE`).

**Common Functions:**

*   **`grantRole(bytes32 role, address account)`**
    *   **Purpose:** Grants a specific role to an account.
    *   **Role Required:** Admin of the role being granted (often `DEFAULT_ADMIN_ROLE` for the contract, which is admin of all other roles within it by default in OpenZeppelin's AccessControl).
    *   **Inputs:**
        *   `role` (`bytes32`): The `bytes32` value of the role name (e.g., from `Constants.MINTER_ROLE()`).
        *   `account` (`address`): The address to grant the role to.
            *   Example: `"0xMinterAddress..."`
    *   **Outputs:** None.
    *   **Admin Panel Interaction:** Select role, input address, execute.

*   **`revokeRole(bytes32 role, address account)`**
    *   **Purpose:** Revokes a role from an account.
    *   **Role Required:** Admin of the role being revoked (often `DEFAULT_ADMIN_ROLE` for the contract).
    *   **Inputs:** Same as `grantRole`.
    *   **Outputs:** None.
    *   **Admin Panel Interaction:** Select role, input address, execute.

*   **`renounceRole(bytes32 role, address callerConfirmation)`**
    *   **Purpose:** Allows an account to renounce a role they possess.
    *   **Role Required:** The account must possess the role and be the `callerConfirmation`.
    *   **Inputs:**
        *   `role` (`bytes32`): The role to renounce.
        *   `callerConfirmation` (`address`): Must be `msg.sender`.
    *   **Outputs:** None.
    *   **Admin Panel Interaction:** An admin might use this for their own address if needed, or a user might have a "renounce my role" button if they have specific, renounceable roles.

*   **`getRoleAdmin(bytes32 role)`** (View)
*   **`getRoleMember(bytes32 role, uint256 index)`** (View)
*   **`getRoleMemberCount(bytes32 role)`** (View)
*   **`getRoleMembers(bytes32 role)`** (View)
*   **`hasRole(bytes32 role, address account)`** (View)
    *   **Admin Panel Interaction:** Display role memberships and admins for auditing and management.

**Common Events:**

*   **`RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole)`**
*   **`RoleGranted(bytes32 indexed role, address indexed account, address indexed sender)`**
*   **`RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender)`**
    *   **Admin Panel Interaction:** Log these events for audit trails. Update UI to reflect role changes.

#### B. Pausing and Unpausing Contracts (General)

*   **Contracts:** `DeveloperRegistry`, `DeveloperDepositEscrow`, `DirectProjectVault`, `LiquidityPoolManager` (and its individual pools), `DevEscrow`, `RiskRateOracleAdapter`.
*   **Purpose:** Temporarily halt certain operations on a contract in case of emergencies or upgrades.
*   **Frontend Interaction (Admin Panel):** Buttons to pause/unpause specific contracts.
*   **Frontend Interaction (User Requesting Admin Service):** Users don't request this. This is a high-level admin action.

**Common Functions:**

*   **`pause()`**
    *   **Purpose:** Pauses the contract.
    *   **Role Required:** `Constants.PAUSER_ROLE`.
    *   **Inputs:** None.
    *   **Outputs:** None.
    *   **Admin Panel Interaction:** "Pause Contract" button.

*   **`unpause()`**
    *   **Purpose:** Unpauses the contract.
    *   **Role Required:** `Constants.PAUSER_ROLE`.
    *   **Inputs:** None.
    *   **Outputs:** None.
    *   **Admin Panel Interaction:** "Unpause Contract" button.

*   **`paused()`** (View)
    *   **Purpose:** Checks if the contract is currently paused.
    *   **Inputs:** None.
    *   **Outputs:** `bool`.
    *   **Admin Panel Interaction:** Display current pause status.

**Common Events:**

*   **`Paused(address account)`**
*   **`Unpaused(address account)`**
    *   **Admin Panel Interaction:** Log for audit. Update UI to show contract status.

#### C. `DeveloperDepositEscrow` Admin Functions

*   **Purpose:** Administrative actions specific to managing developer security deposits.
*   **Frontend Interaction (Admin Panel):** Interface for slashing deposits in case of default.
*   **Frontend Interaction (User Requesting Admin Service):** A project stakeholder or system event might report a default, leading an admin to investigate and potentially slash a deposit.

**Functions:**

*   **`slashDeposit(uint256 projectId, address feeRecipient)`**
    *   **Purpose:** Slashes a developer's deposit, transferring it to a `feeRecipient`.
    *   **Role Required:** `Constants.SLASHER_ROLE` (on `DeveloperDepositEscrow`).
    *   **Inputs:**
        *   `projectId` (`uint256`): The ID of the project whose deposit is to be slashed.
            *   Example: `"101"`
        *   `feeRecipient` (`address`): The address to receive the slashed funds (e.g., protocol treasury).
            *   Example: `"0xProtocolTreasuryAddress..."`
    *   **Outputs:** None.
    *   **Admin Panel Interaction:** Select project, confirm slashing action, specify recipient.

**Events:**

*   **`DepositSlashed(uint256 indexed projectId, address indexed developer, uint256 amount, address recipient)`**
    *   **Admin Panel Interaction:** Log for audit. Update project status to reflect deposit slashed.

#### D. `FeeRouter` Admin Functions

*   **Purpose:** Configuration of fee parameters and treasury addresses.
*   **Frontend Interaction (Admin Panel):** Settings page for updating treasury addresses and potentially fee constants if they become configurable.
*   **Frontend Interaction (User Requesting Admin Service):** Not applicable for direct user requests.

**Functions:**

*   **`setProtocolTreasury(address _newTreasury)`**
    *   **Purpose:** Updates the protocol treasury address.
    *   **Role Required:** `Constants.DEFAULT_ADMIN_ROLE` (on `FeeRouter`).
    *   **Inputs:**
        *   `_newTreasury` (`address`): The new protocol treasury address.
            *   Example: `"0xNewProtocolTreasury..."`
    *   **Outputs:** None.
    *   **Admin Panel Interaction:** Input field for new treasury address.

*   **`setCarbonTreasury(address _newTreasury)`**
    *   **Purpose:** Updates the carbon treasury address.
    *   **Role Required:** `Constants.DEFAULT_ADMIN_ROLE` (on `FeeRouter`).
    *   **Inputs:**
        *   `_newTreasury` (`address`): The new carbon treasury address.
            *   Example: `"0xNewCarbonTreasury..."`
    *   **Outputs:** None.
    *   **Admin Panel Interaction:** Input field for new carbon treasury address.

*   **`setProjectDetails(uint256 projectId, uint256 loanAmount, address developer, uint64 creationTime)`**
    *   **Purpose:** Sets or updates project details used for fee calculations. Called by `ProjectFactory` or `LiquidityPoolManager` during project setup.
    *   **Role Required:** `Constants.PROJECT_HANDLER_ROLE` (granted to `ProjectFactory` and `LiquidityPoolManager` on `FeeRouter`).
    *   **Inputs:**
        *   `projectId` (`uint256`): Example: `"101"`
        *   `loanAmount` (`uint256`): Example: `"50000000000"`
        *   `developer` (`address`): Example: `"0xDevAddress..."`
        *   `creationTime` (`uint64`): Timestamp of project/loan creation. Example: current block timestamp.
    *   **Outputs:** None.
    *   **Admin Panel Interaction:** Indirectly through project creation flows. Manual override might be available for admins if necessary.

*   **`setRepaymentSchedule(uint256 projectId, uint8 scheduleType, uint256 paymentAmount)`**
    *   **Purpose:** Configures the repayment schedule for a project, used in `FeeRouter` to calculate next payment due dates.
    *   **Role Required:** `Constants.PROJECT_HANDLER_ROLE` (granted to `ProjectFactory` and `LiquidityPoolManager` on `FeeRouter`).
    *   **Inputs:**
        *   `projectId` (`uint256`): Example: `"101"`
        *   `scheduleType` (`uint8`): `1` for weekly, `2` for monthly.
            *   Example: `"1"`
        *   `paymentAmount` (`uint256`): Expected payment amount per period.
            *   Example: `"1000000000"`
    *   **Outputs:** None.
    *   **Admin Panel Interaction:** Part of project setup, potentially editable by admins.

*   **`updateLastMgmtFeeTimestamp(uint256 projectId)`**
*   **`updatePaymentSchedule(uint256 projectId)`**
    *   **Role Required:** `Constants.REPAYMENT_ROUTER_ROLE` (granted to `RepaymentRouter` contract on `FeeRouter`).
    *   **Admin Panel Interaction:** These are typically called by `RepaymentRouter`, not directly by an admin panel.

**Events:**
    *(FeeRouter events are mainly for logging/auditing and are triggered by other contract interactions.)*

#### E. `PausableGovernor` Admin & Governance Functions

*   **Purpose:** Manages governance proposals, including pausing/unpausing other system contracts.
*   **Frontend Interaction (Admin Panel / Governance Portal):** Interface to create proposals, view active proposals, vote, and queue/execute passed proposals.
*   **Frontend Interaction (User Requesting Admin Service):** Token holders (if it's a token-based governor) or members of a council (if it's a council-based governor) would interact to propose and vote.

**General Governance Flow (Conceptual - actual functions depend on OpenZeppelin Governor chosen):**

1.  **`propose(address[] targets, uint256[] values, bytes[] calldatas, string description)`**
    *   **Purpose:** A user with proposal rights creates a new governance proposal.
    *   **Role Required:** Proposal rights (e.g., token holders meeting a threshold, specific `PROPOSER_ROLE` if defined by the Governor. Note: `PROPOSER_ROLE` is not in the provided `Constants.json`, so this depends on Governor implementation. Often, any token holder can propose, or it's a role set on the Governor itself).
    *   **Inputs:**
        *   `targets` (`address[]`): Array of contract addresses to call.
            *   Example: `["0xDirectProjectVaultToPause..."]`
        *   `values` (`uint256[]`): Array of ETH values to send with each call (usually `0`).
            *   Example: `["0"]`
        *   `calldatas` (`bytes[]`): Array of calldata for the function calls on target contracts.
            *   Example: `[ethers.utils.id("pause()").substring(0, 10)]` (to call `pause()` - actual encoding needed)
        *   `description` (`string`): A human-readable description of the proposal.
            *   Example: `"Proposal to pause DirectProjectVault for project 101 during maintenance."`
    *   **Outputs:** `uint256` (proposalId).
    *   **Admin/Governance Portal Interaction:** Form to create a new proposal, specifying targets, function calls, and description.

2.  **`castVote(uint256 proposalId, uint8 support)` or `castVoteWithReason(uint256 proposalId, uint8 support, string reason)` etc.**
    *   **Purpose:** Eligible voters cast their vote on a proposal.
    *   **Role Required:** Voting rights (token holders, council members).
    *   **Inputs:**
        *   `proposalId` (`uint256`): The ID of the proposal.
        *   `support` (`uint8`): Vote type (e.g., 0 for Against, 1 for For, 2 for Abstain - depends on Governor setup).
        *   `reason` (`string`, optional): Justification for the vote.
    *   **Outputs:** None or vote weight.
    *   **Admin/Governance Portal Interaction:** Display active proposals, allow users to connect wallet and cast vote.

3.  **`queue(uint256 proposalId)`**
    *   **Purpose:** After a proposal passes and its voting period ends, it's queued for execution (subject to a timelock).
    *   **Role Required:** Anyone (usually, after proposal is successful).
    *   **Inputs:** `proposalId` (`uint256`).
    *   **Outputs:** None.
    *   **Admin/Governance Portal Interaction:** Button to queue a passed proposal.

4.  **`execute(uint256 proposalId)`**
    *   **Purpose:** Executes a queued proposal after the timelock period.
    *   **Role Required:** Anyone (usually, after timelock passes).
    *   **Inputs:** `proposalId` (`uint256`).
    *   **Outputs:** None.
    *   **Admin/Governance Portal Interaction:** Button to execute a queued and ready proposal.

**Viewing Functions:**
*   `state(uint256 proposalId)`: Get current state of a proposal.
*   `proposalVotes(uint256 proposalId)`: Get vote counts.
*   `getVotes(address account, uint256 blockNumber)`: Get voting power of an account.
*   And others depending on the specific Governor modules used.

**Events:**
*   `ProposalCreated(...)`
*   `VoteCast(...)`
*   `ProposalQueued(...)`
*   `ProposalExecuted(...)`
*   `TimelockChange(...)` (If timelock is managed by the governor)
    *   **Admin/Governance Portal Interaction:** Display proposal lifecycle, voting results, upcoming executions.

#### F. `MockUSDC` Admin Functions (For Test Environments)

*   **Purpose:** Allows minting and controlled burning of MockUSDC tokens for testing.
*   **Frontend Interaction (Admin Panel/Dev Tool):** Interface for developers/testers to get MockUSDC or burn it.
*   **Frontend Interaction (User Requesting Admin Service):** Not for end-users on a mainnet deployment.

**Functions:**

*   **`mint(address to, uint256 amount)`**
    *   **Purpose:** Mints new MockUSDC tokens.
    *   **Role Required:** `Constants.MINTER_ROLE` (on `MockUSDC`).
    *   **Inputs:**
        *   `to` (`address`): Address to receive tokens.
            *   Example: `"0xTesterAddress..."`
        *   `amount` (`uint256`): Amount to mint (considering 6 decimals).
            *   Example: `"1000000000"` (for 1000 USDC)
    *   **Outputs:** None.
    *   **Admin Panel/Dev Tool Interaction:** Input recipient address and amount, click "Mint".

*   **`burnFrom(address from, uint256 amount)`**
    *   **Purpose:** Burns tokens from a specified address, controlled by `BURNER_ROLE`.
    *   **Role Required:** `Constants.BURNER_ROLE` (on `MockUSDC`). (Caller also needs allowance from `from` address).
    *   **Inputs:**
        *   `from` (`address`): Address to burn tokens from.
            *   Example: `"0xTargetToBurnFrom..."`
        *   `amount` (`uint256`): Amount to burn.
            *   Example: `"500000000"`
    *   **Outputs:** None.
    *   **Admin Panel/Dev Tool Interaction:** Input source address and amount, click "Burn From". Requires prior approval from the `from` address to this contract if the `BURNER_ROLE` holder is not the `from` address itself.

*   **`burn(uint256 amount)` (Inherited from ERC20Burnable)**
    *   **Purpose:** Allows token holder to burn their own tokens.
    *   **Role Required:** None (token holder).
    *   **Inputs:**
        *   `amount` (`uint256`): Amount to burn.
    *   **Outputs:** None.
    *   **Admin Panel/Dev Tool Interaction:** If an admin wants to burn their own tokens.

**Events:**

*   **`Minted(address indexed minter, address indexed to, uint256 amount)`**
*   **`BurnedFrom(address indexed burner, address indexed from, uint256 amount)`**
*   `Transfer(address indexed from, address indexed to, uint256 value)` (will show burn as transfer to address(0))
    *   **Admin Panel/Dev Tool Interaction:** Log mint/burn operations.

---

### General Contract Upgradeability (UUPS)

*   **Contracts:** `DeveloperRegistry`, `RiskRateOracleAdapter`, `DirectProjectVault`, `LiquidityPoolManager`, `FeeRouter`.
*   **Purpose:** Allows upgrading the implementation contract while preserving storage and address.
*   **Frontend Interaction (Admin Panel):** An interface for admins with `UPGRADER_ROLE` to propose and execute upgrades. This usually involves calling `upgradeToAndCall(address newImplementation, bytes data)`. The `data` parameter can be used to call an initialization function on the new implementation if needed.
*   **Function:** `upgradeToAndCall(address newImplementation, bytes data)`
    *   **Role Required:** `Constants.UPGRADER_ROLE` (often combined with `Constants.DEFAULT_ADMIN_ROLE` or managed via governance).
    *   **Inputs:**
        *   `newImplementation` (`address`): Address of the new logic contract.
        *   `data` (`bytes`): Optional calldata for an initialization function on the new implementation.
    *   **Outputs:** None.
*   **Event:** `Upgraded(address indexed implementation)`
    *   **Admin Panel Interaction:** Log upgrade events for audit.

---

Remember to always refer to the `Constants.sol` for the correct `bytes32` role values.