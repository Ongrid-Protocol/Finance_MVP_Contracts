# OnGrid Finance Smart Contracts - Technical PRD (MVP v1.3)

*(Consolidated implementation brief for AI code generation - Finance Stack Only)*
*(Date: 25 Apr 2025)*

## 1. Project Overview

This document outlines the technical requirements for the **OnGrid Finance Smart Contracts (MVP)**. This system facilitates the financing of solar energy projects by connecting investors with developers on the Base blockchain (Sepolia testnet and Mainnet). It utilizes USDC as the primary stablecoin.

The core functionality involves two primary financing pathways:
1.  **Direct Project Vaults:** For individual, high-value projects (≥ $50k USD), allowing investors to fund specific initiatives directly. Each vault acts as a dedicated, minimal-proxy ERC-4626-like contract.
2.  **Liquidity Pools:** Managed by `LiquidityPoolManager` for funding low-value projects (< $50k USD). These pools aggregate investor capital and automatically allocate funds to eligible smaller projects.

Key system features include:
* Developer KYC verification via an off-chain process with on-chain attestation.
* A mandatory 20% upfront deposit from developers for all projects.
* Milestone-based fund drawdowns for developers.
* Automated fee calculation and routing based on a defined structure.
* Off-chain risk analysis determining project APRs, pushed on-chain via an oracle adapter.
* UUPS upgradeability for contract evolution.
* Integration points for off-chain services like KYC verification and fiat on-ramps (specifically Coinbase Onramp).

## 2. Frameworks and Libraries

* **Solidity:** `^0.8.25`
* **Blockchain:** Base Mainnet & Base Sepolia Testnet
* **Development Tooling:** Foundry (`forge`, `anvil`, `cast`)
* **Primary Asset:** USDC (6 decimals) (using MockUSDC for non-mainnet deployments)
* **Core Dependencies:**
    * **OpenZeppelin Contracts (`v5.*`)**: `ERC20`, `ERC20Permit` (for MockUSDC), `AccessControl`, `Ownable`, `Pausable`, `ReentrancyGuard`, `Clones`, `UUPSUpgradeable`, `SafeERC20`, `ERC2771Context` (optional for gasless).
    * **Solmate (`v7.*`)**: `FixedPointMathLib` (for interest), optional `ERC4626` wrapper.
    * **PRB-Math (`v4.*`)**: `PRBMathUD60x18` (for high-precision interest rate calculations).
    * **Forge-Std (`latest`)**: `Vm`, `StdCheats` (for deployment/upgrade scripts).

## 3. Core Contract Functionalities & Specifications

*(Contracts listed align with the file structure in Section 7)*

### 3.1 `MockUSDC.sol` (src/token/)

* **Inherits:** `ERC20Permit`, `AccessControl`, `ERC20Burnable`
* **Purpose:** A mock USDC token for non-mainnet environments (Anvil, Base Sepolia). Mimics mainnet USDC (6 decimals) but allows controlled minting/burning via roles.
* **Roles:** `MINTER_ROLE`, `BURNER_ROLE`. Deployer gets roles initially.
* **Key Functions:**
    * `constructor()`: Sets name "Mock USD Coin", symbol "USDC", decimals 6.
    * `mint(address to, uint256 amount)`: `external onlyRole(MINTER_ROLE)`.
    * `burn(uint256 amount)`: `external` (uses OZ `ERC20Burnable`).
    * `burnFrom(address from, uint256 amount)`: `external onlyRole(BURNER_ROLE)` (alternative burn control).
* **Events:** Standard `Transfer`, `Approval`; `Minted`, `Burned`.

### 3.2 `DeveloperRegistry.sol` (src/registry/)

