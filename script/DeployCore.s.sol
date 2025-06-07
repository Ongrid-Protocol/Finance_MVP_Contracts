// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Interfaces
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IDeveloperRegistry} from "../src/interfaces/IDeveloperRegistry.sol";
import {IDeveloperDepositEscrow} from "../src/interfaces/IDeveloperDepositEscrow.sol";
import {IFeeRouter} from "../src/interfaces/IFeeRouter.sol";
import {ILiquidityPoolManager} from "../src/interfaces/ILiquidityPoolManager.sol";
import {IRiskRateOracleAdapter} from "../src/interfaces/IRiskRateOracleAdapter.sol";
import {IPausableGovernor} from "../src/interfaces/IPausableGovernor.sol";

// Implementations
import {DeveloperRegistry} from "../src/registry/DeveloperRegistry.sol";
import {DeveloperDepositEscrow} from "../src/escrow/DeveloperDepositEscrow.sol";
import {DevEscrow} from "../src/escrow/DevEscrow.sol";
import {DirectProjectVault} from "../src/vault/DirectProjectVault.sol";
import {FeeRouter} from "../src/repayment/FeeRouter.sol";
import {RepaymentRouter} from "../src/repayment/RepaymentRouter.sol";
import {RiskRateOracleAdapter} from "../src/oracle/RiskRateOracleAdapter.sol";
import {LiquidityPoolManager} from "../src/vault/LiquidityPoolManager.sol";
import {ProjectFactory} from "../src/factory/ProjectFactory.sol";
import {PausableGovernor} from "../src/governance/PausableGovernor.sol";

// Common
import {Constants} from "../src/common/Constants.sol";

