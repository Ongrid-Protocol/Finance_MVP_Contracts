# Smart Contract Role Granting Setup Guide

This guide outlines the necessary role granting steps to configure the OnGrid Protocol smart contracts for operational use. These steps are typically performed by an `Admin Wallet` that holds the `DEFAULT_ADMIN_ROLE` on the respective contracts.

**Important Initial Assumptions:**

1.  **`Admin Wallet`:** This wallet address is used for performing administrative actions. It is assumed that this `Admin Wallet` initially holds the `DEFAULT_ADMIN_ROLE` on all major deployed contracts listed below (e.g., `DeveloperRegistry`, `ProjectFactory`, `DeveloperDepositEscrow`, `LiquidityPoolManager`, `FeeRouter`, `RiskRateOracleAdapter`, `MockUSDC`). The `DEFAULT_ADMIN_ROLE` for a contract usually allows the holder to grant any other role within that contract.
2.  **`Constants.sol`:** All `bytes32` role identifiers used below (e.g., `Constants.MINTER_ROLE`) are correctly defined in your `Constants.sol` file and their `bytes32` values are obtained by calling the respective functions on the deployed `Constants` contract (e.g., `MINTER_ROLE_BYTES32 = Constants.MINTER_ROLE()`).
3.  **Contract Addresses:** The deployed addresses of all smart contracts are known.

## Section 1: Granting Operational Roles to the `Admin Wallet`

These roles empower the `Admin Wallet` to perform direct administrative actions and initiate key system processes.

### 1.1. `MockUSDC`: Minting Capability
*   **Actor:** `Admin Wallet`
*   **Target Contract:** `MockUSDC`
*   **Role to Grant:** `Constants.MINTER_ROLE`
*   **Account Receiving Role:** `Admin Wallet` Address
*   **Function to Call on `MockUSDC`:** `grantRole(MINTER_ROLE_BYTES32, ADMIN_WALLET_ADDRESS)`
*   **Purpose:** Allows the `Admin Wallet` to mint `MockUSDC` tokens for testing and distribution.
*   **Verification:** `MockUSDC.hasRole(MINTER_ROLE_BYTES32, ADMIN_WALLET_ADDRESS)` should return `true`.

### 1.2. `ProjectFactory`: Project Creation Capability
*   **Actor:** `Admin Wallet`
*   **Target Contract:** `ProjectFactory`
*   **Role to Grant:** `Constants.DEFAULT_ADMIN_ROLE` (Project creation is a core administrative function of the factory, typically managed by its overall admin.)
*   **Account Receiving Role:** `Admin Wallet` Address (This step assumes the Admin Wallet is already the `DEFAULT_ADMIN_ROLE` or is being granted it by the deployer).
*   **Function to Call on `ProjectFactory`:** (If granting `DEFAULT_ADMIN_ROLE`, this is usually done by the current admin of the role).
*   **Purpose:** Allows the `Admin Wallet` to create new `DirectProjectVault` instances via the `ProjectFactory`.
*   **Verification:** `ProjectFactory.hasRole(DEFAULT_ADMIN_ROLE_BYTES32, ADMIN_WALLET_ADDRESS)` should return `true`.

### 1.3. `LiquidityPoolManager`: Pool Management & Fund Allocation
*   **Actor:** `Admin Wallet`
*   **Target Contract:** `LiquidityPoolManager`
*   **Roles to Ensure/Grant:** `Constants.DEFAULT_ADMIN_ROLE` (Pool creation and fund allocation are core administrative functions of the manager, typically managed by its overall admin.)
*   **Account Receiving Role:** `Admin Wallet` Address (This step assumes the Admin Wallet is already the `DEFAULT_ADMIN_ROLE` or is being granted it by the deployer).
*   **Purpose:** Allows `Admin Wallet` to create new Liquidity Pools and allocate funds from pools to projects.
*   **Verification:** `LiquidityPoolManager.hasRole(DEFAULT_ADMIN_ROLE_BYTES32, ADMIN_WALLET_ADDRESS)` should return `true`.

### 1.4. `RiskRateOracleAdapter`: Oracle Operations & Configuration
*   **Actor:** `Admin Wallet`
*   **Target Contract:** `RiskRateOracleAdapter`
*   **Steps:**
    1.  **Pushing Risk Parameters:**
        *   **Role to Grant:** `Constants.RISK_ORACLE_ROLE`
        *   **Account Receiving Role:** `Admin Wallet` Address (or a dedicated `Oracle_Wallet_Address`)
        *   **Function to Call on `RiskRateOracleAdapter`:** `grantRole(RISK_ORACLE_ROLE_BYTES32, ACCOUNT_ADDRESS)`
        *   **Purpose:** Allows the designated account to call `pushRiskParams` and other oracle-specific functions.
    2.  **Configuration (e.g., `setTargetContract`):**
        *   The `Admin Wallet` uses its `DEFAULT_ADMIN_ROLE` on `RiskRateOracleAdapter` for config functions.