* **Inherits:** `AccessControl`, `Pausable`, `UUPSUpgradeable`
* **Purpose:** Manages developer identity, KYC status (attested via off-chain verification), and funding history.
* **Roles:** `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, `UPGRADER_ROLE`, `KYC_ADMIN_ROLE` (trusted off-chain service).
* **State:**
    * `struct DevInfo { bytes32 kycDataHash; bool isVerified; uint32 timesFunded; }`
    * `mapping(address => DevInfo) public developerInfo;`
* **Key Functions:**
    * `submitKYC(address developer, bytes32 kycHash, string calldata kycDataLocation)`: `external onlyRole(KYC_ADMIN_ROLE)`. Stores hash, off-chain location (e.g., IPFS CID). Emits `KYCSubmitted`.
    * `setVerifiedStatus(address developer, bool verified)`: `external onlyRole(KYC_ADMIN_ROLE)`. Updates `isVerified`. Emits `KYCStatusChanged`.
    * `incrementFundedCounter(address developer)`: `internal`. Called by `ProjectFactory`. Increments `timesFunded`.
    * `isVerified(address developer) returns (bool)`: `view`.
    * `getDeveloperInfo(address developer) returns (DevInfo memory)`: `view`.
* **Events:** `KYCSubmitted(address indexed developer, bytes32 kycHash)`, `KYCStatusChanged(address indexed developer, bool isVerified)`, `DeveloperFundedCounterIncremented(address indexed developer, uint32 newCount)`.

### 3.3 `DeveloperDepositEscrow.sol` (src/escrow/)

* **Inherits:** `ReentrancyGuard`, `Pausable`, `AccessControl`.
* **Purpose:** Holds the 20% upfront deposit from developers. Funds locked until loan completion or default (manual trigger in MVP).
* **Roles:** `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, `RELEASER_ROLE` (`ProjectFactory` or Admin), `SLASHER_ROLE` (Admin).
* **State:**
    * `IERC20 public immutable usdcToken;`
    * `mapping(uint256 => uint256) public depositAmount; // projectId => amount`
    * `mapping(uint256 => address) public projectDeveloper; // projectId => developer`
    * `mapping(uint256 => bool) public depositReleased; // projectId => bool`
* **Key Functions:**
    * `constructor(address _usdcToken)`: Sets USDC address. Grants deployer roles.
    * `fundDeposit(uint256 projectId, address developer, uint256 amount)`: `external nonReentrant onlyRole(RELEASER_ROLE)`. Called by `ProjectFactory`. Transfers deposit from `developer`.
    * `releaseDeposit(uint256 projectId)`: `external nonReentrant onlyRole(RELEASER_ROLE)`. Called on success. Transfers deposit back to `developer`.
    * `slashDeposit(uint256 projectId, address feeRecipient)`: `external nonReentrant onlyRole(SLASHER_ROLE)`. Called on default. Transfers deposit to `feeRecipient`.
* **Events:** `DepositFunded(uint256 indexed projectId, address indexed developer, uint256 amount)`, `DepositReleased(uint256 indexed projectId, address indexed developer, uint256 amount)`, `DepositSlashed(uint256 indexed projectId, address indexed developer, uint256 amount, address recipient)`.

### 3.4 `ProjectFactory.sol` (src/factory/)

* **Inherits:** `ReentrancyGuard`, `Pausable`, `UUPSUpgradeable`, `AccessControl`.
* **Purpose:** Developer entry point for listing projects. Verifies KYC & 20% deposit, deploys `DirectProjectVault` or triggers `LiquidityPoolManager`.
* **Roles:** `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, `UPGRADER_ROLE`.
* **State:**
    * `IDeveloperRegistry public immutable developerRegistry;`
    * `IDeveloperDepositEscrow public immutable depositEscrow;`
    * `ILiquidityPoolManager public liquidityPoolManager; // Settable`
    * `address public vaultImplementation; // Settable`
    * `IERC20 public immutable usdcToken;`
    * `uint256 public projectCounter;`
    * Uses `HIGH_VALUE_THRESHOLD` from `Constants.sol`.