contract DeployCore is Script {
    // --- Environment Variables ---
    address USDC_ADDRESS;

    // Admin Addresses (Set these via env or directly)
    address PROTOCOL_TREASURY_ADMIN;
    address CARBON_TREASURY_ADMIN;
    address KYC_ADMIN;
    address ORACLE_ADMIN;
    address PAUSER_ADMIN_FOR_CLONES;
    address ADMIN_FOR_VAULT_CLONES;
    address SLASHING_ADMIN; // For DeveloperDepositEscrow

    // Deployed Contract Addresses
    IDeveloperRegistry developerRegistryProxy;
    DeveloperDepositEscrow developerDepositEscrowContract; // Use concrete type for direct calls
    address devEscrowImplementationAddress;
    address directProjectVaultImplementationAddress;
    IFeeRouter feeRouterProxy;
    RepaymentRouter repaymentRouterContract; // Use concrete type
    IRiskRateOracleAdapter riskRateOracleAdapterProxy;
    ILiquidityPoolManager liquidityPoolManagerProxy;
    ProjectFactory projectFactoryProxy; // Use concrete type for setAddresses
    PausableGovernor pausableGovernorContract; // Use concrete type

    function setUp() public {
        USDC_ADDRESS = vm.envAddress("USDC_ADDRESS");

        PROTOCOL_TREASURY_ADMIN = vm.envAddress("PROTOCOL_TREASURY_ADMIN");
        CARBON_TREASURY_ADMIN = vm.envAddress("CARBON_TREASURY_ADMIN");
        KYC_ADMIN = vm.envAddress("KYC_ADMIN");
        ORACLE_ADMIN = vm.envAddress("ORACLE_ADMIN");
        PAUSER_ADMIN_FOR_CLONES = vm.envAddress("PAUSER_ADMIN_FOR_CLONES");
        ADMIN_FOR_VAULT_CLONES = vm.envAddress("ADMIN_FOR_VAULT_CLONES");
        SLASHING_ADMIN = vm.envAddress("SLASHING_ADMIN");

        if (USDC_ADDRESS == address(0)) {
            revert("USDC_ADDRESS not set in .env");
        }
        if (
            PROTOCOL_TREASURY_ADMIN == address(0) || CARBON_TREASURY_ADMIN == address(0) || KYC_ADMIN == address(0)
                || ORACLE_ADMIN == address(0) || PAUSER_ADMIN_FOR_CLONES == address(0)
                || ADMIN_FOR_VAULT_CLONES == address(0) || SLASHING_ADMIN == address(0)
        ) {
            revert("One or more admin addresses not set in .env");
        }
    }

    function run() public {
        address deployer = 0x0a1978f4CeC6AfA754b6Fa11b7D141e529b22741;
        vm.startBroadcast();

        console.log("Deployer Address (from --account):", deployer);
        console.log("USDC Address:", USDC_ADDRESS);

        console.log("\n--- Phase 1: Deploying Core Logic & Base Contracts ---");

        DeveloperRegistry devRegistryImpl = new DeveloperRegistry();
        bytes memory devRegistryInitData = abi.encodeWithSelector(DeveloperRegistry.initialize.selector, deployer);
        developerRegistryProxy =
            IDeveloperRegistry(address(new ERC1967Proxy(address(devRegistryImpl), devRegistryInitData)));
        console.log("DeveloperRegistry (Proxy) deployed at:", address(developerRegistryProxy));
        console.log("DeveloperRegistry (Impl) deployed at:", address(devRegistryImpl));

        developerDepositEscrowContract = new DeveloperDepositEscrow(USDC_ADDRESS);
        console.log("DeveloperDepositEscrow deployed at:", address(developerDepositEscrowContract));

        devEscrowImplementationAddress = address(new DevEscrow());
        console.log("DevEscrow Implementation deployed at:", devEscrowImplementationAddress);

        directProjectVaultImplementationAddress = address(new DirectProjectVault());
        console.log("DirectProjectVault Implementation deployed at:", directProjectVaultImplementationAddress);

        console.log("\n--- Phase 2: Deploying Routers & Adapters ---");

        FeeRouter feeRouterImpl = new FeeRouter();
        bytes memory feeRouterInitData = abi.encodeWithSelector(
            FeeRouter.initialize.selector,
            deployer,
            USDC_ADDRESS,
            address(developerRegistryProxy),
            PROTOCOL_TREASURY_ADMIN,
            CARBON_TREASURY_ADMIN
        );
        feeRouterProxy = IFeeRouter(address(new ERC1967Proxy(address(feeRouterImpl), feeRouterInitData)));
        console.log("FeeRouter (Proxy) deployed at:", address(feeRouterProxy));
        console.log("FeeRouter (Impl) deployed at:", address(feeRouterImpl));

        repaymentRouterContract = new RepaymentRouter(deployer, USDC_ADDRESS, address(feeRouterProxy));
        console.log("RepaymentRouter deployed at:", address(repaymentRouterContract));

        RiskRateOracleAdapter riskAdapterImpl = new RiskRateOracleAdapter();
        bytes memory riskAdapterInitData = abi.encodeWithSelector(RiskRateOracleAdapter.initialize.selector, deployer);
        riskRateOracleAdapterProxy =
            IRiskRateOracleAdapter(address(new ERC1967Proxy(address(riskAdapterImpl), riskAdapterInitData)));
        console.log("RiskRateOracleAdapter (Proxy) deployed at:", address(riskRateOracleAdapterProxy));
        console.log("RiskRateOracleAdapter (Impl) deployed at:", address(riskAdapterImpl));

        console.log("\n--- Phase 3: Deploying Managers & Main Factory ---");

        LiquidityPoolManager lpmImpl = new LiquidityPoolManager();
        bytes memory lpmInitData = abi.encodeWithSelector(
            LiquidityPoolManager.initialize.selector,
            deployer,
            USDC_ADDRESS,
            address(feeRouterProxy),
            address(developerRegistryProxy),
            address(riskRateOracleAdapterProxy),
            devEscrowImplementationAddress,
            address(repaymentRouterContract),
            address(developerDepositEscrowContract),
            PROTOCOL_TREASURY_ADMIN
        );
        liquidityPoolManagerProxy = ILiquidityPoolManager(address(new ERC1967Proxy(address(lpmImpl), lpmInitData)));
        console.log("LiquidityPoolManager (Proxy) deployed at:", address(liquidityPoolManagerProxy));
        console.log("LiquidityPoolManager (Impl) deployed at:", address(lpmImpl));

        ProjectFactory projectFactoryImpl = new ProjectFactory();
        bytes memory projectFactoryInitData = abi.encodeWithSelector(
            ProjectFactory.initialize.selector,
            address(developerRegistryProxy),
            address(developerDepositEscrowContract),
            USDC_ADDRESS,
            deployer
        );
        projectFactoryProxy =
            ProjectFactory(address(new ERC1967Proxy(address(projectFactoryImpl), projectFactoryInitData)));
        console.log("ProjectFactory (Proxy) deployed at:", address(projectFactoryProxy));
        console.log("ProjectFactory (Impl) deployed at:", address(projectFactoryImpl));

        console.log("Configuring ProjectFactory addresses...");
        projectFactoryProxy.setAddresses(
            address(liquidityPoolManagerProxy),
            directProjectVaultImplementationAddress,
            devEscrowImplementationAddress,
            address(repaymentRouterContract),
            PAUSER_ADMIN_FOR_CLONES,
            ADMIN_FOR_VAULT_CLONES,
            address(riskRateOracleAdapterProxy),
            address(feeRouterProxy)
        );
        console.log("ProjectFactory addresses configured.");

        console.log("\n--- Phase 4: Deploying Governance Contract ---");

        pausableGovernorContract = new PausableGovernor(deployer);
        console.log("PausableGovernor deployed at:", address(pausableGovernorContract));

        console.log("\n--- Phase 5: Assigning Roles & Permissions ---");

        console.log("Assigning roles on DeveloperRegistry...");
        DeveloperRegistry(address(developerRegistryProxy)).grantRole(Constants.KYC_ADMIN_ROLE, KYC_ADMIN);
        DeveloperRegistry(address(developerRegistryProxy)).grantRole(
            Constants.PROJECT_HANDLER_ROLE, address(projectFactoryProxy)
        );
        DeveloperRegistry(address(developerRegistryProxy)).grantRole(
            Constants.PROJECT_HANDLER_ROLE, address(liquidityPoolManagerProxy)
        );
        console.log("DeveloperRegistry roles assigned.");

        console.log("Assigning roles on DeveloperDepositEscrow...");
        developerDepositEscrowContract.grantRole(Constants.DEPOSIT_FUNDER_ROLE, address(projectFactoryProxy));
        developerDepositEscrowContract.grantRole(Constants.DEPOSIT_FUNDER_ROLE, address(liquidityPoolManagerProxy));
        developerDepositEscrowContract.setRoleAdminExternally(Constants.RELEASER_ROLE, Constants.DEFAULT_ADMIN_ROLE);
        developerDepositEscrowContract.grantRole(Constants.RELEASER_ROLE, deployer);
        developerDepositEscrowContract.grantRole(Constants.RELEASER_ROLE, address(projectFactoryProxy));
        developerDepositEscrowContract.grantRole(Constants.RELEASER_ROLE, address(liquidityPoolManagerProxy));
        developerDepositEscrowContract.grantRole(Constants.SLASHER_ROLE, SLASHING_ADMIN);
        console.log("DeveloperDepositEscrow roles assigned.");

        console.log("Assigning roles on FeeRouter...");
        FeeRouter(address(feeRouterProxy)).grantRole(Constants.REPAYMENT_ROUTER_ROLE, address(repaymentRouterContract));
        FeeRouter(address(feeRouterProxy)).grantRole(Constants.PROJECT_HANDLER_ROLE, address(projectFactoryProxy));
        FeeRouter(address(feeRouterProxy)).grantRole(Constants.PROJECT_HANDLER_ROLE, address(liquidityPoolManagerProxy));
        console.log("FeeRouter roles assigned.");

        console.log("Assigning roles on RepaymentRouter...");
        repaymentRouterContract.grantRole(Constants.PROJECT_HANDLER_ROLE, address(projectFactoryProxy));
        repaymentRouterContract.grantRole(Constants.PROJECT_HANDLER_ROLE, address(liquidityPoolManagerProxy));
        console.log("RepaymentRouter roles assigned.");

        console.log("Assigning ORACLE_ROLE on RiskRateOracleAdapter to specific oracle admin...");
        RiskRateOracleAdapter(address(riskRateOracleAdapterProxy)).grantRole(Constants.RISK_ORACLE_ROLE, ORACLE_ADMIN);
        console.log("RiskRateOracleAdapter ORACLE_ROLE assigned.");

        console.log("Assigning PROJECT_HANDLER_ROLE on RiskRateOracleAdapter to ProjectFactory and LPM...");
        RiskRateOracleAdapter(address(riskRateOracleAdapterProxy)).grantRole(
            Constants.PROJECT_HANDLER_ROLE, address(projectFactoryProxy)
        );
        RiskRateOracleAdapter(address(riskRateOracleAdapterProxy)).grantRole(
            Constants.PROJECT_HANDLER_ROLE, address(liquidityPoolManagerProxy)
        );
        console.log("RiskRateOracleAdapter PROJECT_HANDLER_ROLE for target setting assigned.");

        console.log("Assigning roles on LiquidityPoolManager...");
        LiquidityPoolManager(address(liquidityPoolManagerProxy)).grantRole(
            Constants.PROJECT_HANDLER_ROLE, address(projectFactoryProxy)
        );
        LiquidityPoolManager(address(liquidityPoolManagerProxy)).grantRole(
            Constants.RISK_ORACLE_ROLE, address(riskRateOracleAdapterProxy)
        );
        console.log("LiquidityPoolManager roles assigned.");

        console.log("Granting PAUSER_ROLE to PausableGovernor...");
        DeveloperRegistry(address(developerRegistryProxy)).grantRole(
            Constants.PAUSER_ROLE, address(pausableGovernorContract)
        );
        developerDepositEscrowContract.grantRole(Constants.PAUSER_ROLE, address(pausableGovernorContract));
        projectFactoryProxy.grantRole(Constants.PAUSER_ROLE, address(pausableGovernorContract));
        LiquidityPoolManager(address(liquidityPoolManagerProxy)).grantRole(
            Constants.PAUSER_ROLE, address(pausableGovernorContract)
        );
        repaymentRouterContract.grantRole(Constants.PAUSER_ROLE, address(pausableGovernorContract));
        console.log("PAUSER_ROLE granted to PausableGovernor.");

        console.log("Configuring PausableGovernor...");
        pausableGovernorContract.addPausableContract(address(developerRegistryProxy));
        pausableGovernorContract.addPausableContract(address(developerDepositEscrowContract));
        pausableGovernorContract.addPausableContract(address(projectFactoryProxy));
        pausableGovernorContract.addPausableContract(address(liquidityPoolManagerProxy));
        pausableGovernorContract.addPausableContract(address(repaymentRouterContract));
        console.log("PausableGovernor configured.");

        vm.stopBroadcast();

        console.log("\n--- Deployment Summary ---");
        console.log("DeveloperRegistry Proxy:", address(developerRegistryProxy));
        console.log("DeveloperDepositEscrow:", address(developerDepositEscrowContract));
        console.log("DevEscrow Impl:", devEscrowImplementationAddress);
        console.log("DirectProjectVault Impl:", directProjectVaultImplementationAddress);
        console.log("FeeRouter Proxy:", address(feeRouterProxy));
        console.log("RepaymentRouter:", address(repaymentRouterContract));
        console.log("RiskRateOracleAdapter Proxy:", address(riskRateOracleAdapterProxy));
        console.log("LiquidityPoolManager Proxy:", address(liquidityPoolManagerProxy));
        console.log("ProjectFactory Proxy:", address(projectFactoryProxy));
        console.log("PausableGovernor:", address(pausableGovernorContract));
        console.log("---------------------------");
        console.log("Deployment and configuration complete!");
    }
}
