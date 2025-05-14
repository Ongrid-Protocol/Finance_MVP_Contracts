# Smart Contract Integration Guide for Frontend Developers

## Introduction

This guide provides a step-by-step approach to integrating the OnGrid Finance smart contracts with the frontend for developer and investor flows. It details the key functions to call, events to listen for, and data formats for inputs and outputs.

**Assumptions:**
* You have the ABIs for all contracts.
* You have the deployed contract addresses.
* You are using a library like Ethers.js or Viem in TypeScript to interact with the contracts.

**Data Type Mapping (Solidity -> TypeScript):**
* `address`: `string` (e.g., "0x123...")
* `uint256`, `uint64`, `uint48`, `uint32`, `uint16`, `uint8`: `bigint` (use `BigInt("value")` or handle as `string` for display and convert to `bigint` for contract calls).
* `bytes32`, `bytes4`, `bytes`: `string` (hexadecimal, e.g., "0xabc...")
* `bool`: `boolean`
* `string`: `string`
* `tuple`: `object`
* `array` (e.g., `address[]`): `Array<type>` (e.g., `string[]`)

---

## User Flow Integration

### Flow 1: Developer Project Creation

This flow allows verified developers to create new projects which are then either funded directly through a vault (high-value) or through a liquidity pool (low-value).

#### Prerequisites
* Developer must be KYC verified in the `DeveloperRegistry`
* Developer must have sufficient USDC for the 20% deposit
* Developer must approve the `DeveloperDepositEscrow` contract to spend their USDC

#### Integration Steps

1. **Check Developer Verification Status**
   ```typescript
   const isVerified = await developerRegistryContract.isVerified(developerAddress);
   if (!isVerified) {
     // Show KYC verification required message
     return;
   }
   ```

2. **Create Project Form**
   * Form inputs:
     * `loanAmountRequested`: Total project cost (100% amount)
     * `requestedTenor`: Loan duration in days
     * `metadataCID`: IPFS CID of project metadata

3. **Approve USDC for Deposit**
   * Calculate deposit amount (20% of `loanAmountRequested`)
   ```typescript
   const depositAmount = BigInt(loanAmountRequested) * BigInt(2000) / BigInt(10000); // 20%
   await usdcContract.approve(developerDepositEscrowAddress, depositAmount);
   ```

4. **Create Project**
   ```typescript
   const params = {
     loanAmountRequested: loanAmount,
     requestedTenor: tenorDays,
     metadataCID: cid
   };
   const tx = await projectFactoryContract.createProject(params);
   const receipt = await tx.wait();
   ```

5. **Determine Project Type from Events**
   * Listen for either `ProjectCreated` (high-value) or `LowValueProjectSubmitted` (low-value) events
   ```typescript
   const projectCreatedEvent = receipt.events?.find(e => e.event === 'ProjectCreated');
   const lowValueEvent = receipt.events?.find(e => e.event === 'LowValueProjectSubmitted');
   
   if (projectCreatedEvent) {
     // High-value project (direct vault)
     const { projectId, vaultAddress, devEscrowAddress, loanAmount } = projectCreatedEvent.args;
     // Store these addresses for future interactions
   } else if (lowValueEvent) {
     // Low-value project (liquidity pool)
     const { projectId, poolId, success } = lowValueEvent.args;
     // Note: success indicates if funding was immediate or requires waiting
   }
   ```

### Flow 2: Investor Funding (DirectProjectVault)

Investors can deposit USDC to fund high-value projects through their designated vaults.

#### Prerequisites
* Investor must have sufficient USDC
* Investor must approve the vault contract to spend their USDC

#### Integration Steps

1. **Display Vault Funding Status**
   ```typescript
   const vaultContract = new ethers.Contract(vaultAddress, vaultABI, provider);
   const totalAssetsInvested = await vaultContract.getTotalAssetsInvested();
   const loanAmount = await vaultContract.getLoanAmount();
   const isFundingClosed = await vaultContract.isFundingClosed();
   const fundingPercentage = totalAssetsInvested * 100n / loanAmount;
   ```