*   **Verification:** `RiskRateOracleAdapter.hasRole(RISK_ORACLE_ROLE_BYTES32, ACCOUNT_ADDRESS)` should return `true`.

### 1.5. `DeveloperDepositEscrow`: Direct Deposit Management by Admin
*   **Actor:** `Admin Wallet`
*   **Target Contract:** `DeveloperDepositEscrow`
*   **Steps:**
    1.  **Slashing Deposits:**
        *   **Role to Grant:** `Constants.SLASHER_ROLE`
        *   **Account Receiving Role:** `Admin Wallet` Address
        *   **Function to Call on `DeveloperDepositEscrow`:** `grantRole(SLASHER_ROLE_BYTES32, ADMIN_WALLET_ADDRESS)`
        *   **Purpose:** Allows `Admin Wallet` to slash developer deposits if necessary.
    2.  **Manual Deposit Release (Optional/Fallback):**
        *   **Role to Grant:** `Constants.RELEASER_ROLE`
        *   **Account Receiving Role:** `Admin Wallet` Address
        *   **Function to Call on `DeveloperDepositEscrow`:** `grantRole(RELEASER_ROLE_BYTES32, ADMIN_WALLET_ADDRESS)`
        *   **Purpose:** Allows `Admin Wallet` to manually release or transfer deposits in specific scenarios.
*   **Verification:** `DeveloperDepositEscrow.hasRole(...)` for each role should return `true`.

### 1.6. `DeveloperRegistry`: KYC Management (If Admin Wallet handles KYC directly)
*   **Actor:** `Admin Wallet`
*   **Target Contract:** `DeveloperRegistry`
*   **Role to Grant:** `Constants.KYC_ADMIN_ROLE`
*   **Account Receiving Role:** `Admin Wallet` Address (Alternatively, grant this to a separate `KYC_Admin_Wallet_Address` - see Section 3)
*   **Function to Call on `DeveloperRegistry`:** `grantRole(KYC_ADMIN_ROLE_BYTES32, ADMIN_WALLET_ADDRESS)`
*   **Purpose:** Allows `Admin Wallet` to submit KYC information and set developer verification status.
*   **Verification:** `DeveloperRegistry.hasRole(KYC_ADMIN_ROLE_BYTES32, ADMIN_WALLET_ADDRESS)` should return `true`.

## Section 2: Granting Roles to System Contracts for Inter-Contract Operations

These roles allow different system contracts to securely call functions on each other as part of automated processes.

### 2.1. `FeeRouter` Permissions:
*   **Actor:** `Admin Wallet`
*   **Target Contract:** `FeeRouter`
*   **Steps:**
    1.  **For `ProjectFactory`:**
        *   **Role to Grant:** `Constants.PROJECT_HANDLER_ROLE`
        *   **Account Receiving Role:** `ProjectFactory` Contract Address
        *   **Function to Call on `FeeRouter`:** `grantRole(PROJECT_HANDLER_ROLE_BYTES32, PROJECT_FACTORY_ADDRESS)`
        *   **Purpose:** Allows `ProjectFactory` to call `setProjectDetails` and `setRepaymentSchedule` on `FeeRouter` during project creation.
    2.  **For `LiquidityPoolManager`:**
        *   **Role to Grant:** `Constants.PROJECT_HANDLER_ROLE`
        *   **Account Receiving Role:** `LiquidityPoolManager` Contract Address
        *   **Function to Call on `FeeRouter`:** `grantRole(PROJECT_HANDLER_ROLE_BYTES32, LIQUIDITY_POOL_MANAGER_ADDRESS)`
        *   **Purpose:** Allows `LiquidityPoolManager` to call `setProjectDetails` and `setRepaymentSchedule` on `FeeRouter` when allocating funds to projects.
    3.  **For `RepaymentRouter`:**
        *   **Role to Grant:** `Constants.REPAYMENT_ROUTER_ROLE`
        *   **Account Receiving Role:** `RepaymentRouter` Contract Address
        *   **Function to Call on `FeeRouter`:** `grantRole(REPAYMENT_ROUTER_ROLE_BYTES32, REPAYMENT_ROUTER_ADDRESS)`
        *   **Purpose:** Allows `RepaymentRouter` to call `updateLastMgmtFeeTimestamp` and `updatePaymentSchedule` on `FeeRouter` during repayment processing.