* **Key Functions:**
    * `constructor(address _registry, address _depositEscrow, address _usdc)`
    * `setAddresses(address _poolManager, address _vaultImpl)`: `external onlyRole(DEFAULT_ADMIN_ROLE)`.
    * `createProject(ProjectParams calldata params)`: `external nonReentrant whenNotPaused returns (uint256 projectId)`.
        * Checks `developerRegistry.isVerified(msg.sender)`.
        * Calculates & triggers `depositEscrow.fundDeposit`.
        * Increments `projectCounter`.
        * If ≥ threshold, deploys `DirectProjectVault` clone via `Clones.clone`, initializes, emits `ProjectCreated`.
        * Else, calls `liquidityPoolManager.registerAndFundProject`, emits `LowValueProjectSubmitted`.
        * Calls `developerRegistry.incrementFundedCounter`.
* **Structs:** `struct ProjectParams { uint256 loanAmountRequested; uint48 requestedTenor; string metadataCID; /* + */ }`
* **Events:** `ProjectCreated(uint256 indexed projectId, address indexed developer, address vaultAddress, uint256 loanAmount)`, `LowValueProjectSubmitted(uint256 indexed projectId, address indexed developer, uint256 loanAmount)`.

### 3.5 `DirectProjectVault.sol` (src/vault/)

* **Inherits:** `ReentrancyGuard`, `Pausable`, `UUPSUpgradeable`, `AccessControl`, optional `ERC4626`.
* **Purpose:** Manages a single high-value project loan lifecycle: investment, interest accrual, drawdowns, repayment, claims.
* **Roles:** `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, `UPGRADER_ROLE`, `REPAYMENT_HANDLER_ROLE` (`RepaymentRouter`), `DEV_ESCROW_ROLE` (`DevEscrow`), `RISK_ORACLE_ROLE` (`RiskRateOracleAdapter`).
* **State:**
    * Includes `usdcToken`, `developer`, `devEscrow`, `projectId`, `loanAmount`, `totalAssetsInvested`, `loanTenor`, `currentAprBps`, `loanStartTime`, `lastInterestAccrualTimestamp`, `accruedInterest` (use RAY precision via PRBMath), `principalRepaid`, `fundingClosed`, `loanClosed`, mappings for investor balances/claims.
* **Key Functions:**
    * `initialize(...)`: UUPS initializer.
    * `invest(uint256 amount)`: Accepts investor USDC until `loanAmount` cap. Updates state.
    * `_accrueInterest()`: `internal`. Calculates continuously compounded interest using `PRBMathUD60x18` based on `currentAprBps` and outstanding principal.
    * `handleRepayment(uint256 principalAmount, uint256 interestAmount)`: `external onlyRole(REPAYMENT_HANDLER_ROLE)`. Updates repayment state.
    * `claimYield()` / `claimPrincipal()`: Allow investors to claim repaid amounts.
    * `updateRiskParams(uint16 newAprBps)`: `external onlyRole(RISK_ORACLE_ROLE)`. Updates APR.
    * `triggerDrawdown(uint256 amount)`: `external onlyRole(DEV_ESCROW_ROLE)`. Called by `DevEscrow`.
    * `closeLoan()`: Marks loan as closed when fully repaid.
* **Events:** `Invested`, `FundingClosed`, `RepaymentReceived`, `YieldClaimed`, `PrincipalClaimed`, `DrawdownExecuted`, `RiskParamsUpdated`, `LoanClosed`.

### 3.6 `LiquidityPoolManager.sol` (src/vault/)

* **Inherits:** `ReentrancyGuard`, `Pausable`, `UUPSUpgradeable`, `AccessControl`.
* **Purpose:** Manages liquidity pools for funding low-value projects automatically.
* **Roles:** `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, `UPGRADER_ROLE`, `PROJECT_HANDLER_ROLE` (`ProjectFactory`), `REPAYMENT_HANDLER_ROLE` (`RepaymentRouter`), `RISK_ORACLE_ROLE`.
* **State:**
    * `struct PoolInfo { ... totalAssets; totalShares; ... }`
    * `mapping(uint256 => PoolInfo) public pools;`
    * `struct LoanRecord { ... principal; aprBps; principalRepaid; ... }`
    * `mapping(uint256 => mapping(uint256 => LoanRecord)) public poolLoans; // poolId => projectId => Loan`
    * `mapping(address => mapping(uint256 => uint256)) public userShares;`
