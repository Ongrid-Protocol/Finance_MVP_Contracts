# Smart Contract Role Granting Setup Guide

This guide outlines the necessary role granting steps to configure the OnGrid Protocol smart contracts for operational use. These steps are typically performed by an `Admin Wallet` that holds the `DEFAULT_ADMIN_ROLE` on the respective contracts.

**Important Initial Assumptions:**

1.  **`Admin Wallet`:** This wallet address is used for performing administrative actions. It is assumed that this `Admin Wallet` initially holds the `DEFAULT_ADMIN_ROLE` on all major deployed contracts listed below (e.g., `DeveloperRegistry`, `ProjectFactory`, `DeveloperDepositEscrow`, `LiquidityPoolManager`, `FeeRouter`, `RiskRateOracleAdapter`, `MockUSDC`). The `DEFAULT_ADMIN_ROLE` for a contract usually allows the holder to grant any other role within that contract.
2.  **`Constants.sol`:** All `bytes32` role identifiers used below (e.g., `Constants.MINTER_ROLE()`) are correctly defined in your `Constants.sol` file and their `bytes32` values are obtained by calling the respective functions on the deployed `Constants` contract.
    *   *Note: `MILESTONE_AUTHORIZER_ROLE` has been removed.*
    *   *Note: `DEV_ESCROW_ROLE` on `DirectProjectVault` is currently unused as `triggerDrawdown` function is commented out.*
3.  **Contract Addresses:** The deployed addresses of all smart contracts are known.

## Section 1: Granting Operational Roles to the `Admin Wallet` (Deployer)

These roles empower the `Admin Wallet` (typically the deployer address) to perform direct administrative actions and initiate key system processes.

### 1.1. `MockUSDC`: Minting Capability
*   **Actor:** `Admin Wallet` / Deployer
*   **Target Contract:** `MockUSDC`
*   **Role to Grant:** `Constants.MINTER_ROLE()`
*   **Account Receiving Role:** `Admin Wallet` / Deployer Address
*   **Action:** Call `grantRole(Constants.MINTER_ROLE(), ADMIN_WALLET_ADDRESS)` on `MockUSDC`.
    *   *Note: This specific grant is NOT in `DeployCore.s.sol` and should be handled via an admin panel or separate script if `MockUSDC` is pre-deployed or deployed separately.*
*   **Purpose:** Allows the `Admin Wallet` to mint `MockUSDC` tokens.
*   **Verification:** `MockUSDC.hasRole(Constants.MINTER_ROLE(), ADMIN_WALLET_ADDRESS)` should return `true`.

### 1.2. `ProjectFactory`: General Admin Rights & Configuration
*   **Actor:** Deployer (during deployment script)
*   **Target Contract:** `ProjectFactory`
*   **Role Granted:** `Constants.DEFAULT_ADMIN_ROLE()`
*   **Account Receiving Role:** Deployer Address (e.g., `0x0a19...`)
*   **Action (in `DeployCore.s.sol`):** `deployer` is passed as admin in `ProjectFactory.initialize(...)`. The `deployer` then calls `projectFactoryProxy.setAddresses(...)` which is also guarded by `DEFAULT_ADMIN_ROLE()` (this now includes `feeRouterAddress`).
*   **Purpose:** Allows Deployer to manage `ProjectFactory`, including calling `setAddresses`.
*   **Verification:** `ProjectFactory.hasRole(Constants.DEFAULT_ADMIN_ROLE(), DEPLOYER_ADDRESS)` is `true`.

### 1.3. `LiquidityPoolManager`: General Admin Rights
*   **Actor:** Deployer (during deployment script)
*   **Target Contract:** `LiquidityPoolManager`
*   **Role Granted:** `Constants.DEFAULT_ADMIN_ROLE()`
*   **Account Receiving Role:** Deployer Address
*   **Action (in `DeployCore.s.sol`):** `deployer` is passed as admin in `LiquidityPoolManager.initialize(...)`.
*   **Purpose:** Allows Deployer to manage `LiquidityPoolManager` (e.g., create pools).
*   **Verification:** `LiquidityPoolManager.hasRole(Constants.DEFAULT_ADMIN_ROLE(), DEPLOYER_ADDRESS)` is `true`.