*   **Verification:** Check `FeeRouter.hasRole(...)` for each recipient contract and role.

### 2.2. `DeveloperRegistry` Permissions (for `incrementFundedCounter`):
*   **Actor:** `Admin Wallet`
*   **Target Contract:** `DeveloperRegistry`
*   **Role to Grant:** `Constants.PROJECT_HANDLER_ROLE` (This role is used by `ProjectFactory`/`LPM` to indicate they are handling project lifecycle steps that affect the registry).
*   **Steps:**
    1.  **For `ProjectFactory`:**
        *   **Account Receiving Role:** `ProjectFactory` Contract Address
        *   **Function to Call on `DeveloperRegistry`:** `grantRole(PROJECT_HANDLER_ROLE_BYTES32, PROJECT_FACTORY_ADDRESS)`
    2.  **For `LiquidityPoolManager`:**
        *   **Account Receiving Role:** `LiquidityPoolManager` Contract Address
        *   **Function to Call on `DeveloperRegistry`:** `grantRole(PROJECT_HANDLER_ROLE_BYTES32, LIQUIDITY_POOL_MANAGER_ADDRESS)`
*   **Purpose:** Allows `ProjectFactory` and `LiquidityPoolManager` to call `incrementFundedCounter`.
*   **Verification:** Check `DeveloperRegistry.hasRole(PROJECT_HANDLER_ROLE_BYTES32, ...)` for each contract.

### 2.3. `RepaymentRouter` Permissions (for `registerProject`):
*   **Actor:** `Admin Wallet`
*   **Target Contract:** `RepaymentRouter`
*   **Role to Grant:** `Constants.PROJECT_HANDLER_ROLE` (This role is used by `ProjectFactory`/`LPM` to indicate they are handling project lifecycle steps that affect the repayment router).
*   **Steps:**
    1.  **For `ProjectFactory`:**
        *   **Account Receiving Role:** `ProjectFactory` Contract Address
        *   **Function to Call on `RepaymentRouter`:** `grantRole(PROJECT_HANDLER_ROLE_BYTES32, PROJECT_FACTORY_ADDRESS)`
    2.  **For `LiquidityPoolManager`:**
        *   **Account Receiving Role:** `LiquidityPoolManager` Contract Address
        *   **Function to Call on `RepaymentRouter`:** `grantRole(PROJECT_HANDLER_ROLE_BYTES32, LIQUIDITY_POOL_MANAGER_ADDRESS)`
*   **Purpose:** Allows `ProjectFactory` and `LiquidityPoolManager` to call `registerProject` (or equivalent setup function) on `RepaymentRouter`.
*   **Verification:** Check `RepaymentRouter.hasRole(PROJECT_HANDLER_ROLE_BYTES32, ...)` for each contract.

### 2.4. `DeveloperDepositEscrow` Permissions (for System Contracts):
*   **Actor:** `Admin Wallet`
*   **Target Contract:** `DeveloperDepositEscrow`
*   **New Role Introduced:** `Constants.DEPOSIT_FUNDER_ROLE`
*   **Steps:**
    1.  **Grant `DEPOSIT_FUNDER_ROLE` for funding deposits:**
        *   **Account Receiving Role:** `ProjectFactory` Contract Address
        *   **Function to Call on `DeveloperDepositEscrow`:** `grantRole(DEPOSIT_FUNDER_ROLE_BYTES32, PROJECT_FACTORY_ADDRESS)`
        *   **Purpose:** Allows `ProjectFactory` to call `fundDeposit` on `DeveloperDepositEscrow`.
    2.  **Grant `DEPOSIT_FUNDER_ROLE` for funding deposits:**
        *   **Account Receiving Role:** `LiquidityPoolManager` Contract Address
        *   **Function to Call on `DeveloperDepositEscrow`:** `grantRole(DEPOSIT_FUNDER_ROLE_BYTES32, LIQUIDITY_POOL_MANAGER_ADDRESS)`
        *   **Purpose:** Allows `LiquidityPoolManager` to call `fundDeposit` on `DeveloperDepositEscrow`.
    3.  **Empower `ProjectFactory` to grant `RELEASER_ROLE` to Vault Instances:**
        *   The `ProjectFactory` needs to be an admin of the `RELEASER_ROLE` to grant it.
        *   **Action:** `Admin Wallet` (as `DEFAULT_ADMIN_ROLE` on `DeveloperDepositEscrow`) calls `_setRoleAdmin(RELEASER_ROLE_BYTES32, DEPOSIT_FUNDER_ROLE_BYTES32)` on `DeveloperDepositEscrow`.
            *   **Explanation:** This makes any address holding `DEPOSIT_FUNDER_ROLE` (i.e., `ProjectFactory` and `LPM`) an administrator for the `RELEASER_ROLE`. Thus, `ProjectFactory` can subsequently grant `RELEASER_ROLE` to the `DirectProjectVault` instances it creates.
            *   **Note:** This also means `LiquidityPoolManager` could grant `RELEASER_ROLE`. If this is undesired, a more specific role for `ProjectFactory` could be created and made admin of `RELEASER_ROLE`. For now, this approach is simpler.