* **Key Functions:**
    * `createPool(...)`: Admin function to create new pools.
    * `depositToPool(uint256 poolId, uint256 amount)`: Investor deposits USDC, gets LP shares.
    * `redeem(uint256 poolId, uint256 shares)`: Investor redeems LP shares for USDC.
    * `registerAndFundProject(uint256 projectId, address developer, ProjectParams calldata params)`: `external onlyRole(PROJECT_HANDLER_ROLE)`.
        * Selects pool, checks liquidity.
        * Gets APR via Oracle Adapter.
        * Deploys `DevEscrow` for the loan. Stores its address.
        * Creates `LoanRecord`.
        * Transfers principal from Pool to the new `DevEscrow`. Updates pool assets.
    * `handleRepayment(uint256 poolId, uint256 projectId, ...)`: `external onlyRole(REPAYMENT_HANDLER_ROLE)`. Updates `LoanRecord` and pool assets.
* **Events:** `PoolCreated`, `PoolDeposit`, `PoolRedeem`, `PoolProjectFunded`, `PoolRepaymentReceived`.

### 3.7 `DevEscrow.sol` (src/escrow/)

* **Inherits:** `AccessControl` (allows roles), `Pausable`, `ReentrancyGuard`.
* **Purpose:** Holds funds for a specific project, releases tranches to the developer upon milestone authorization. Instantiated by `ProjectFactory` (for vaults) or `LiquidityPoolManager` (for pools).
* **Roles:** `DEFAULT_ADMIN_ROLE` (funding source: Vault/PoolMgr), `PAUSER_ROLE`, `MILESTONE_AUTHORIZER_ROLE` (trusted off-chain admin).
* **State:**
    * `usdcToken`, `developer`, `fundingSource`, `totalAllocated`, `totalWithdrawn`, milestone mappings (`amount`, `authorized`, `withdrawn`).
* **Key Functions:**
    * `constructor(...)`: Sets immutable state, grants roles.
    * `fundEscrow(uint256 amount)`: `external onlyRole(DEFAULT_ADMIN_ROLE)`. Receives funds from Vault/PoolMgr.
    * `setMilestone(uint8 index, uint256 amount)`: `external onlyRole(DEFAULT_ADMIN_ROLE)`. Defines tranches.
    * `authorizeMilestone(uint8 index)`: `external onlyRole(MILESTONE_AUTHORIZER_ROLE)`. Flags milestone ready for withdrawal.
    * `withdraw(uint8 index)`: `external nonReentrant whenNotPaused`. Only callable by `developer`. Checks authorization, transfers funds, notifies `fundingSource`.
* **Events:** `EscrowFunded`, `MilestoneSet`, `MilestoneAuthorised`, `DeveloperDrawdown`.

### 3.8 `RiskRateOracleAdapter.sol` (src/oracle/)

* **Inherits:** `AccessControl`, `UUPSUpgradeable`.
* **Purpose:** On-chain interface for trusted off-chain source to push project APR/tenor.
* **Roles:** `DEFAULT_ADMIN_ROLE`, `UPGRADER_ROLE`, `ORACLE_ROLE`.
* **State:**
    * `mapping(uint256 => address) public projectTargetContract; // projectId => Vault or PoolManager`
* **Key Functions:**
    * `setTargetContract(...)`: Admin sets target.
    * `pushRiskParams(uint256 projectId, uint16 aprBps, uint48 tenor)`: `external onlyRole(ORACLE_ROLE)`. Calls update function on target contract.
* **Events:** `RiskParamsPushed`.

### 3.9 `RepaymentRouter.sol` (src/repayment/)