### 1.4. `RiskRateOracleAdapter`: Oracle Operations & Configuration
*   **Actor:** Deployer / `Admin Wallet`
*   **Target Contract:** `RiskRateOracleAdapter`
*   **Roles & Actions:**
    1.  **`Constants.DEFAULT_ADMIN_ROLE()` to Deployer:** Granted via `RiskRateOracleAdapter.initialize(deployer)`.
        *   **Purpose:** Allows Deployer to configure `RiskRateOracleAdapter` (e.g., `setTargetContract`, `setAssessmentInterval`).
    2.  **`Constants.RISK_ORACLE_ROLE()` to `ORACLE_ADMIN`:**
        *   **Action:** `RiskRateOracleAdapter(proxy).grantRole(Constants.RISK_ORACLE_ROLE(), ORACLE_ADMIN_ENV_VAR)` in `DeployCore.s.sol`.
        *   **Purpose:** Allows designated `ORACLE_ADMIN` to call `pushRiskParams`, etc.
*   **Verification:** Check roles for `DEPLOYER_ADDRESS` and `ORACLE_ADMIN`.
*   **Note:** `ProjectFactory` and `LiquidityPoolManager` now automatically call `setTargetContract` on `RiskRateOracleAdapter` for new projects. `DirectProjectVault` grants `RISK_ORACLE_ROLE` to the `riskOracleAdapterAddress` provided during its initialization (via `ProjectFactory`).

### 1.5. `DeveloperDepositEscrow`: Direct Deposit Management by Admin/Deployer
*   **Actor:** Deployer / `Admin Wallet`
*   **Target Contract:** `DeveloperDepositEscrow`
*   **Roles & Actions (in `DeployCore.s.sol` by deployer):
    1.  **`Constants.DEFAULT_ADMIN_ROLE()` to Deployer:** Implicitly granted to `msg.sender` of constructor (the deployer script/wallet).
        *   **Purpose:** Allows deployer to grant other roles and call `setRoleAdminExternally`.
    2.  **`Constants.SLASHER_ROLE()` to `SLASHING_ADMIN`:**
        *   `developerDepositEscrowContract.grantRole(Constants.SLASHER_ROLE(), SLASHING_ADMIN_ENV_VAR)`.
        *   **Purpose:** Allows designated `SLASHING_ADMIN` to slash deposits.
    3.  **`Constants.RELEASER_ROLE()` to Deployer:**
        *   `developerDepositEscrowContract.grantRole(Constants.RELEASER_ROLE(), deployer)`.
        *   **Purpose:** Allows Deployer/`Admin Wallet` to manually release deposits if needed.
*   **Verification:** Check roles for `DEPLOYER_ADDRESS` and `SLASHING_ADMIN`.

### 1.6. `DeveloperRegistry`: General Admin & KYC Setup
*   **Actor:** Deployer / `Admin Wallet`
*   **Target Contract:** `DeveloperRegistry`
*   **Roles & Actions:**
    1.  **`Constants.DEFAULT_ADMIN_ROLE()` to Deployer:** Granted via `DeveloperRegistry.initialize(deployer)`.
        *   **Purpose:** Allows Deployer to manage `DeveloperRegistry`.
    2.  **`Constants.KYC_ADMIN_ROLE()` to `KYC_ADMIN`:**
        *   Action: `DeveloperRegistry(proxy).grantRole(Constants.KYC_ADMIN_ROLE(), KYC_ADMIN_ENV_VAR)` in `DeployCore.s.sol`.
        *   **Purpose:** Allows designated `KYC_ADMIN` to manage KYC.
*   **Verification:** Check roles.

## Section 2: Granting Roles to System Contracts for Inter-Contract Operations

These roles are granted by the Deployer (holder of `DEFAULT_ADMIN_ROLE` on the target contracts) during the deployment script.

### 2.1. `FeeRouter` Permissions:
*   **Actor:** Deployer (via `DeployCore.s.sol`)
*   **Target Contract:** `FeeRouter` (Proxy Address)
*   **Steps & Purpose:**
    1.  **Grant `Constants.PROJECT_HANDLER_ROLE()` to `ProjectFactory` Contract:** Allows `ProjectFactory` to call `setProjectDetails` and `setRepaymentSchedule` for high-value projects.
    2.  **Grant `Constants.PROJECT_HANDLER_ROLE()` to `LiquidityPoolManager` Contract:** Allows `LPM` to call `setProjectDetails` and `setRepaymentSchedule` for pool-funded projects.
    3.  **Grant `Constants.REPAYMENT_ROUTER_ROLE()` to `RepaymentRouter` Contract:** Allows `RepaymentRouter` to call `updateLastMgmtFeeTimestamp`, `updatePaymentSchedule`, and `routeFees`.
*   **Verification:** Check `FeeRouter.hasRole(...)` for each grantee contract.