2. **Approve USDC for Investment**
   ```typescript
   await usdcContract.approve(vaultAddress, investmentAmount);
   ```

3. **Invest in Vault**
   ```typescript
   const tx = await vaultContract.invest(investmentAmount);
   const receipt = await tx.wait();
   ```

4. **Track Investment Success**
   * Listen for `Invested` event
   ```typescript
   const investedEvent = receipt.events?.find(e => e.event === 'Invested');
   if (investedEvent) {
     const { investor, amountInvested, totalAssetsInvested } = investedEvent.args;
     // Update UI with investment status
   }
   ```

5. **Monitor Funding Completion**
   * Listen for `FundingClosed` event to know when funding goal is reached
   ```typescript
   vaultContract.on('FundingClosed', (projectId, totalAssetsInvested) => {
     // Update UI to show funding is complete
   });
   ```

### Flow 3: Investor Pool Participation (LiquidityPoolManager)

Investors can participate in pools that fund low-value projects.

#### Prerequisites
* Investor must have sufficient USDC
* Investor must approve the LiquidityPoolManager to spend their USDC

#### Integration Steps

1. **Display Available Pools**
   ```typescript
   const poolCount = await liquidityPoolManagerContract.poolCount();
   const pools = [];
   
   for (let i = 1; i <= poolCount; i++) {
     try {
       const poolInfo = await liquidityPoolManagerContract.getPoolInfo(i);
       if (poolInfo.exists) {
         pools.push({
           poolId: i,
           name: poolInfo.name,
           totalAssets: poolInfo.totalAssets,
           totalShares: poolInfo.totalShares
         });
       }
     } catch {
       // Skip non-existent pools
     }
   }
   ```

2. **Approve USDC for Pool Deposit**
   ```typescript
   await usdcContract.approve(liquidityPoolManagerAddress, depositAmount);
   ```

3. **Deposit to Pool**
   ```typescript
   const tx = await liquidityPoolManagerContract.depositToPool(poolId, depositAmount);
   const receipt = await tx.wait();
   ```

4. **Track Deposit Success**
   * Listen for `PoolDeposit` event
   ```typescript
   const depositEvent = receipt.events?.find(e => e.event === 'PoolDeposit');
   if (depositEvent) {
     const { poolId, investor, assetsDeposited, sharesMinted } = depositEvent.args;
     // Update UI with deposit status and shares
   }
   ```

5. **Redeem Shares from Pool**
   ```typescript
   const userShares = await liquidityPoolManagerContract.getUserShares(poolId, userAddress);
   const tx = await liquidityPoolManagerContract.redeem(poolId, sharesToRedeem);
   const receipt = await tx.wait();
   ```

6. **Track Redemption Success**
   * Listen for `PoolRedeem` event
   ```typescript
   const redeemEvent = receipt.events?.find(e => e.event === 'PoolRedeem');
   if (redeemEvent) {
     const { poolId, redeemer, sharesBurned, assetsWithdrawn } = redeemEvent.args;
     // Update UI with redemption status
   }
   ```

### Flow 4: Developer Loan Repayment

Developers repay their loans through the RepaymentRouter, which automatically handles fee calculations and routing.

#### Prerequisites
* Developer must have sufficient USDC for repayment
* Developer must approve the RepaymentRouter to spend their USDC

#### Integration Steps

1. **Display Loan Repayment Status**
   * For DirectProjectVault projects:
   ```typescript
   const outstandingPrincipal = await vaultContract.getLoanAmount() - await vaultContract.getPrincipalRepaid();
   const isLoanClosed = await vaultContract.isLoanClosed();
   ```
   
   * For LiquidityPoolManager projects:
   ```typescript
   const loanRecord = await liquidityPoolManagerContract.getPoolLoanRecord(poolId, projectId);
   const outstandingPrincipal = loanRecord.principal - loanRecord.principalRepaid;
   const isActive = loanRecord.isActive;
   ```