* **Inherits:** `ReentrancyGuard`, `Pausable`, `AccessControl`.
* **Purpose:** Central point for developer repayments. Calculates fees, determines principal/interest split, routes funds appropriately.
* **Roles:** `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`.
* **State:**
    * `usdcToken`, `feeRouter`, `projectFundingSource` mapping.
* **Key Functions:**
    * `constructor(...)`
    * `setFundingSource(...)`: Admin maps projectId to its Vault/Pool.
    * `repay(uint256 projectId, uint256 amount)`: `external nonReentrant whenNotPaused`.
        * Pulls USDC from developer.
        * Calls `feeRouter` to calculate Mgmt & Tx fees.
        * Determines principal/interest split (needs view into Vault/Pool).
        * Calls `feeRouter.routeFees(...)`.
        * Calls `handleRepayment(...)` on the project's Vault/Pool.
* **Events:** `RepaymentRouted`.

### 3.10 `FeeRouter.sol` (src/repayment/)

* **Inherits:** `AccessControl`, `UUPSUpgradeable`.
* **Purpose:** Calculates protocol fees (Capital Raising, Management, Transaction) and routes them to treasuries.
* **Roles:** `DEFAULT_ADMIN_ROLE`, `UPGRADER_ROLE`, `REPAYMENT_ROUTER_ROLE` (`RepaymentRouter`), `PROJECT_HANDLER_ROLE` (`ProjectFactory`/Vault/Pool).
* **Constants:** Uses fee constants from `Constants.sol`.
* **State:**
    * `protocolTreasury`, `carbonTreasury`, `developerRegistry`, project detail mappings (`creationTime`, `loanAmount`, `lastMgmtFeeTimestamp`).
* **Key Functions:**
    * `constructor(...)`
    * `setProjectDetails(...)`: Stores needed info for calcs.
    * `calculateCapitalRaisingFee(...) returns (uint256)`: `view`. Applies 2%/1.5% based on repeat status.
    * `calculateManagementFee(...) returns (uint256)`: `view`. Calculates accrued AUM fee using tiers and PRBMath time diff.
    * `calculateTransactionFee(...) returns (uint256)`: `view`. Applies tiered BPS based on amount. *No Cap.*
    * `routeFees(uint256 feeAmount)`: `external`. Splits feeAmount and transfers to treasuries.
* **Events:** `FeeRouted`.

### 3.11 `PausableGovernor.sol` (src/governance/)

* **Inherits:** `AccessControl`.
* **Purpose:** Centralized admin control for pausing/unpausing contracts.
* **Roles:** `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`.
* **State:** `mapping(address => bool) public pausableContracts;`
* **Key Functions:** `addPausableContract`, `removePausableContract`, `pause(target)`, `unpause(target)`.

### 3.12 `Constants.sol` (src/common/)

* **Purpose:** Defines shared constants.
* **Content:** Includes BPS, fee rates (Capital, Tiered Tx *without cap*, Tiered AUM), thresholds ($50k project value, tx fee tiers, AUM tiers), 20% deposit percent. *(Ensure TX_FEE_HARD_CAP constant is removed)*.

### 3.13 `Errors.sol` (src/common/)

* **Purpose:** Defines custom error types for gas efficiency and clarity.
* **Content:** Include errors like `NotAuthorized`, `NotVerified`, `InvalidAmount`, `DepositInsufficient`, `FundingCapReached`, `MilestoneNotAuthorized`, etc.

## 4. Data Structures (Core Structs)

*(Defined within relevant contracts or a shared `Structs.sol`)*

* `DevInfo` (`DeveloperRegistry`)
* `ProjectParams` (`ProjectFactory`)
* `PoolInfo` (`LiquidityPoolManager`)
* `LoanRecord` (`LiquidityPoolManager`)

## 5. System Flow & Interactions