### 2.2. `DeveloperRegistry` Permissions (for `incrementFundedCounter`):
*   **Actor:** Deployer (via `DeployCore.s.sol`)
*   **Target Contract:** `DeveloperRegistry` (Proxy Address)
*   **Role to Grant:** `Constants.PROJECT_HANDLER_ROLE()`
*   **Steps & Purpose:**
    1.  **Grant to `ProjectFactory` Contract:** Allows `ProjectFactory` to call `incrementFundedCounter` (for both high-value and LPM-routed projects, as `ProjectFactory` calls this after LPM interaction too).
    2.  **Grant to `LiquidityPoolManager` Contract:** Allows `LPM` to directly call `incrementFundedCounter` (as per recent fix).
*   **Verification:** Check `DeveloperRegistry.hasRole(Constants.PROJECT_HANDLER_ROLE(), ...)` for each system contract.

### 2.3. `RepaymentRouter` Permissions (for `setFundingSource`):
*   **Actor:** Deployer (via `DeployCore.s.sol`)
*   **Target Contract:** `RepaymentRouter`
*   **Role to Grant:** `Constants.PROJECT_HANDLER_ROLE()`
*   **Steps & Purpose:**
    1.  **Grant to `ProjectFactory` Contract:** Allows `ProjectFactory` to call `setFundingSource` when it creates a `DirectProjectVault`.
    2.  **Grant to `LiquidityPoolManager` Contract:** Allows `LPM` to call `setFundingSource` when it funds a project from a pool.
*   **Verification:** Check `RepaymentRouter.hasRole(Constants.PROJECT_HANDLER_ROLE(), ...)` for each system contract.

### 2.4. `DeveloperDepositEscrow` Permissions (Crucial Inter-Contract Setup):
*   **Actor:** Deployer (via `DeployCore.s.sol`)
*   **Target Contract:** `DeveloperDepositEscrow`
*   **Steps & Purpose:**
    1.  **Grant `Constants.DEPOSIT_FUNDER_ROLE()` to `ProjectFactory` Contract:** Allows `ProjectFactory` to call `fundDeposit`.
    2.  **Grant `Constants.DEPOSIT_FUNDER_ROLE()` to `LiquidityPoolManager` Contract:** Allows `LPM` to call `fundDeposit`.
    3.  **Set Admin of `RELEASER_ROLE`:** Call `developerDepositEscrowContract.setRoleAdminExternally(Constants.RELEASER_ROLE(), Constants.DEPOSIT_FUNDER_ROLE())`.
        *   **Explanation:** This makes any contract holding `DEPOSIT_FUNDER_ROLE` (i.e., `ProjectFactory` and `LPM`) an administrator *for the `RELEASER_ROLE` only*. This is the key to allowing `ProjectFactory` to grant `RELEASER_ROLE` to new vaults directly during vault creation.
*   **Verification:**
    *   `DeveloperDepositEscrow.hasRole(Constants.DEPOSIT_FUNDER_ROLE(), PROJECT_FACTORY_ADDRESS)` is `true`.
    *   `DeveloperDepositEscrow.hasRole(Constants.DEPOSIT_FUNDER_ROLE(), LIQUIDITY_POOL_MANAGER_ADDRESS)` is `true`.
    *   `DeveloperDepositEscrow.getRoleAdmin(Constants.RELEASER_ROLE())` returns the `bytes32` value of `Constants.DEPOSIT_FUNDER_ROLE()`.

### 2.5. `RiskRateOracleAdapter` Permissions (for `setTargetContract`):
*   **Actor:** Deployer (via `DeployCore.s.sol`)
*   **Target Contract:** `RiskRateOracleAdapter` (Proxy Address)
*   **Role to Grant:** `Constants.PROJECT_HANDLER_ROLE()`
*   **Accounts Receiving Role:** `ProjectFactory` and `LiquidityPoolManager` contracts.
*   **Action (in `DeployCore.s.sol`):**
    ```solidity
    RiskRateOracleAdapter(address(riskRateOracleAdapterProxy)).grantRole(Constants.PROJECT_HANDLER_ROLE(), address(projectFactoryProxy));
    RiskRateOracleAdapter(address(riskRateOracleAdapterProxy)).grantRole(Constants.PROJECT_HANDLER_ROLE(), address(liquidityPoolManagerProxy));
    ```
*   **Purpose:** Allows `ProjectFactory` and `LiquidityPoolManager` to automatically call `setTargetContract` on `RiskRateOracleAdapter` when new projects are created/funded.
*   **Note:** The `setTargetContract` function in `RiskRateOracleAdapter` is now protected by `PROJECT_HANDLER_ROLE`.

## Section 3: Granting Roles to Specific User-Type Wallets (Post-Deployment by Admin)

These are typically done via an Admin Panel after the initial deployment and setup.