2. **Get Next Payment Information**
   ```typescript
   const [dueDate, paymentAmount] = await feeRouterContract.getNextPaymentInfo(projectId);
   const dueDateFormatted = new Date(Number(dueDate) * 1000).toLocaleDateString();
   ```

3. **Approve USDC for Repayment**
   ```typescript
   await usdcContract.approve(repaymentRouterAddress, repaymentAmount);
   ```

4. **Make Repayment**
   ```typescript
   const tx = await repaymentRouterContract.repay(projectId, repaymentAmount);
   const receipt = await tx.wait();
   ```

5. **Track Repayment Success**
   * Listen for `RepaymentRouted` event
   ```typescript
   const repaymentEvent = receipt.events?.find(e => e.event === 'RepaymentRouted');
   if (repaymentEvent) {
     const { 
       projectId, 
       payer, 
       totalAmountRepaid, 
       feeAmount, 
       principalAmount, 
       interestAmount, 
       fundingSource 
     } = repaymentEvent.args;
     // Update UI with repayment breakdown
   }
   ```

6. **Track Loan Status Changes**
   * For DirectProjectVault, listen for `LoanClosed` event
   ```typescript
   vaultContract.on('LoanClosed', (projectId, finalPrincipalRepaid, finalInterestAccrued) => {
     // Update UI to show loan is closed
   });
   ```

### Flow 5: Investor Yield & Principal Claims (DirectProjectVault)

Investors claim their principal and yields from repaid vault loans.

#### Integration Steps

1. **Display Claimable Amounts**
   ```typescript
   const claimablePrincipal = await vaultContract.claimablePrincipal(investorAddress);
   const claimableYield = await vaultContract.claimableYield(investorAddress);
   ```

2. **Claim Both Principal and Yield**
   ```typescript
   const tx = await vaultContract.redeem();
   const receipt = await tx.wait();
   ```

3. **Track Claim Success**
   * Listen for `PrincipalClaimed` and `YieldClaimed` events
   ```typescript
   const principalEvent = receipt.events?.find(e => e.event === 'PrincipalClaimed');
   const yieldEvent = receipt.events?.find(e => e.event === 'YieldClaimed');
   
   if (principalEvent) {
     const { investor, amountClaimed } = principalEvent.args;
     // Update UI with principal claim
   }
   
   if (yieldEvent) {
     const { investor, amountClaimed } = yieldEvent.args;
     // Update UI with yield claim
   }
   ```

4. **Alternative: Claim Principal or Yield Separately**
   ```typescript
   // To claim only principal
   const principalTx = await vaultContract.claimPrincipal();
   // To claim only yield
   const yieldTx = await vaultContract.claimYield();
   ```

## Event Monitoring (All User Interfaces)

To provide a responsive user experience, the frontend should monitor key events:

### Global Project Events
* `ProjectCreated` from ProjectFactory - High-value project created
* `LowValueProjectSubmitted` from ProjectFactory - Low-value project submitted

### Vault & Investor Events
* `Invested` from DirectProjectVault - Investment received
* `FundingClosed` from DirectProjectVault - Vault funding completed
* `RepaymentReceived` from DirectProjectVault - Repayment processed
* `PrincipalClaimed`, `YieldClaimed` from DirectProjectVault - Investor claims

### Pool & LP Events
* `PoolCreated`, `PoolDeposit`, `PoolRedeem` from LiquidityPoolManager - Pool activity
* `PoolProjectFunded` from LiquidityPoolManager - Project funded by pool
* `PoolRepaymentReceived` from LiquidityPoolManager - Repayment to pool

### Repayment Events
* `RepaymentRouted` from RepaymentRouter - Repayment processed
* `FeeRouted` from FeeRouter - Fees distributed

### Deposit Events
* `DepositFunded`, `DepositReleased`, `DepositSlashed` from DeveloperDepositEscrow - Deposit status

Setting up event listeners for these events will ensure the UI stays current with on-chain state changes.