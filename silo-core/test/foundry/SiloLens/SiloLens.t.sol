// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {IInterestRateModel} from "silo-core/contracts/interfaces/IInterestRateModel.sol";
import {SiloLittleHelper} from "silo-core/test/foundry/_common/SiloLittleHelper.sol";
import {IDistributionManager} from "silo-core/contracts/incentives/interfaces/IDistributionManager.sol";
import {TokenHelper} from "silo-core/contracts/lib/TokenHelper.sol";
import {SiloLens} from "silo-core/contracts/SiloLens.sol";

/*
FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc SiloLensTest
*/
contract SiloLensTest is SiloLittleHelper, Test {
    uint256 internal constant _AMOUNT_COLLATERAL = 1000e18;
    uint256 internal constant _AMOUNT_PROTECTED = 1000e18;
    uint256 internal constant _AMOUNT_BORROW = 500e18;

    address internal _depositor = makeAddr("Depositor");
    address internal _borrower = makeAddr("Borrower");

    ISiloConfig internal _siloConfig;

    function setUp() public {
        _siloConfig = _setUpLocalFixture();

        _makeDeposit(silo1, token1, _AMOUNT_COLLATERAL, _depositor, ISilo.CollateralType.Collateral);

        _makeDeposit(silo1, token1, _AMOUNT_PROTECTED, _depositor, ISilo.CollateralType.Protected);

        _makeDeposit(silo0, token0, _AMOUNT_COLLATERAL, _borrower, ISilo.CollateralType.Collateral);

        vm.prank(_borrower);
        silo1.borrow(_AMOUNT_BORROW, _borrower, _borrower);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_SiloLens_getVersion_neverReverts
    */
    function test_SiloLens_getVersion_neverReverts(address _contract) public view {
        // forge found case when code length is 1: 0x00
        // for this address `getVersion` is reverting
        vm.assume(_contract.code.length != 1);
        SILO_LENS.getVersion(_contract);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_SiloLens_getVersion_version
    */
    function test_SiloLens_getVersion_version() public view {
        assertEq(SILO_LENS.getVersion(address(SILO_LENS)), SILO_LENS.VERSION(), "version should be the same");
    }
    
    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_SiloLens_getVersions
    */
    function test_SiloLens_getVersions() public view {
        address[] memory contracts = new address[](2);
        contracts[0] = address(SILO_LENS);
        contracts[1] = address(this);

        string[] memory versions = SILO_LENS.getVersions(contracts);
        assertEq(versions[0], SILO_LENS.VERSION(), "version should be the same");
        assertEq(versions[1], "legacy", "version should be legacy");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_SiloLens_getVersion_legacy
    */
    function test_SiloLens_getVersion_legacy() public view {
        assertEq(SILO_LENS.getVersion(address(this)), "legacy");
    }

    /*
        forge test -vvv --ffi --mt test_SiloLens_getInterestRateModel
    */
    function test_SiloLens_getInterestRateModel() public view {
        assertEq(SILO_LENS.getInterestRateModel(silo0), _siloConfig.getConfig(address(silo0)).interestRateModel);
        assertEq(SILO_LENS.getInterestRateModel(silo1), _siloConfig.getConfig(address(silo1)).interestRateModel);
    }

    /*
        FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_SiloLens_calculateProfitableLiquidation
    */
    function test_SiloLens_calculateProfitableLiquidation() public {
        IPartialLiquidation hook = IPartialLiquidation(IShareToken(address(silo1)).hookReceiver());

        uint256 ltv = SILO_LENS.getLtv(silo0, _borrower);
        assertEq(ltv, 0.5e18, "price is 1:1 so LTV is 50%, otherwise we need to adjust this test");

        (uint256 collateralToLiquidate, uint256 debtToCover) =
            SILO_LENS.calculateProfitableLiquidation(silo0, _borrower);

        assertEq(collateralToLiquidate, 0, "collateralToLiquidate is 0 when position is solvent");
        assertEq(debtToCover, 0, "debtToCover is 0 when position is solvent");

        vm.warp(block.timestamp + 3000 days);

        // insolvent but not bad debt position should return max debt to cover
        ltv = SILO_LENS.getLtv(silo0, _borrower);
        assertLt(ltv, 0.95e18, "LTV is less than 95% (to have some space for liquidation fee)");

        (collateralToLiquidate, debtToCover) = SILO_LENS.calculateProfitableLiquidation(silo0, _borrower);

        assertFalse(silo1.isSolvent(_borrower), "expected position to be insolvent");

        (uint256 maxCollateralToLiquidate, uint256 maxDebtToCover,) = hook.maxLiquidation(_borrower);

        assertEq(collateralToLiquidate, maxCollateralToLiquidate, "[collateral] collateral is always max");
        assertEq(
            debtToCover, _estimateDebtToCover(collateralToLiquidate), "[debt] debt should be calculated with profit"
        );

        vm.warp(block.timestamp + 1000 days);

        (maxCollateralToLiquidate, maxDebtToCover,) = hook.maxLiquidation(_borrower);

        ltv = SILO_LENS.getLtv(silo0, _borrower);
        assertGt(ltv, 1e18, "expect bad debt");

        (collateralToLiquidate, debtToCover) = SILO_LENS.calculateProfitableLiquidation(silo1, _borrower);
        assertEq(collateralToLiquidate, maxCollateralToLiquidate, "collateralToLiquidate is max collateral");
        assertEq(debtToCover, _estimateDebtToCover(collateralToLiquidate), "debt to cover must allow for profit");
    }

    /*
        FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_SiloLens_getOracleAddresses
    */
    function test_SiloLens_getOracleAddresses() public view {
        (address solvencyOracle, address maxLtvOracle) = (SILO_LENS.getOracleAddresses(silo0));
        assertEq(solvencyOracle, address(0), "solvencyOracle0");
        assertEq(maxLtvOracle, address(0), "maxLtvOracle0");

        (solvencyOracle, maxLtvOracle) = (SILO_LENS.getOracleAddresses(silo1));
        assertEq(solvencyOracle, address(0), "solvencyOracle1");
        assertEq(maxLtvOracle, address(0), "maxLtvOracle1");
    }

    /*
        forge test -vvv --ffi --mt test_SiloLens_getDepositAPR
    */
    function test_SiloLens_getDepositAPR() public view {
        assertEq(SILO_LENS.getDepositAPR(silo0), 0, "Deposit APR in silo0 equal to 0 because there is no debt");

        (,, uint256 daoFee, uint256 deployerFee) = SILO_LENS.getFeesAndFeeReceivers(silo1);

        assertTrue(daoFee > 0, "daoFee > 0");
        assertTrue(deployerFee > 0, "deployerFee > 0");

        uint256 depositAPR = SILO_LENS.getDepositAPR(silo1);
        uint256 borrowAPR = SILO_LENS.getBorrowAPR(silo1);
        assertTrue(depositAPR < borrowAPR, "depositAPR < borrowAPR because of fees");

        uint256 collateralAssets = silo1.getCollateralAssets();
        uint256 debtAssets = silo1.getDebtAssets();

        assertEq(
            depositAPR,
            // forge-lint: disable-next-line(divide-before-multiply)
            (borrowAPR * debtAssets / collateralAssets) * (10 ** 18 - daoFee - deployerFee) / 10 ** 18,
            "Deposit APR is borrow APR multiplied by debt/deposits minus fees"
        );
    }

    /*
        forge test -vvv --ffi --mt test_SiloLens_getBorrowAPR
    */
    function test_SiloLens_getBorrowAPR() public view {
        assertEq(SILO_LENS.getBorrowAPR(silo0), 0, "Borrow APR in silo0 equal to 0 because there is no debt");

        uint256 borrowAPR = SILO_LENS.getBorrowAPR(silo1);
        assertEq(borrowAPR, 70000000004304000, "Borrow APR in silo1 ~7% because of debt");

        IInterestRateModel irm = IInterestRateModel(SILO_LENS.getInterestRateModel(silo1));
        assertEq(borrowAPR, irm.getCurrentInterestRate(address(silo1), block.timestamp), "APR equal to IRM rate");
    }

    /*
        forge test -vvv --ffi --mt test_SiloLens_getRawLiquidity
    */
    function test_SiloLens_getRawLiquidity() public view {
        uint256 liquiditySilo0 = SILO_LENS.getRawLiquidity(silo0);
        assertEq(liquiditySilo0, _AMOUNT_COLLATERAL);

        uint256 liquiditySilo1 = SILO_LENS.getRawLiquidity(silo1);
        assertEq(liquiditySilo1, _AMOUNT_COLLATERAL - _AMOUNT_BORROW);
    }

    /*
        forge test -vvv --ffi --mt test_SiloLens_getMaxLtv
    */
    function test_SiloLens_getMaxLtv() public view {
        uint256 maxLtvSilo0 = SILO_LENS.getMaxLtv(silo0);
        assertEq(maxLtvSilo0, _siloConfig.getConfig(address(silo0)).maxLtv);

        uint256 maxLtvSilo1 = SILO_LENS.getMaxLtv(silo1);
        assertEq(maxLtvSilo1, _siloConfig.getConfig(address(silo1)).maxLtv);
    }

    /*
        forge test -vvv --ffi --mt test_SiloLens_getLt
    */
    function test_SiloLens_getLt() public view {
        uint256 ltSilo0 = SILO_LENS.getLt(silo0);
        assertEq(ltSilo0, _siloConfig.getConfig(address(silo0)).lt);

        uint256 ltSilo1 = SILO_LENS.getLt(silo1);
        assertEq(ltSilo1, _siloConfig.getConfig(address(silo1)).lt);
    }

    /*
        forge test -vvv --ffi --mt test_SiloLens_getLtv
    */
    function test_SiloLens_getLtv() public view {
        // due to initial state
        uint256 expectedLtv = _AMOUNT_BORROW * 100 / _AMOUNT_COLLATERAL * 1e18 / 100;

        uint256 ltvSilo0 = SILO_LENS.getLtv(silo0, _borrower);
        assertEq(ltvSilo0, expectedLtv);

        uint256 ltvSilo1 = SILO_LENS.getLtv(silo1, _borrower);
        assertEq(ltvSilo1, expectedLtv);
    }

    /*
        forge test -vvv --ffi --mt test_SiloLens_getFeesAndFeeReceivers
    */
    function test_SiloLens_getFeesAndFeeReceivers() public {
        // hardcoded in the silo config for the local testing
        address deployerFeeReceiverConfig = 0xdEDEDEDEdEdEdEDedEDeDedEdEdeDedEdEDedEdE;

        vm.warp(block.timestamp + 300 days);

        address daoFeeReceiver;
        address deployerFeeReceiver;
        uint256 daoFee;
        uint256 deployerFee;

        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        address deployer = vm.addr(deployerPrivateKey);

        (daoFeeReceiver, deployerFeeReceiver, daoFee, deployerFee) = SILO_LENS.getFeesAndFeeReceivers(silo0);

        assertEq(daoFeeReceiver, deployer);
        assertEq(deployerFeeReceiver, deployerFeeReceiverConfig);
        assertEq(daoFee, 150000000000000000);
        assertEq(deployerFee, 100000000000000000);

        (daoFeeReceiver, deployerFeeReceiver, daoFee, deployerFee) = SILO_LENS.getFeesAndFeeReceivers(silo1);

        assertEq(daoFeeReceiver, deployer);
        assertEq(deployerFeeReceiver, deployerFeeReceiverConfig);
        assertEq(daoFee, 150000000000000000);
        assertEq(deployerFee, 100000000000000000);
    }

    /*
        forge test -vvv --ffi --mt test_SiloLens_collateralBalanceOfUnderlying
    */
    function test_SiloLens_collateralBalanceOfUnderlying() public view {
        uint256 borrowerCollateralSilo0 = SILO_LENS.collateralBalanceOfUnderlying(silo0, _depositor);
        assertEq(borrowerCollateralSilo0, 0);

        uint256 borrowerCollateralSilo1 = SILO_LENS.collateralBalanceOfUnderlying(silo1, _depositor);
        assertEq(borrowerCollateralSilo1, _AMOUNT_COLLATERAL + _AMOUNT_PROTECTED);

        uint256 borrowerCollateralSilo0Ignored = SILO_LENS.collateralBalanceOfUnderlying(silo0, _depositor);

        assertEq(borrowerCollateralSilo0Ignored, 0);

        uint256 borrowerCollateralSilo1Ignored = SILO_LENS.collateralBalanceOfUnderlying(silo1, _depositor);

        assertEq(borrowerCollateralSilo1Ignored, _AMOUNT_COLLATERAL + _AMOUNT_PROTECTED);
    }

    /*
        forge test -vvv --ffi --mt test_SiloLens_debtBalanceOfUnderlying
    */
    function test_SiloLens_debtBalanceOfUnderlying() public view {
        uint256 borrowerDebtSilo0 = SILO_LENS.debtBalanceOfUnderlying(silo0, _borrower);
        assertEq(borrowerDebtSilo0, 0);

        uint256 borrowerDebtSilo1 = SILO_LENS.debtBalanceOfUnderlying(silo1, _borrower);
        assertEq(borrowerDebtSilo1, _AMOUNT_BORROW);

        uint256 borrowerDebtSilo0Ignored = SILO_LENS.debtBalanceOfUnderlying(silo0, _borrower);

        assertEq(borrowerDebtSilo0Ignored, 0);

        uint256 borrowerDebtSilo1Ignored = SILO_LENS.debtBalanceOfUnderlying(silo1, _borrower);

        assertEq(borrowerDebtSilo1Ignored, _AMOUNT_BORROW);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_SiloLens_getSiloIncentivesControllerProgramsNames -vvv
    */
    function test_SiloLens_getSiloIncentivesControllerProgramsNames() public {
        address token = 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f;

        vm.mockCall(token, abi.encodeWithSelector(IERC20.balanceOf.selector, address(SILO_LENS)), abi.encode(0));

        string memory expectedString = "0x5615deb798bb3e4dfa0139dfa1b3d433cc23b72f";
        // Safe: hex literal is converted to bytes32, which is a standard safe conversion.
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 programId = bytes32(hex"5615deb798bb3e4dfa0139dfa1b3d433cc23b72f");

        address siloIncentivesController = makeAddr("SiloIncentivesControllerCompatible");

        // to simulate what we have in the DistributionManager
        bytes memory withRemovedZeros = TokenHelper.removeZeros(abi.encodePacked(programId));

        string[] memory incentivesControllerProgramsNames = new string[](1);
        incentivesControllerProgramsNames[0] = string(withRemovedZeros);

        vm.mockCall(
            siloIncentivesController,
            abi.encodeWithSelector(IDistributionManager.getAllProgramsNames.selector),
            abi.encode(incentivesControllerProgramsNames)
        );

        string[] memory programsNames = SILO_LENS.getSiloIncentivesControllerProgramsNames(siloIncentivesController);
        assertEq(programsNames.length, 1);
        assertEq(programsNames[0], expectedString);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_SiloLens_forking_getSiloIncentivesControllerProgramsNames -vvv
    */
    function test_SiloLens_forking_getSiloIncentivesControllerProgramsNames() public {
        vm.createSelectFork(vm.envString("RPC_SONIC"), 26894678);

        address siloIncentivesController = 0xdc5B289bB15C3FEE96d106a607B13cCA8092F4F9;

        SiloLens localLens = new SiloLens();
        string[] memory programsNames = localLens.getSiloIncentivesControllerProgramsNames(siloIncentivesController);

        assertEq(programsNames.length, 2);
    }
    /*
    FOUNDRY_PROFILE=core_test \
        forge test --ffi --mt test_SiloLens_20BytesName_getSiloIncentivesControllerProgramsNames -vvv
    */

    function test_SiloLens_20BytesName_getSiloIncentivesControllerProgramsNames() public {
        string memory expectedString = "ssssssssssssssssssss";
        address siloIncentivesController = makeAddr("SiloIncentivesControllerCompatible");

        bytes memory nameBytes = bytes(expectedString);

        // Safe: nameBytes is always 20 bytes (address length) in this test context
        // forge-lint: disable-next-line(unsafe-typecast)
        address token = address(bytes20(nameBytes));

        vm.mockCallRevert(token, abi.encodeWithSelector(IERC20.balanceOf.selector, address(SILO_LENS)), abi.encode(0));

        // to simulate what we have in the DistributionManager
        string[] memory incentivesControllerProgramsNames = new string[](1);
        incentivesControllerProgramsNames[0] = expectedString;

        vm.mockCall(
            siloIncentivesController,
            abi.encodeWithSelector(IDistributionManager.getAllProgramsNames.selector),
            abi.encode(incentivesControllerProgramsNames)
        );

        string[] memory programsNames = SILO_LENS.getSiloIncentivesControllerProgramsNames(siloIncentivesController);
        assertEq(programsNames.length, 1);
        assertEq(programsNames[0], expectedString);
    }

    function _estimateDebtToCover(uint256 _collateralToLiquidate) internal pure returns (uint256) {
        // fee here is hardcoded
        return _collateralToLiquidate * 1e18 / (1e18 + 0.05e18);
    }
}