*(High-level flow described previously remains accurate)*
* Developer Onboarding (Off-chain KYC -> On-chain Attestation)
* Project Listing (Factory checks -> Vault Deploy / Pool Trigger)
* Investment (Investor Deposits -> Vault/Pool receives)
* Funding Allocation (Pool selects -> Deploys Escrow -> Funds Escrow)
* Drawdown (Off-chain Auth -> Dev Withdraws from Escrow)
* Repayment (Dev -> RepaymentRouter -> Fees -> Vault/Pool)
* Claiming (Investor -> Vault/Pool)

## 6. External Integrations (Off-Chain Interactions)

* **KYC:** Off-chain verification -> On-chain attestation (hash/location only) via `DeveloperRegistry`.
* **Risk Oracle:** Off-chain analysis -> On-chain APR push via `RiskRateOracleAdapter`.
* **Milestone Authority:** Off-chain verification -> On-chain authorization via `DevEscrow`.
* **Coinbase Onramp:** DApp integration for fiat-to-USDC; contracts receive standard USDC transfers.
* **Gas Sponsoring:** Planned for *carbon* oracle; potentially applicable to finance oracle if needed via off-chain relayers.

## 7. Project File Structure (Foundry)
ongrid-finance/
├── foundry.toml
├── script/
│   ├── DeployMockUSDC.s.sol
│   ├── DeployCore.s.sol
│   └── UpgradeCore.s.sol
├── src/
│   ├── common/
│   │   ├── Errors.sol
│   │   ├── Constants.sol
│   │ # └── Structs.sol (Optional)
│   ├── token/
│   │   └── MockUSDC.sol
│   ├── registry/
│   │   └── DeveloperRegistry.sol
│   ├── escrow/
│   │   ├── DeveloperDepositEscrow.sol
│   │   └── DevEscrow.sol
│   ├── factory/
│   │   └── ProjectFactory.sol
│   ├── vault/
│   │   ├── DirectProjectVault.sol
│   │   └── LiquidityPoolManager.sol
│   ├── oracle/
│   │   └── RiskRateOracleAdapter.sol
│   ├── repayment/
│   │   ├── RepaymentRouter.sol
│   │   └── FeeRouter.sol
│   ├── governance/
│   │   └── PausableGovernor.sol
│   └── interfaces/
│       ├── IERC20.sol
│       ├── IDeveloperRegistry.sol
│       ├── IDeveloperDepositEscrow.sol
│       ├── IDevEscrow.sol
│     # ├── IProjectFactory.sol (Interaction via direct import likely sufficient)
│       ├── IProjectVault.sol
│       ├── ILiquidityPoolManager.sol
│     # ├── IRiskRateOracleAdapter.sol (Interaction via direct import likely sufficient)
│     # ├── IRepaymentRouter.sol (Interaction via direct import likely sufficient)
│       ├── IFeeRouter.sol
│       └── IPausableGovernor.sol
├── lib/ # Forge dependencies (OZ, Solmate, PRBMath, ForgeStd)
├── test/ # Excluded from this PRD
├── README.md
└── .env.example
*(Note: Interfaces might be less critical if contracts are within the same project and can import structs/errors directly, but define them if cross-contract calls are complex or for external interaction points).*

## 8. Documentation Strategy

1.  **README.md**: Project overview, setup, deployment.
2.  **NatSpec Comments**: Comprehensive // comments within Solidity code.
3.  **Architecture Diagram**: Separate visual aid.
4.  **This PRD**: Primary implementation specification.

## 9. Implementation Guidelines

* **Clarity for AI:** Use descriptive names, explicit comments, clear logic.
* **Security:** Apply best practices (ReentrancyGuard, Checks-Effects-Interactions, AccessControl, Pausable).
* **Gas Efficiency:** Use custom errors, optimize storage, use efficient math libraries (Solmate, PRBMath).
* **Events:** Emit detailed, indexed events for all state changes.
* **Modularity:** Maintain separation of concerns between contracts.
* **Upgradeability:** Implement UUPS correctly, manage storage layout carefully. Ensure deployment scripts (`script/`) handle deployment and wiring of dependencies and roles correctly.

