# Admin Integration and Role Granting Guide

This guide outlines the necessary admin functionalities and role granting setup for the OnGrid Protocol smart contracts. It provides a detailed breakdown of all admin-level interactions required for the system to function properly.

## I. Overview of Deployment and Initial Setup

The `DeployCore.s.sol` script handles the deployment of all core contracts and establishes most of the critical initial role assignments and contract linkages. This automated setup is crucial for the protocol's interconnected components to function correctly from the outset.

**Key actions performed by `DeployCore.s.sol`:**
1.  Deploys implementation contracts and their respective `ERC1967Proxy` contracts.
2.  Initializes these proxy contracts with necessary parameters, including linking them to each other (e.g., `ProjectFactory` is linked to `DeveloperRegistry`, `DeveloperDepositEscrow`, `LiquidityPoolManager`, etc.).
3.  Assigns initial `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, and `UPGRADER_ROLE` on upgradeable contracts, typically to the deployer address.
4.  Grants specific operational roles to designated admin EOA addresses (provided via `.env` variables like `KYC_ADMIN`, `ORACLE_ADMIN`, `SLASHING_ADMIN`).
5.  Grants necessary inter-contract operational roles (e.g., `PROJECT_HANDLER_ROLE` to `ProjectFactory` and `LiquidityPoolManager` on `DeveloperRegistry` and `FeeRouter`; `REPAYMENT_ROUTER_ROLE` to `RepaymentRouter` on `FeeRouter`).
6.  Configures the `PausableGovernor` by registering key contracts that it can pause/unpause and grants `PAUSER_ROLE` on these contracts to the `PausableGovernor`.

**The primary role of the Admin Panel post-deployment is:**
*   To allow admins (initially the deployer or an EOA granted `DEFAULT_ADMIN_ROLE`) to manage specific operational aspects of the protocol.
*   To further manage roles: granting or revoking operational roles to other admin EOAs if the initial `.env` admins need to be changed, augmented, or if roles need to be reassigned.
*   To execute emergency or special administrative functions not part of regular user flows.

## II. Admin Panel: Initial Setup and Role Verification/Management

This section details the manual steps required *after* deployment using the Admin Panel, primarily for verifying the automated setup and making any further adjustments to role assignments for External Admin EOAs. The account performing these actions in the Admin Panel must have the `DEFAULT_ADMIN_ROLE` on the respective target contracts. The deployer address initially holds this role on most contracts.

### A. Connecting to the Admin Panel
1.  **Connect Wallet**: Ensure the wallet connected to the Admin Panel holds the necessary administrative privileges (e.g., the deployer address or an address that has been granted `DEFAULT_ADMIN_ROLE` on the relevant contracts).
2.  **Select Network**: Ensure the Admin Panel is connected to the correct blockchain network where the contracts are deployed.
3.  **Load Contract Addresses**: The Admin Panel should be pre-configured or allow configuration with the deployed addresses of all core contracts. These addresses are outputted by the `DeployCore.s.sol` script.

### B. Verifying and Managing Key External Admin Roles

The `DeployCore.s.sol` script assigns critical roles to addresses specified in your environment variables (`KYC_ADMIN`, `ORACLE_ADMIN`, `SLASHING_ADMIN`, etc.). The Admin Panel should allow verification of these assignments and modification if necessary.

**For each role below, the Admin Panel should provide an interface to:**
*   View current holders of the role.
*   Grant the role to a new address.
*   Revoke the role from an existing address.

**Actor**: An EOA with `DEFAULT_ADMIN_ROLE` on the target contract.

1.  **KYC Administrator (`KYC_ADMIN_ROLE`)**
    *   **Purpose**: Manages developer KYC submissions and verification statuses.
    *   **Target Contract**: `DeveloperRegistry`
    *   **Role Constant**: `Constants.KYC_ADMIN_ROLE`
    *   **Deployment Action**: `DeployCore.s.sol` grants this role to the `KYC_ADMIN` (from `.env`).
    *   **Admin Panel Actions**:
        *   **Grant**: `DeveloperRegistry.grantRole(KYC_ADMIN_ROLE, newKycAdminAddress)`
        *   **Revoke**: `DeveloperRegistry.revokeRole(KYC_ADMIN_ROLE, existingKycAdminAddress)`
    *   **Verification**:
        *   Call `DeveloperRegistry.hasRole(KYC_ADMIN_ROLE, kycAdminAddressFromEnv)` should return `true`.
        *   Call `DeveloperRegistry.getRoleMemberCount(KYC_ADMIN_ROLE)` and `DeveloperRegistry.getRoleMember(KYC_ADMIN_ROLE, index)` to list members.

2.  **Slashing Administrator (`SLASHER_ROLE`)**
    *   **Purpose**: Authorizes slashing of developer deposits in case of default.
    *   **Target Contract**: `DeveloperDepositEscrow`
    *   **Role Constant**: `Constants.SLASHER_ROLE`
    *   **Deployment Action**: `DeployCore.s.sol` grants this role to `SLASHING_ADMIN` (from `.env`).
    *   **Admin Panel Actions**:
        *   **Grant**: `DeveloperDepositEscrow.grantRole(SLASHER_ROLE, newSlashingAdminAddress)`
        *   **Revoke**: `DeveloperDepositEscrow.revokeRole(SLASHER_ROLE, existingSlashingAdminAddress)`
    *   **Verification**:
        *   Call `DeveloperDepositEscrow.hasRole(SLASHER_ROLE, slashingAdminAddressFromEnv)` should return `true`.

3.  **Risk Oracle Administrator (`RISK_ORACLE_ROLE` on `RiskRateOracleAdapter`)**
    *   **Purpose**: Allows pushing updated risk parameters (e.g., APR) to projects via the `RiskRateOracleAdapter`. Also allows triggering periodic assessments and setting project risk levels.
    *   **Target Contract**: `RiskRateOracleAdapter`
    *   **Role Constant**: `Constants.RISK_ORACLE_ROLE`
    *   **Deployment Action**: `DeployCore.s.sol` grants this role to `ORACLE_ADMIN` (from `.env`).
    *   **Admin Panel Actions**:
        *   **Grant**: `RiskRateOracleAdapter.grantRole(RISK_ORACLE_ROLE, newOracleAdminAddress)`
        *   **Revoke**: `RiskRateOracleAdapter.revokeRole(RISK_ORACLE_ROLE, existingOracleAdminAddress)`
    *   **Verification**:
        *   Call `RiskRateOracleAdapter.hasRole(RISK_ORACLE_ROLE, oracleAdminAddressFromEnv)` should return `true`.

4.  **PausableGovernor Administrators**
    *   **PAUSER_ROLE on `PausableGovernor`**:
        *   **Purpose**: Allows an address to call `pause(targetContract)` and `unpause(targetContract)` on the `PausableGovernor`, which in turn calls `pause()`/`unpause()` on the registered target contracts.
        *   **Target Contract**: `PausableGovernor`
        *   **Role Constant**: `Constants.PAUSER_ROLE`
        *   **Deployment Action**: `DeployCore.s.sol` grants this role on `PausableGovernor` to the `deployer`. The `PausableGovernor` itself is granted `PAUSER_ROLE` on the individual pausable contracts (`DeveloperRegistry`, `DeveloperDepositEscrow`, `ProjectFactory`, `LiquidityPoolManager`, `RepaymentRouter`).
        *   **Admin Panel Actions (by `DEFAULT_ADMIN_ROLE` on `PausableGovernor`)**:
            *   **Grant**: `PausableGovernor.grantRole(PAUSER_ROLE, newGlobalPauserAddress)`
            *   **Revoke**: `PausableGovernor.revokeRole(PAUSER_ROLE, existingGlobalPauserAddress)`
    *   **DEFAULT_ADMIN_ROLE on `PausableGovernor`**:
        *   **Purpose**: Allows an address to add or remove contracts from the `PausableGovernor`'s control list.
        *   **Target Contract**: `PausableGovernor`
        *   **Role Constant**: `Constants.DEFAULT_ADMIN_ROLE`
        *   **Deployment Action**: `DeployCore.s.sol` grants this role on `PausableGovernor` to the `deployer`.
        *   **Admin Panel Actions (by current `DEFAULT_ADMIN_ROLE` on `PausableGovernor`)**:
            *   Consider if this role needs to be transferred or granted to another EOA. If so: `PausableGovernor.grantRole(DEFAULT_ADMIN_ROLE, newGovernorFullAdminAddress)`. The original admin might then renounce their role.

5.  **Clone Administrators (`PAUSER_ADMIN_FOR_CLONES`, `ADMIN_FOR_VAULT_CLONES`)**
    *   These addresses are passed during `ProjectFactory.setAddresses()` and used during the initialization of cloned `DevEscrow` and `DirectProjectVault` contracts.
    *   **`PAUSER_ADMIN_FOR_CLONES`**: Receives `PAUSER_ROLE` on newly created `DevEscrow` clones.
    *   **`ADMIN_FOR_VAULT_CLONES`**: Receives `DEFAULT_ADMIN_ROLE` (and thus `PAUSER_ROLE`, `UPGRADER_ROLE`) on newly created `DirectProjectVault` clones.
    *   **Admin Panel Action**: If these admin addresses need to be changed *after* `ProjectFactory.setAddresses()` has been called, the `ProjectFactory.setAddresses()` function must be called again by an account with `DEFAULT_ADMIN_ROLE` on `ProjectFactory` with the new admin addresses. This will affect *future* clones. For *existing* clones, roles would need to be managed directly on those clone instances by their current admin.

### C. Verifying Inter-Contract Roles
The Admin Panel should also allow viewing (though not typically modifying, as these are core protocol links) key inter-contract roles established by `DeployCore.s.sol`. This helps in diagnosing issues. Examples:
*   `ProjectFactory` having `PROJECT_HANDLER_ROLE` on `DeveloperRegistry`, `FeeRouter`, `RiskRateOracleAdapter`, `RepaymentRouter`.
*   `ProjectFactory` having `DEPOSIT_FUNDER_ROLE` and `RELEASER_ROLE` on `DeveloperDepositEscrow`.
*   `LiquidityPoolManager` having similar roles.
*   `RepaymentRouter` having `REPAYMENT_ROUTER_ROLE` on `FeeRouter`.
*   `RiskRateOracleAdapter` having `RISK_ORACLE_ROLE` on `LiquidityPoolManager` and `DirectProjectVault` (clones).

**Verification Method**: Use `hasRole(ROLE, contractAddress)` on the contract granting the role.

## III. Admin Panel Functionality and Integration Steps

### 1. KYC Management (DeveloperRegistry)

#### Functionality Required
1.  **Submit KYC Data for a Developer**
    *   **Context**: After an admin has reviewed KYC documents off-chain.
    *   **Action**: Admin uses the panel to submit the developer's address, a hash of their KYC documents, and the off-chain storage location of these documents (e.g., IPFS CID).
    *   **Contract Call**: `DeveloperRegistry.submitKYC(address developer, bytes32 kycHash, string calldata kycDataLocation)`
    *   **Caller Requirement**: Admin EOA must have `KYC_ADMIN_ROLE` on `DeveloperRegistry`.
    *   **Testing Success**:
        *   Transaction completes successfully.
        *   `KYCSubmitted` event is emitted with correct `developer` and `kycHash`.
        *   Verify using `DeveloperRegistry.getDeveloperInfo(developer)` that `kycDataHash` is updated.
        *   Verify using `DeveloperRegistry.getKycDataLocation(developer)` that the location string is updated.

2.  **Set Developer's KYC Verification Status**
    *   **Context**: After KYC data is submitted and reviewed.
    *   **Action**: Admin sets the developer's status to verified or not verified.
    *   **Contract Call**: `DeveloperRegistry.setVerifiedStatus(address developer, bool verified)`
    *   **Caller Requirement**: Admin EOA must have `KYC_ADMIN_ROLE` on `DeveloperRegistry`.
    *   **Testing Success**:
        *   Transaction completes successfully.
        *   `KYCStatusChanged` event is emitted with correct `developer` and `isVerified` status.
        *   Verify using `DeveloperRegistry.isVerified(developer)` or `DeveloperRegistry.getDeveloperInfo(developer)` that `isVerified` status is updated.

3.  **View Developer KYC Information**
    *   **Action**: Admin searches for a developer by address to view their KYC hash, data location, verification status, and number of times funded.
    *   **Contract Calls**:
        *   `DeveloperRegistry.getDeveloperInfo(address developer)`
        *   `DeveloperRegistry.getKycDataLocation(address developer)`
        *   `DeveloperRegistry.isVerified(address developer)` (redundant if using `getDeveloperInfo`)
        *   `DeveloperRegistry.getTimesFunded(address developer)` (redundant if using `getDeveloperInfo`)
    *   **Testing Success**: Data displayed in the panel matches the on-chain state.

### 2. Developer Deposit Management (DeveloperDepositEscrow)

#### Functionality Required
1.  **Manually Release Deposit (Emergency/Contingency)**
    *   **Context**: For exceptional situations where a project's deposit needs manual release to the developer (e.g., project cancellation before funding, error correction). This is typically handled automatically by `ProjectFactory` or `LiquidityPoolManager` for successful low-value projects or by `DirectProjectVault` clones for high-value projects.
    *   **Action**: Admin specifies the `projectId` and triggers the release.
    *   **Contract Call**: `DeveloperDepositEscrow.releaseDeposit(uint256 projectId)`
    *   **Caller Requirement**: Admin EOA must have `RELEASER_ROLE` on `DeveloperDepositEscrow`.
    *   **Testing Success**:
        *   Transaction completes successfully.
        *   `DepositReleased` event is emitted with correct `projectId`, `developer`, and `amount`.
        *   Developer's USDC balance increases by the deposit amount.
        *   `DeveloperDepositEscrow.isDepositSettled(projectId)` returns `true`.

2.  **Slash Deposit (Project Default)**
    *   **Context**: If a project defaults and its associated deposit needs to be slashed.
    *   **Action**: Admin specifies `projectId` and the `feeRecipient` (typically the Protocol Treasury Admin address set in `LiquidityPoolManager` or another designated treasury).
    *   **Contract Call**: `DeveloperDepositEscrow.slashDeposit(uint256 projectId, address feeRecipient)`
    *   **Caller Requirement**: Admin EOA must have `SLASHER_ROLE` on `DeveloperDepositEscrow`. The `SLASHING_ADMIN` (from `.env`) is granted this by `DeployCore`.
    *   **Testing Success**:
        *   Transaction completes successfully.
        *   `DepositSlashed` event is emitted with correct `projectId`, `developer`, `amount`, and `feeRecipient`.
        *   The `feeRecipient`'s USDC balance increases by the deposit amount.
        *   `DeveloperDepositEscrow.isDepositSettled(projectId)` returns `true`.

3.  **View Deposit Status**
    *   **Action**: Admin searches by `projectId` to view deposit details.
    *   **Contract Calls**:
        *   `DeveloperDepositEscrow.getDepositAmount(uint256 projectId)`
        *   `DeveloperDepositEscrow.getProjectDeveloper(uint256 projectId)`
        *   `DeveloperDepositEscrow.isDepositSettled(uint256 projectId)`
    *   **Testing Success**: Data displayed matches the on-chain state.

### 3. Liquidity Pool Management (LiquidityPoolManager)

#### Functionality Required
1.  **Create New Liquidity Pool**
    *   **Action**: Admin provides a name for the new pool. The `poolId` is assigned incrementally.
    *   **Contract Call**: `LiquidityPoolManager.createPool(uint256 poolId_unused, string calldata name)` (Note: `poolId` parameter is currently unused in `createPool` as `poolCount` is used internally).
    *   **Caller Requirement**: Admin EOA must have `DEFAULT_ADMIN_ROLE` on `LiquidityPoolManager`.
    *   **Testing Success**:
        *   Transaction completes successfully.
        *   `PoolCreated` event is emitted with the new `poolId`, `name`, and `creator` address.
        *   `LiquidityPoolManager.getPoolInfo(newPoolId)` returns the correct details with `exists = true`.
        *   `LiquidityPoolManager.poolCount()` is incremented.

2.  **Set Pool Risk Level and Base APR**
    *   **Action**: Admin selects a `poolId`, assigns a `riskLevel` (1=low, 2=medium, 3=high), and sets a `baseAprBps` for loans funded by this pool. This APR is used if the `RiskRateOracleAdapter` does not provide a specific rate for a project or if the oracle call fails.
    *   **Contract Call**: `LiquidityPoolManager.setPoolRiskLevel(uint256 poolId, uint16 riskLevel, uint16 baseAprBps)`
    *   **Caller Requirement**: Admin EOA must have `DEFAULT_ADMIN_ROLE` on `LiquidityPoolManager`.
    *   **Testing Success**:
        *   Transaction completes successfully.
        *   Call `LiquidityPoolManager.poolRiskLevels(poolId)` to verify `riskLevel`.
        *   Call `LiquidityPoolManager.poolAprRates(poolId)` to verify `baseAprBps`.

3.  **Handle Loan Default in a Pool**
    *   **Context**: When a low-value project funded by a liquidity pool defaults.
    *   **Action**: Admin specifies `poolId`, `projectId`, an optional `writeOffAmount` (defaults to full outstanding principal if 0), and whether to `slashDeposit`.
    *   **Contract Call**: `LiquidityPoolManager.handleLoanDefault(uint256 poolId, uint256 projectId, uint256 writeOffAmount, bool slashDeposit)`
    *   **Caller Requirement**: Admin EOA must have `DEFAULT_ADMIN_ROLE` on `LiquidityPoolManager`.
    *   **Testing Success**:
        *   Transaction completes successfully.
        *   `LoanDefaulted` event is emitted with correct details.
        *   `LiquidityPoolManager.getPoolLoanRecord(poolId, projectId)` shows `isActive = false`.
        *   `LiquidityPoolManager.getPoolInfo(poolId)` shows `totalAssets` reduced by `actualWriteOffAmount`.
        *   If `slashDeposit` was true, verify `DeveloperDepositEscrow.slashDeposit` was called (check `DepositSlashed` event and `DeveloperDepositEscrow.isDepositSettled(projectId)`). The recipient of slashed funds is `protocolTreasuryAdmin` stored in `LiquidityPoolManager`.

4.  **View Pool and Loan Information**
    *   **Action**: Admin selects a pool to view its details (total assets, total shares, risk level, APR) and a list of loans funded by it.
    *   **Contract Calls**:
        *   `LiquidityPoolManager.getPoolInfo(uint256 poolId)`
        *   `LiquidityPoolManager.poolRiskLevels(uint256 poolId)`
        *   `LiquidityPoolManager.poolAprRates(uint256 poolId)`
        *   To list loans, the panel may need to iterate through project IDs known to be associated with the pool or listen to `PoolProjectFunded` events historically. Then call `LiquidityPoolManager.getPoolLoanRecord(uint256 poolId, uint256 projectId)` for each.
    *   **Testing Success**: Displayed data accurately reflects the on-chain state.

### 4. Risk Management and Oracle Interaction (RiskRateOracleAdapter)

#### Functionality Required
1.  **Set Project Risk Level**
    *   **Context**: An off-chain risk assessment determines a project's risk level (1-low, 2-medium, 3-high).
    *   **Action**: Admin (or automated oracle system with `RISK_ORACLE_ROLE`) inputs `projectId` and `riskLevel`.
    *   **Contract Call**: `RiskRateOracleAdapter.setProjectRiskLevel(uint256 projectId, uint16 riskLevel)`
    *   **Caller Requirement**: Caller must have `RISK_ORACLE_ROLE` on `RiskRateOracleAdapter`.
    *   **Testing Success**:
        *   Transaction completes successfully.
        *   `ProjectRiskLevelSet` event emitted.
        *   `RiskRateOracleAdapter.getProjectRiskLevel(projectId)` returns the set level.

2.  **Push Updated Risk Parameters (APR) to a Project**
    *   **Context**: An off-chain oracle determines a new APR for a project. The tenor is usually not changed post-funding.
    *   **Action**: Admin (or automated oracle system with `RISK_ORACLE_ROLE`) inputs `projectId`, new `aprBps`, and `tenor` (0 if unchanged).
    *   **Contract Call**: `RiskRateOracleAdapter.pushRiskParams(uint256 projectId, uint16 aprBps, uint48 tenor)`
    *   **Caller Requirement**: Admin EOA (or oracle contract) must have `RISK_ORACLE_ROLE` on `RiskRateOracleAdapter`.
    *   **Testing Success**:
        *   Transaction completes successfully.
        *   `RiskParamsPushed` event is emitted with correct details.
        *   If the project is a Vault, `DirectProjectVault.getCurrentAprBps()` on the target vault reflects the new APR.
        *   If the project is pool-funded, `LiquidityPoolManager.getPoolLoanRecord(poolId, projectId).aprBps` reflects the new APR.

3.  **Trigger Batch Risk Assessment / Request Periodic Assessment**
    *   **`triggerBatchRiskAssessment()`**:
        *   **Context**: To signal off-chain systems to reassess all projects.
        *   **Action**: Admin triggers this function.
        *   **Contract Call**: `RiskRateOracleAdapter.triggerBatchRiskAssessment()`
        *   **Caller Requirement**: `RISK_ORACLE_ROLE` on `RiskRateOracleAdapter`.
        *   **Testing Success**: `BatchRiskAssessmentTriggered` event emitted.
    *   **`requestPeriodicAssessment(uint256 projectId)`**:
        *   **Context**: To signal off-chain systems for a specific project if its assessment interval has passed.
        *   **Action**: Admin triggers for a specific `projectId`.
        *   **Contract Call**: `RiskRateOracleAdapter.requestPeriodicAssessment(uint256 projectId)`
        *   **Caller Requirement**: `RISK_ORACLE_ROLE` on `RiskRateOracleAdapter`.
        *   **Testing Success**: `PeriodicAssessmentRequested` event emitted if interval passed. `lastAssessmentTimestamp` for the project is updated.

4.  **Manage Assessment Interval**
    *   **Action**: Admin updates the global `assessmentInterval` for periodic assessments.
    *   **Contract Call**: `RiskRateOracleAdapter.setAssessmentInterval(uint256 newInterval)`
    *   **Caller Requirement**: `DEFAULT_ADMIN_ROLE` on `RiskRateOracleAdapter`.
    *   **Testing Success**: `AssessmentIntervalUpdated` event emitted. `RiskRateOracleAdapter.assessmentInterval()` returns the new interval.

5.  **View Oracle Configuration**
    *   **Action**: View target contracts for projects, pool IDs, risk levels, and assessment interval.
    *   **Contract Calls**:
        *   `RiskRateOracleAdapter.getTargetContract(uint256 projectId)`
        *   `RiskRateOracleAdapter.getPoolId(uint256 projectId)`
        *   `RiskRateOracleAdapter.getProjectRiskLevel(uint256 projectId)`
        *   `RiskRateOracleAdapter.assessmentInterval()`
        *   `RiskRateOracleAdapter.lastAssessmentTimestamp(uint256 projectId)`
    *   **Testing Success**: Data displayed matches on-chain state.

### 5. System Pause Control (PausableGovernor)

The `PausableGovernor` contract centralizes pause/unpause operations for critical system contracts. `DeployCore.s.sol` registers these contracts with the governor and grants `PAUSER_ROLE` to the governor on those contracts.

#### Functionality Required
1.  **Pause a Registered Contract**
    *   **Action**: Admin selects a target contract (already registered with the governor) and triggers pause.
    *   **Contract Call**: `PausableGovernor.pause(address targetContract)`
    *   **Caller Requirement**: Admin EOA must have `PAUSER_ROLE` on `PausableGovernor`.
    *   **Testing Success**:
        *   Transaction completes successfully.
        *   `Paused` event from `PausableGovernor` emitted.
        *   The target contract's `paused()` function (e.g., `DeveloperRegistry.paused()`) returns `true`.
        *   State-changing functions on the target contract should revert or be blocked.

2.  **Unpause a Registered Contract**
    *   **Action**: Admin selects a target contract and triggers unpause.
    *   **Contract Call**: `PausableGovernor.unpause(address targetContract)`
    *   **Caller Requirement**: Admin EOA must have `PAUSER_ROLE` on `PausableGovernor`.
    *   **Testing Success**:
        *   Transaction completes successfully.
        *   `Unpaused` event from `PausableGovernor` emitted.
        *   The target contract's `paused()` function returns `false`.
        *   State-changing functions on the target contract become operational again.

3.  **Manage Pausable Contracts List (Add/Remove)**
    *   **Context**: If new pausable contracts are deployed or existing ones need to be removed from governor control.
    *   **Action (Add)**: Admin provides the address of a new contract that implements the pausable interface (has `pause()` and `unpause()` functions and ideally grants `PAUSER_ROLE` to the `PausableGovernor`).
    *   **Contract Call (Add)**: `PausableGovernor.addPausableContract(address target)`
    *   **Caller Requirement (Add)**: `DEFAULT_ADMIN_ROLE` on `PausableGovernor`.
    *   **Testing Success (Add)**:
        *   `PausableContractAdded` event emitted.
        *   `PausableGovernor.isPausableContract(target)` returns `true`.
        *   **Crucially, the `target` contract must separately grant `PAUSER_ROLE` to the `PausableGovernor`'s address for the governor to successfully call `pause/unpause` on it.** The `addPausableContract` function checks for interface support but doesn't grant roles on the target.
    *   **Action (Remove)**: Admin provides the address of a contract to remove from governor control.
    *   **Contract Call (Remove)**: `PausableGovernor.removePausableContract(address target)`
    *   **Caller Requirement (Remove)**: `DEFAULT_ADMIN_ROLE` on `PausableGovernor`.
    *   **Testing Success (Remove)**:
        *   `PausableContractRemoved` event emitted.
        *   `PausableGovernor.isPausableContract(target)` returns `false`.

4.  **View Governor Configuration**
    *   **Action**: List all contracts currently managed by `PausableGovernor`.
    *   **Contract Call**: This requires iterating through known contracts and checking `PausableGovernor.isPausableContract(address target)`. The admin panel might maintain a list based on `PausableContractAdded`/`Removed` events.
    *   **Testing Success**: Displayed list is accurate.

### 6. Treasury and Fee Management (FeeRouter)

#### Functionality Required
1.  **Update Protocol Treasury Address**
    *   **Action**: Admin changes the `protocolTreasury` address where a share of fees is sent.
    *   **Contract Call**: `FeeRouter.setProtocolTreasury(address _newTreasury)`
    *   **Caller Requirement**: `DEFAULT_ADMIN_ROLE` on `FeeRouter`.
    *   **Testing Success**:
        *   Transaction completes successfully.
        *   `FeeRouter.getProtocolTreasury()` returns the new address.

2.  **Update Carbon Treasury Address**
    *   **Action**: Admin changes the `carbonTreasury` address.
    *   **Contract Call**: `FeeRouter.setCarbonTreasury(address _newTreasury)`
    *   **Caller Requirement**: `DEFAULT_ADMIN_ROLE` on `FeeRouter`.
    *   **Testing Success**:
        *   Transaction completes successfully.
        *   `FeeRouter.getCarbonTreasury()` returns the new address.

3.  **View Fee-Related Information**
    *   **Action**: Display current treasury addresses, project fee details.
    *   **Contract Calls**:
        *   `FeeRouter.getProtocolTreasury()`
        *   `FeeRouter.getCarbonTreasury()`
        *   `FeeRouter.getProjectFeeDetails(uint256 projectId)`
        *   `FeeRouter.getNextPaymentInfo(uint256 projectId)`
    *   **Event Monitoring**: `FeeRouted` to track fee distributions.
    *   **Testing Success**: Data displayed accurately reflects on-chain values.

### 7. Project and Vault Management (ProjectFactory, DirectProjectVault instances)

#### Functionality Required
1.  **Configure `ProjectFactory` Addresses**
    *   **Context**: Initial setup or if any core implementation/admin address changes.
    *   **Action**: Admin calls `setAddresses` on `ProjectFactory` to link it to `LiquidityPoolManager`, vault/escrow implementations, `RepaymentRouter`, `FeeRouter`, `RiskRateOracleAdapter`, and default admin/pauser addresses for clones.
    *   **Contract Call**: `ProjectFactory.setAddresses(...)` with all required parameters.
    *   **Caller Requirement**: `DEFAULT_ADMIN_ROLE` on `ProjectFactory`.
    *   **Deployment Action**: This is done by `DeployCore.s.sol`. The admin panel might need this if these addresses change post-deployment.
    *   **Testing Success**:
        *   `AddressesSet` event emitted with correct parameters.
        *   Verify stored addresses in `ProjectFactory` (e.g., `liquidityPoolManager`, `vaultImplementation`) match the inputs.

2.  **Manually Close Funding for a `DirectProjectVault`**
    *   **Context**: If a high-value project's funding needs to be closed before the cap is met (e.g., by admin decision).
    *   **Action**: Admin identifies the specific `DirectProjectVault` address and triggers funding closure.
    *   **Contract Call**: `DirectProjectVault(vaultAddress).closeFundingManually()`
    *   **Caller Requirement**: Admin EOA must have `DEFAULT_ADMIN_ROLE` on that specific `DirectProjectVault` instance (this role is granted to `ADMIN_FOR_VAULT_CLONES` during vault creation by `ProjectFactory`).
    *   **Testing Success**:
        *   `FundingClosed` event emitted from the vault.
        *   `DirectProjectVault.isFundingClosed()` returns `true`.
        *   Funds are transferred to the developer, developer's deposit is transferred from `DeveloperDepositEscrow` to the developer, and `DevEscrow` is notified.

3.  **Manually Close a Loan for a `DirectProjectVault`**
    *   **Context**: If a loan in a `DirectProjectVault` is fully repaid but not automatically closed, or for administrative closure under specific conditions.
    *   **Action**: Admin identifies the vault and triggers loan closure.
    *   **Contract Call**: `DirectProjectVault(vaultAddress).closeLoan()`
    *   **Caller Requirement**: `DEFAULT_ADMIN_ROLE` on that specific `DirectProjectVault` instance. The function requires the loan to be fully repaid (`principalRepaid >= totalAssetsInvested`).
    *   **Testing Success**:
        *   `LoanClosed` event emitted from the vault.
        *   `DirectProjectVault.isLoanClosed()` returns `true`.

4.  **View `DirectProjectVault` Details**
    *   **Action**: Admin searches/selects a `DirectProjectVault` address to view its comprehensive details.
    *   **Contract Calls**: Numerous view functions on `DirectProjectVault` like `getTotalAssetsInvested()`, `getLoanAmount()`, `getPrincipalRepaid()`, `isFundingClosed()`, `isLoanClosed()`, `investorShares(investorAddress)`, etc.
    *   **Testing Success**: Data displayed accurately reflects the vault's state.

## IV. Admin Integration Sequence Summary

For a new deployment and Admin Panel setup:

1.  **Deploy Contracts**: Run `DeployCore.s.sol`. Note all deployed contract addresses and admin EOAs used from `.env`.
2.  **Admin Panel Configuration**:
    *   Input all deployed contract addresses into the Admin Panel.
    *   Connect with the `deployer` wallet or an EOA that has been granted `DEFAULT_ADMIN_ROLE` on the relevant contracts.
3.  **Role Verification**:
    *   Use the Admin Panel's role viewing functionality to verify that all roles set by `DeployCore.s.sol` (both for external admins from `.env` and inter-contract roles) are correctly assigned.
4.  **Grant Additional/Modify Admin Roles (If Needed)**:
    *   If `KYC_ADMIN`, `SLASHING_ADMIN`, `ORACLE_ADMIN` need to be different EOAs or if additional admins are required for these roles, use the Admin Panel (with `DEFAULT_ADMIN_ROLE` on the respective contracts) to grant these roles via the `grantRole` functions.
    *   If other EOAs need `PAUSER_ROLE` on the `PausableGovernor`, grant it.
5.  **Operational Functionality Testing**:
    *   **KYC**: Test `submitKYC` and `setVerifiedStatus`.
    *   **Pools**: Test `createPool`, `setPoolRiskLevel`.
    *   **Risk Oracle**: Test `setProjectRiskLevel`, `pushRiskParams`, `setAssessmentInterval`.
    *   **Pause/Unpause**: Test pausing and unpausing a non-critical registered contract via `PausableGovernor`.
    *   **Treasury**: Test viewing treasury addresses. Changing them is a significant operation.
6.  **User Flow Support**: Once the Admin Panel is set up and core admin roles are confirmed/assigned, the panel will be used to support user flows (e.g., KYC verification, handling defaults).

This structured approach ensures that all administrative controls are correctly established and accessible for the ongoing management of the OnGrid Protocol.
