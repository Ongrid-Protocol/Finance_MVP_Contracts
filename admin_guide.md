# Admin Integration and Role Granting Guide

This guide outlines the necessary admin functionalities and role granting setup for the OnGrid Protocol smart contracts. It provides a detailed breakdown of all admin-level interactions required for the system to function properly.

## Initial Role Assignments (Automated During Deployment)

During contract deployment via `DeployCore.s.sol`, several critical role assignments are automatically performed. These form the foundation of the contract permissions system.

### 1. DeveloperRegistry
* **Deployment Process**: 
  * Call `initialize(deployer)` - Grants `DEFAULT_ADMIN_ROLE` to deployer
  * `DeveloperRegistry(proxy).grantRole(Constants.KYC_ADMIN_ROLE, KYC_ADMIN)` - Grants KYC admin role
  * `DeveloperRegistry(proxy).grantRole(Constants.PROJECT_HANDLER_ROLE, ProjectFactory)` - Allows ProjectFactory to increment funded counter
  * `DeveloperRegistry(proxy).grantRole(Constants.PROJECT_HANDLER_ROLE, LiquidityPoolManager)` - Allows LPM to increment funded counter

### 2. DeveloperDepositEscrow
* **Deployment Process**:
  * Constructor grants `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, `RELEASER_ROLE`, `SLASHER_ROLE` to deployer
  * `grantRole(Constants.DEPOSIT_FUNDER_ROLE, ProjectFactory)` - Allows ProjectFactory to fund deposits
  * `grantRole(Constants.DEPOSIT_FUNDER_ROLE, LiquidityPoolManager)` - Allows LPM to fund deposits
  * `setRoleAdminExternally(Constants.RELEASER_ROLE, Constants.DEFAULT_ADMIN_ROLE)` - Sets admin for RELEASER_ROLE
  * `grantRole(Constants.RELEASER_ROLE, deployer)` - Allows deployer to release deposits
  * `grantRole(Constants.RELEASER_ROLE, ProjectFactory)` - Allows ProjectFactory to release deposits
  * `grantRole(Constants.RELEASER_ROLE, LiquidityPoolManager)` - Allows LPM to release deposits
  * `grantRole(Constants.SLASHER_ROLE, SLASHING_ADMIN)` - Allows slashing admin to slash deposits

### 3. FeeRouter
* **Deployment Process**:
  * Call `initialize(deployer, USDC, DeveloperRegistry, PROTOCOL_TREASURY_ADMIN, CARBON_TREASURY_ADMIN)` - Sets up treasuries and grants `DEFAULT_ADMIN_ROLE` to deployer
  * `grantRole(Constants.REPAYMENT_ROUTER_ROLE, RepaymentRouter)` - Allows RepaymentRouter to route fees
  * `grantRole(Constants.PROJECT_HANDLER_ROLE, ProjectFactory)` - Allows ProjectFactory to set project details
  * `grantRole(Constants.PROJECT_HANDLER_ROLE, LiquidityPoolManager)` - Allows LPM to set project details

### 4. RepaymentRouter
* **Deployment Process**:
  * Constructor grants `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE` to deployer
  * `grantRole(Constants.PROJECT_HANDLER_ROLE, ProjectFactory)` - Allows ProjectFactory to set funding source
  * `grantRole(Constants.PROJECT_HANDLER_ROLE, LiquidityPoolManager)` - Allows LPM to set funding source

### 5. RiskRateOracleAdapter
* **Deployment Process**:
  * Call `initialize(deployer)` - Grants `DEFAULT_ADMIN_ROLE`, `UPGRADER_ROLE`, `RISK_ORACLE_ROLE` to deployer
  * `grantRole(Constants.RISK_ORACLE_ROLE, ORACLE_ADMIN)` - Grants oracle role to designated admin
  * `grantRole(Constants.PROJECT_HANDLER_ROLE, ProjectFactory)` - Allows ProjectFactory to set target contract
  * `grantRole(Constants.PROJECT_HANDLER_ROLE, LiquidityPoolManager)` - Allows LPM to set target contract

### 6. PausableGovernor
* **Deployment Process**:
  * Constructor grants `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE` to deployer
  * `addPausableContract` for DeveloperRegistry, DeveloperDepositEscrow, ProjectFactory, LiquidityPoolManager, RepaymentRouter - Registers contracts that can be paused

## Admin Panel Functionality

The admin panel should be built to support the following key functionalities, organized by categories:

### 1. KYC Management

#### Functionality Required
1. **Submit KYC for a Developer**
   * **Contract**: DeveloperRegistry
   * **Function**: `submitKYC(address developer, bytes32 kycHash, string kycDataLocation)`
   * **Role Required**: `KYC_ADMIN_ROLE`
   * **UI Elements**: 
     * Form with fields for developer address
     * File upload for KYC documents (stored off-chain)
     * Hash generation from the documents
     * IPFS or other storage for KYC documents

2. **Set KYC Verification Status**
   * **Contract**: DeveloperRegistry
   * **Function**: `setVerifiedStatus(address developer, bool verified)`
   * **Role Required**: `KYC_ADMIN_ROLE` 
   * **UI Elements**:
     * Search for developer by address
     * Toggle switch for verification status
     * Submit button

3. **View Developer KYC Status**
   * **Contract**: DeveloperRegistry
   * **Function**: `getDeveloperInfo(address developer)`, `getKycDataLocation(address developer)`
   * **UI Elements**:
     * Search by developer address
     * Display KYC status, hash, and link to data location
     * Display funding history count

#### Implementation Steps
1. Create admin role form with developer address field
2. Integrate with file upload system for KYC documents
3. Generate hash from documents using keccak256
4. Upload documents to IPFS or chosen storage system
5. Call `submitKYC` with address, hash, and location
6. Implement verification toggle for approved developers

### 2. Deposit Management

#### Functionality Required
1. **Manually Release Deposit (Emergency/Contingency)**
   * **Contract**: DeveloperDepositEscrow
   * **Function**: `releaseDeposit(uint256 projectId)`
   * **Role Required**: `RELEASER_ROLE`
   * **UI Elements**:
     * Project ID input field
     * Confirmation dialog
     * Release button

2. **Slash Deposit (When Default Occurs)**
   * **Contract**: DeveloperDepositEscrow
   * **Function**: `slashDeposit(uint256 projectId, address feeRecipient)`
   * **Role Required**: `SLASHER_ROLE`
   * **UI Elements**:
     * Project ID input field
     * Fee recipient address field (defaulting to protocol treasury)
     * Confirmation dialog
     * Slash button

3. **View Deposit Status**
   * **Contract**: DeveloperDepositEscrow
   * **Functions**: `getDepositAmount(uint256 projectId)`, `getProjectDeveloper(uint256 projectId)`, `isDepositSettled(uint256 projectId)`
   * **UI Elements**:
     * Search by project ID
     * Display deposit amount, developer, and settlement status

#### Implementation Steps
1. Create deposit management dashboard
2. Implement project search functionality
3. Display detailed deposit information
4. Add release and slash buttons with confirmation dialogues
5. Integrate with deposit events for real-time updates

### 3. Pool Management

#### Functionality Required
1. **Create Liquidity Pool**
   * **Contract**: LiquidityPoolManager
   * **Function**: `createPool(uint256 poolId_unused, string calldata name)`
   * **Role Required**: `DEFAULT_ADMIN_ROLE`
   * **UI Elements**:
     * Pool name input field
     * Create pool button

2. **Set Pool Risk Level**
   * **Contract**: LiquidityPoolManager
   * **Function**: `setPoolRiskLevel(uint256 poolId, uint16 riskLevel, uint16 baseAprBps)`
   * **Role Required**: `DEFAULT_ADMIN_ROLE`
   * **UI Elements**:
     * Pool ID selector
     * Risk level selector (1-3)
     * Base APR input (in basis points)
     * Update button

3. **Handle Loan Default**
   * **Contract**: LiquidityPoolManager
   * **Function**: `handleLoanDefault(uint256 poolId, uint256 projectId, uint256 writeOffAmount, bool slashDeposit)`
   * **Role Required**: `DEFAULT_ADMIN_ROLE`
   * **UI Elements**:
     * Pool ID selector
     * Project ID input
     * Write-off amount input (with option for full amount)
     * Checkbox to also slash deposit
     * Confirmation dialog
     * Process default button

4. **View Pool Information**
   * **Contract**: LiquidityPoolManager
   * **Functions**: `getPoolInfo(uint256 poolId)`, `getPoolLoanRecord(uint256 poolId, uint256 projectId)`
   * **UI Elements**:
     * Pool selector
     * Display pool details (assets, shares)
     * Display all active loans in the pool
     * Filter/search for specific projects

#### Implementation Steps
1. Create pool management dashboard
2. Implement pool creation form
3. Add risk level configuration panel
4. Create loan default handling interface
5. Develop detailed pool information views

### 4. Risk Management & Oracle

#### Functionality Required
1. **Set Project Risk Level**
   * **Contract**: RiskRateOracleAdapter
   * **Function**: `setProjectRiskLevel(uint256 projectId, uint16 riskLevel)`
   * **Role Required**: `RISK_ORACLE_ROLE`
   * **UI Elements**:
     * Project ID input
     * Risk level selector (1-3)
     * Update button

2. **Update Risk Parameters**
   * **Contract**: RiskRateOracleAdapter
   * **Function**: `pushRiskParams(uint256 projectId, uint16 aprBps, uint48 tenor)`
   * **Role Required**: `RISK_ORACLE_ROLE`
   * **UI Elements**:
     * Project ID input
     * APR input (in basis points)
     * Tenor input (in days - zero if unchanged)
     * Push update button

3. **Trigger Batch Risk Assessment**
   * **Contract**: RiskRateOracleAdapter
   * **Function**: `triggerBatchRiskAssessment()`
   * **Role Required**: `RISK_ORACLE_ROLE`
   * **UI Elements**:
     * Trigger button
     * Last assessment timestamp display

4. **Manage Assessment Interval**
   * **Contract**: RiskRateOracleAdapter
   * **Function**: `setAssessmentInterval(uint256 newInterval)`
   * **Role Required**: `DEFAULT_ADMIN_ROLE`
   * **UI Elements**:
     * Current interval display
     * New interval input (in seconds)
     * Update button

#### Implementation Steps
1. Create risk management dashboard
2. Implement project risk level configuration
3. Add APR update functionality
4. Build batch assessment trigger interface
5. Add assessment interval configuration

### 5. System Pause Control

#### Functionality Required
1. **Pause Specific Contract**
   * **Contract**: PausableGovernor
   * **Function**: `pause(address target)`
   * **Role Required**: `PAUSER_ROLE`
   * **UI Elements**:
     * Contract selector dropdown
     * Pause button
     * Current status indicator

2. **Unpause Specific Contract**
   * **Contract**: PausableGovernor
   * **Function**: `unpause(address target)`
   * **Role Required**: `PAUSER_ROLE`
   * **UI Elements**:
     * Contract selector dropdown
     * Unpause button
     * Current status indicator

3. **Add/Remove Pausable Contract**
   * **Contract**: PausableGovernor
   * **Functions**: `addPausableContract(address target)`, `removePausableContract(address target)`
   * **Role Required**: `DEFAULT_ADMIN_ROLE`
   * **UI Elements**:
     * Contract address input
     * Add/Remove buttons
     * List of registered pausable contracts

#### Implementation Steps
1. Create emergency controls dashboard
2. Implement contract selector with status indicators
3. Add pause/unpause functionality
4. Create interface for managing pausable contracts list

### 6. Treasury & Fee Management

#### Functionality Required
1. **Update Protocol Treasury**
   * **Contract**: FeeRouter
   * **Function**: `setProtocolTreasury(address _newTreasury)`
   * **Role Required**: `DEFAULT_ADMIN_ROLE`
   * **UI Elements**:
     * Current treasury address display
     * New treasury address input
     * Update button

2. **Update Carbon Treasury**
   * **Contract**: FeeRouter
   * **Function**: `setCarbonTreasury(address _newTreasury)`
   * **Role Required**: `DEFAULT_ADMIN_ROLE`
   * **UI Elements**:
     * Current treasury address display
     * New treasury address input
     * Update button

3. **View Fee Distribution**
   * **Contract**: FeeRouter
   * **Events to Monitor**: `FeeRouted`
   * **UI Elements**:
     * Fee distribution history table
     * Summary statistics for fees collected
     * Filtering by date range

#### Implementation Steps
1. Create fee management dashboard
2. Implement treasury update interface
3. Build fee distribution history view
4. Add summary statistics visualization

### 7. Vault Management (High-Value Projects)

#### Functionality Required
1. **Manually Close Funding**
   * **Contract**: DirectProjectVault (instance)
   * **Function**: `closeFundingManually()`
   * **Role Required**: `DEFAULT_ADMIN_ROLE` on the specific vault
   * **UI Elements**:
     * Vault address input/selector
     * Current funding status display
     * Close funding button

2. **Manually Close Loan**
   * **Contract**: DirectProjectVault (instance)
   * **Function**: `closeLoan()`
   * **Role Required**: `DEFAULT_ADMIN_ROLE` on the specific vault
   * **UI Elements**:
     * Vault address input/selector
     * Current loan status display
     * Close loan button (only enabled if full repayment received)

3. **View Vault Details**
   * **Contract**: DirectProjectVault (instance)
   * **Functions**: Various getters like `getTotalAssetsInvested()`, `getLoanAmount()`, etc.
   * **UI Elements**:
     * Vault address input/selector
     * Comprehensive vault details display
     * Investor information
     * Repayment status

#### Implementation Steps
1. Create vault management dashboard
2. Implement vault lookup functionality
3. Add funding closure interface
4. Build loan closure interface
5. Develop detailed vault information view

### 8. Role Management

#### Functionality Required
1. **Grant/Revoke KYC Admin Role**
   * **Contract**: DeveloperRegistry
   * **Functions**: `grantRole(Constants.KYC_ADMIN_ROLE, address)`, `revokeRole(Constants.KYC_ADMIN_ROLE, address)`
   * **Role Required**: `DEFAULT_ADMIN_ROLE`
   * **UI Elements**:
     * Address input field
     * Grant/Revoke buttons
     * Current KYC admins list

2. **Grant/Revoke Slasher Role**
   * **Contract**: DeveloperDepositEscrow
   * **Functions**: `grantRole(Constants.SLASHER_ROLE, address)`, `revokeRole(Constants.SLASHER_ROLE, address)`
   * **Role Required**: `DEFAULT_ADMIN_ROLE`
   * **UI Elements**:
     * Address input field
     * Grant/Revoke buttons
     * Current slasher admins list

3. **Grant/Revoke Risk Oracle Role**
   * **Contract**: RiskRateOracleAdapter
   * **Functions**: `grantRole(Constants.RISK_ORACLE_ROLE, address)`, `revokeRole(Constants.RISK_ORACLE_ROLE, address)`
   * **Role Required**: `DEFAULT_ADMIN_ROLE`
   * **UI Elements**:
     * Address input field
     * Grant/Revoke buttons
     * Current oracle admins list

4. **Grant/Revoke Pauser Role**
   * **Contract**: Multiple (DeveloperRegistry, DeveloperDepositEscrow, ProjectFactory, etc.)
   * **Functions**: `grantRole(Constants.PAUSER_ROLE, address)`, `revokeRole(Constants.PAUSER_ROLE, address)`
   * **Role Required**: `DEFAULT_ADMIN_ROLE`
   * **UI Elements**:
     * Contract selector
     * Address input field
     * Grant/Revoke buttons
     * Current pausers list per contract

#### Implementation Steps
1. Create role management dashboard
2. Implement contract selector for role management
3. Build interface for each role type
4. Display current role assignments
5. Implement grant/revoke functionality

## Admin Integration Sequence

For a new deployment, follow this integration sequence to ensure all necessary admin functionality is available:

1. **Initial Admin Dashboard Setup**
   * Prepare interface for all key admin functions
   * Configure access control based on wallet addresses and roles

2. **KYC System Configuration**
   * Set up KYC document storage system (IPFS or similar)
   * Configure KYC submission and approval workflow
   * Grant KYC_ADMIN_ROLE to appropriate personnel

3. **Pool Management Setup**
   * Create initial liquidity pools
   * Set risk levels and APR rates for each pool
   * Monitor pool deposit activities

4. **Risk Management Configuration**
   * Set up risk assessment framework
   * Configure risk level criteria
   * Implement APR update workflow

5. **Emergency Controls Testing**
   * Test pause functionality for all contracts
   * Verify unpause functionality
   * Create emergency response procedures

By following this sequence and implementing the detailed admin functionalities, you'll establish a comprehensive administration system for the OnGrid Protocol.