*   **Verification:**
    *   `DeveloperDepositEscrow.hasRole(DEPOSIT_FUNDER_ROLE_BYTES32, PROJECT_FACTORY_ADDRESS)` should be `true`.
    *   `DeveloperDepositEscrow.hasRole(DEPOSIT_FUNDER_ROLE_BYTES32, LIQUIDITY_POOL_MANAGER_ADDRESS)` should be `true`.
    *   `DeveloperDepositEscrow.getRoleAdmin(RELEASER_ROLE_BYTES32)` should return `DEPOSIT_FUNDER_ROLE_BYTES32`.

## Section 3: Granting Roles to Specific User-Type Wallets

### 3.1. `DeveloperRegistry`: KYC Administration
*   **Actor:** `Admin Wallet`
*   **Target Contract:** `DeveloperRegistry`
*   **Role to Grant:** `Constants.KYC_ADMIN_ROLE`
*   **Account Receiving Role:** `KYC_Admin_Wallet_Address` (a dedicated wallet for KYC operations)
*   **Function to Call on `DeveloperRegistry`:** `grantRole(KYC_ADMIN_ROLE_BYTES32, KYC_ADMIN_WALLET_ADDRESS)`
*   **Purpose:** Allows a dedicated `KYC Admin Wallet` to manage developer KYC processes.
*   **Verification:** `DeveloperRegistry.hasRole(KYC_ADMIN_ROLE_BYTES32, KYC_ADMIN_WALLET_ADDRESS)` should return `true`.

## Section 4: Roles on Contract Instances (Post-Creation Considerations)

### 4.1. `DirectProjectVault` Instance Admin
*   **Context:** When `ProjectFactory.createProjectVault(...)` is called by the `Admin Wallet`.
*   **Expected Behavior:** The `ProjectFactory` should be implemented to set the `msg.sender` (i.e., the `Admin Wallet` that called `createProjectVault`) as the `DEFAULT_ADMIN_ROLE` on the newly deployed `DirectProjectVault` instance.
*   **Purpose:** This grants the `Admin Wallet` control over the specific vault instance.
*   **Verification:** After a vault is created, `newVaultInstance.hasRole(DEFAULT_ADMIN_ROLE_BYTES32, ADMIN_WALLET_ADDRESS)` should return `true`.

### 4.2. `DirectProjectVault` Instance Interaction with `DeveloperDepositEscrow`
*   **Context:** As set up in **Section 2.4 (Step 3)**, the `ProjectFactory` (which has `DEPOSIT_FUNDER_ROLE` and is an admin of `RELEASER_ROLE`) is responsible for granting `RELEASER_ROLE` to new `DirectProjectVault` instances.
*   **Expected Behavior by `ProjectFactory` (internal to its `createProjectVault` function):**
    1.  Grant `Constants.RELEASER_ROLE` to `newVaultAddress` on `DeveloperDepositEscrow`:
        `DeveloperDepositEscrow.grantRole(RELEASER_ROLE_BYTES32, newVaultAddress)`
*   **Purpose:** Allows the `DirectProjectVault` instance to call `releaseDeposit` and `transferDepositToProject` (both guarded by `RELEASER_ROLE`) on `DeveloperDepositEscrow`.
*   **Verification:** After a vault is created by `ProjectFactory`:
    *   `DeveloperDepositEscrow.hasRole(RELEASER_ROLE_BYTES32, newVaultAddress)` should be `true`.

---

This guide provides a comprehensive checklist for role allocation, updated to reflect the new `DEPOSIT_FUNDER_ROLE` and refined granting logic. **It's critical to ensure your `Constants.sol` now includes `DEPOSIT_FUNDER_ROLE`, and `DeveloperDepositEscrow.sol` uses this role for `fundDeposit`.** All role `bytes32` values should be obtained by calling the respective functions on the deployed `Constants` contract.