### 3.1. `DeveloperRegistry`: KYC Administration
*   **Actor:** `Admin Wallet` (holder of `DEFAULT_ADMIN_ROLE` on `DeveloperRegistry`)
*   **Target Contract:** `DeveloperRegistry` (Proxy Address)
*   **Role to Grant:** `Constants.KYC_ADMIN_ROLE()`
*   **Account Receiving Role:** `KYC_Admin_Wallet_Address` (e.g., `KYC_ADMIN` from .env)
*   **Action (via Admin Panel or script):** Call `grantRole(Constants.KYC_ADMIN_ROLE(), KYC_ADMIN_WALLET_ADDRESS)`.
*   **Purpose:** Allows a dedicated `KYC Admin Wallet` to manage developer KYC processes.
*   **Verification:** `DeveloperRegistry.hasRole(Constants.KYC_ADMIN_ROLE(), KYC_ADMIN_WALLET_ADDRESS)` is `true`.

## Section 4: Roles on Contract Instances (Automated Post-Creation)

These roles are granted *by other contracts* as part of their automated internal logic, once the initial setup in Section 1 & 2 is complete.

### 4.1. `DirectProjectVault` Instance Admin & Roles
*   **Context:** When `ProjectFactory._deployAndInitVault(...)` is called.
*   **Expected Behavior:**
    1.  The `adminAddress` (from `ProjectFactory`'s state, set by deployer) is granted `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, and `UPGRADER_ROLE` on the new `DirectProjectVault` instance.
    2.  The `repaymentRouterAddress` is granted `REPAYMENT_HANDLER_ROLE`.
    3.  The `riskOracleAdapterAddress` (if non-zero) is granted `RISK_ORACLE_ROLE`.
    4.  *The `DEV_ESCROW_ROLE` grant to `devEscrow` address is currently commented out in `DirectProjectVault` as `triggerDrawdown` is unused.*
*   **Purpose:** Grants designated admin control, allows repayment router and oracle adapter to interact with the specific vault instance.
*   **Verification:** After a vault is created, check `newVaultInstance.hasRole(...)` for these roles and addresses.

### 4.2. `DirectProjectVault` Instance Interaction with `DeveloperDepositEscrow`
*   **Context:** During `ProjectFactory._deployAndInitializeHighValueProject(...)` execution.
*   **Expected Behavior by `ProjectFactory` (internal logic):**
    1.  `ProjectFactory` directly grants `Constants.RELEASER_ROLE()` on `DeveloperDepositEscrow` to the newly created `vaultAddress`. This is possible because `ProjectFactory` holds `DEPOSIT_FUNDER_ROLE` which is admin of `RELEASER_ROLE`.
*   **Purpose:** Allows the newly created `DirectProjectVault` instance to later call `releaseDeposit()` and `transferDepositToProject()` on `DeveloperDepositEscrow` for its specific project.
*   **Verification:** After a vault is created by `ProjectFactory`:
    *   `DeveloperDepositEscrow.hasRole(Constants.RELEASER_ROLE(), newVaultAddress)` should be `true`.

### 4.3. `RiskRateOracleAdapter` Interaction with New Projects (Vaults & LPM-funded)
*   **Context:**
    *   During `ProjectFactory._deployAndInitializeHighValueProject(...)` for vaults.
    *   During `LiquidityPoolManager._setupRepaymentAndTarget(...)` for LPM-funded projects.
*   **Expected Automated Behavior:**
    1.  `ProjectFactory` calls `IRiskRateOracleAdapter(riskOracleAdapterAddress).setTargetContract(_projectId, vaultAddress, 0)`.
    2.  `LiquidityPoolManager` calls `riskOracleAdapter.setTargetContract(context.projectId, address(this), context.poolId)`.
*   **Permission Prerequisite:** These automated calls are now possible because `ProjectFactory` and `LiquidityPoolManager` are granted `PROJECT_HANDLER_ROLE` on `RiskRateOracleAdapter` (as per Section 2.5), and `setTargetContract` is protected by this role.
*   **Purpose:** Enables the `RiskRateOracleAdapter` to update risk parameters on newly created/funded projects through automated registration by the creating/funding contracts.
*   **Verification:** After project creation/funding:
    *   `RiskRateOracleAdapter.getTargetContract(projectId)` should return the correct vault or LPM address.
    *   `RiskRateOracleAdapter.getPoolId(projectId)` should return the correct poolId for LPM projects.

---

This guide reflects the enhanced role management strategy and recent contract fixes. Key improvements include automated setup calls by `ProjectFactory` and `LiquidityPoolManager`. All `bytes32` role values must be fetched by calling the respective getter functions on the deployed `Constants` contract during script execution or interaction.
