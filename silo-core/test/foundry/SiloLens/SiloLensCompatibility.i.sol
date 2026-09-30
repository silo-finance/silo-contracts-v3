// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {SiloLensDeploy} from "silo-core/deploy/SiloLensDeploy.s.sol";
import {ISiloLens} from "silo-core/contracts/interfaces/ISiloLens.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";

import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {SiloDeployments} from "silo-core/deploy/silo/SiloDeployments.sol";

/*
FOUNDRY_PROFILE=core_test forge test --mc SiloLensCompatibilityTest --ffi -vv
*/
contract SiloLensCompatibilityTest is IntegrationTest {
    ISiloLens internal _lens;
    address internal _borrower = makeAddr("borrower");

    string[] internal _chainsToTest;
    mapping(string chainAlias => ISilo[] silos) internal _siloAddresses;
    mapping(string chainAlias => ISiloConfig[] siloConfigs) internal _siloConfigs;
    mapping(ISilo silo => IPartialLiquidation hookReceiver) internal _hookReceivers;
    mapping(bytes4 sig => bool isTested) internal _testedFunctions;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_SONIC"));

        SiloLensDeploy deploy = new SiloLensDeploy();
        deploy.disableDeploymentsSync();
        _lens = deploy.run();

        _initializeSilosForChain(ChainsLib.SONIC_ALIAS);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_siloLens_compatibility --ffi -vv
    */
    function test_siloLens_compatibility() public {
        uint256 chainsLength = _chainsToTest.length;

        for (uint256 i = 0; i < chainsLength; i++) {
            string memory chainAlias = _chainsToTest[i];
            uint256 silosLength = _siloAddresses[chainAlias].length;

            for (uint256 j = 0; j < silosLength; j++) {
                ISilo silo = _siloAddresses[chainAlias][j];
                _testSilo(silo);
            }

            uint256 siloConfigsLength = _siloConfigs[chainAlias].length;

            for (uint256 k = 0; k < siloConfigsLength; k++) {
                ISiloConfig siloConfig = _siloConfigs[chainAlias][k];
                _testSiloConfig(siloConfig);
            }
        }

        _ensureAllFunctionsAreTested();
    }

    function _testSilo(ISilo _silo) internal {
        _testFn(_isSolvent, _silo, _borrower);
        _testFn(_liquidity, _silo);
        _testFn(_getRawLiquidity, _silo);
        _testFn(_getMaxLtv, _silo);
        _testFn(_calculateProfitableLiquidation, _silo, _borrower);
        _testFn(_getLt, _silo);
        _testFn(_getUserLT, _silo, _borrower);
        _testFn(_getUserLTBorrowersArray, _silo);
        _testFn(_getUsersHealth, _silo);
        _testFn(_getUserLTV, _silo, _borrower);
        _testFn(_getLtv, _silo, _borrower);
        _testFn(_collateralBalanceOfUnderlying, _silo, _borrower);
        _testFn(_debtBalanceOfUnderlying, _silo, _borrower);
        _testFn(_totalDeposits, _silo);
        _testFn(_totalDepositsWithInterest, _silo);
        _testFn(_totalBorrowAmountWithInterest, _silo);
        _testFn(_collateralOnlyDeposits, _silo);
        _testFn(_getDepositAmount, _silo, _borrower);
        _testFn(_totalBorrowAmount, _silo);
        _testFn(_totalBorrowShare, _silo);
        _testFn(_getBorrowAmount, _silo, _borrower);
        _testFn(_borrowShare, _silo, _borrower);
        _testFn(_protocolFees, _silo);
        _testFn(_getUtilization, _silo);
        _testFn(_getInterestRateModel, _silo);
        _testFn(_getBorrowAPR, _silo);
        _testFn(_getDepositAPR, _silo);
        _testFn(_getAPRs, _silo);
        _testFn(_getModel, _silo);
        _testFn(_maxLiquidation, _silo, _borrower);
        _testFn(_getFeesAndFeeReceivers, _silo);
        _testFn(_getSiloIncentivesControllerProgramsNames);
        _testFn(_getOracleAddresses, _silo);
        _testFn(_VERSION);
        _testFn(_getVersion, address(_silo));
        _testFn(_getVersions, address(_silo));
    }

    function _testSiloConfig(ISiloConfig _siloConfig) internal {
        _testFn(_hasPosition, _siloConfig, _borrower);
        _testFn(_inDebt, _siloConfig, _borrower);
        _testFn(_calculateCollateralValue, _siloConfig, _borrower);
        _testFn(_calculateBorrowValue, _siloConfig, _borrower);
    }

    function _testFn(function(ISilo,address) internal view returns (bytes4) func, ISilo _silo, address _user)
        internal
    {
        bytes4 sig = func(_silo, _user);
        _testedFunctions[sig] = true;
    }

    function _testFn(function(ISilo) internal view returns (bytes4) func, ISilo _silo) internal {
        bytes4 sig = func(_silo);
        _testedFunctions[sig] = true;
    }

    function _testFn(
        function(ISiloConfig,address) internal view returns (bytes4) func,
        ISiloConfig _siloConfig,
        address _user
    ) internal {
        bytes4 sig = func(_siloConfig, _user);
        _testedFunctions[sig] = true;
    }

    function _testFn(function() internal view returns (bytes4) func) internal {
        bytes4 sig = func();
        _testedFunctions[sig] = true;
    }
    
    function _testFn(function(address) internal view returns (bytes4) func, address _contract) internal {
        bytes4 sig = func(_contract);
        _testedFunctions[sig] = true;
    }

    function _isSolvent(ISilo _silo, address _user) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.isSolvent(_silo, _user);
        sig = ISiloLens.isSolvent.selector;
    }

    function _liquidity(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.liquidity(_silo);
        sig = ISiloLens.liquidity.selector;
    }

    function _getRawLiquidity(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.getRawLiquidity(_silo);
        sig = ISiloLens.getRawLiquidity.selector;
    }

    function _getMaxLtv(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.getMaxLtv(_silo);
        sig = ISiloLens.getMaxLtv.selector;
    }

    function _getLt(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.getLt(_silo);
        sig = ISiloLens.getLt.selector;
    }

    function _getUserLT(ISilo _silo, address _user) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.getUserLT(_silo, _user);
        sig = bytes4(keccak256("getUserLT(address,address)"));
    }

    function _getUserLTBorrowersArray(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        ISiloLens.Borrower[] memory borrowers = new ISiloLens.Borrower[](1);
        borrowers[0] = ISiloLens.Borrower({silo: _silo, wallet: _borrower});
        _lens.getUsersLT(borrowers);
        sig = bytes4(keccak256("getUsersLT((address,address)[])"));
    }

    function _getUsersHealth(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        ISiloLens.Borrower[] memory borrowers = new ISiloLens.Borrower[](1);
        borrowers[0] = ISiloLens.Borrower({silo: _silo, wallet: _borrower});
        _lens.getUsersHealth(borrowers);
        sig = ISiloLens.getUsersHealth.selector;
    }

    function _getUserLTV(ISilo _silo, address _user) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.getUserLTV(_silo, _user);
        sig = ISiloLens.getUserLTV.selector;
    }

    function _getLtv(ISilo _silo, address _user) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.getLtv(_silo, _user);
        sig = ISiloLens.getLtv.selector;
    }

    function _hasPosition(ISiloConfig _siloConfig, address _user) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.hasPosition(_siloConfig, _user);
        sig = ISiloLens.hasPosition.selector;
    }

    function _inDebt(ISiloConfig _siloConfig, address _user) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.inDebt(_siloConfig, _user);
        sig = ISiloLens.inDebt.selector;
    }

    function _calculateProfitableLiquidation(ISilo _silo, address _user) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.calculateProfitableLiquidation(_silo, _user);
        sig = ISiloLens.calculateProfitableLiquidation.selector;
    }

    function _getFeesAndFeeReceivers(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.getFeesAndFeeReceivers(_silo);
        sig = ISiloLens.getFeesAndFeeReceivers.selector;
    }

    function _collateralBalanceOfUnderlying(ISilo _silo, address _user) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.collateralBalanceOfUnderlying(_silo, _user);
        sig = ISiloLens.collateralBalanceOfUnderlying.selector;
    }

    function _debtBalanceOfUnderlying(ISilo _silo, address _user) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.debtBalanceOfUnderlying(_silo, _user);
        sig = ISiloLens.debtBalanceOfUnderlying.selector;
    }

    function _maxLiquidation(ISilo _silo, address _user) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.maxLiquidation(_silo, _hookReceivers[_silo], _user);
        sig = ISiloLens.maxLiquidation.selector;
    }

    function _totalDeposits(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.totalDeposits(_silo);
        sig = ISiloLens.totalDeposits.selector;
    }

    function _totalDepositsWithInterest(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.totalDepositsWithInterest(_silo);
        sig = ISiloLens.totalDepositsWithInterest.selector;
    }

    function _totalBorrowAmountWithInterest(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.totalBorrowAmountWithInterest(_silo);
        sig = ISiloLens.totalBorrowAmountWithInterest.selector;
    }

    function _collateralOnlyDeposits(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.collateralOnlyDeposits(_silo);
        sig = ISiloLens.collateralOnlyDeposits.selector;
    }

    function _getDepositAmount(ISilo _silo, address _user) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.getDepositAmount(_silo, _user);
        sig = ISiloLens.getDepositAmount.selector;
    }

    function _totalBorrowAmount(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.totalBorrowAmount(_silo);
        sig = ISiloLens.totalBorrowAmount.selector;
    }

    function _totalBorrowShare(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.totalBorrowShare(_silo);
        sig = ISiloLens.totalBorrowShare.selector;
    }

    function _getBorrowAmount(ISilo _silo, address _user) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.getBorrowAmount(_silo, _user);
        sig = ISiloLens.getBorrowAmount.selector;
    }

    function _borrowShare(ISilo _silo, address _user) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.borrowShare(_silo, _user);
        sig = ISiloLens.borrowShare.selector;
    }

    function _protocolFees(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.protocolFees(_silo);
        sig = ISiloLens.protocolFees.selector;
    }

    function _calculateCollateralValue(ISiloConfig _siloConfig, address _user) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.calculateCollateralValue(_siloConfig, _user);
        sig = ISiloLens.calculateCollateralValue.selector;
    }

    function _calculateBorrowValue(ISiloConfig _siloConfig, address _user) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.calculateBorrowValue(_siloConfig, _user);
        sig = ISiloLens.calculateBorrowValue.selector;
    }

    function _getUtilization(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.getUtilization(_silo);
        sig = ISiloLens.getUtilization.selector;
    }

    function _getInterestRateModel(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.getInterestRateModel(_silo);
        sig = ISiloLens.getInterestRateModel.selector;
    }

    function _getBorrowAPR(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.getBorrowAPR(_silo);
        sig = ISiloLens.getBorrowAPR.selector;
    }

    function _getDepositAPR(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.getDepositAPR(_silo);
        sig = ISiloLens.getDepositAPR.selector;
    }

    function _getAPRs(ISilo _silo) internal view returns (bytes4 sig) {
        ISilo[] memory silos = new ISilo[](1);
        silos[0] = _silo;
        // expect do not revert
        _lens.getAPRs(silos);
        sig = ISiloLens.getAPRs.selector;
    }

    function _getModel(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.getModel(_silo);
        sig = ISiloLens.getModel.selector;
    }

    function _getSiloIncentivesControllerProgramsNames() internal pure returns (bytes4 sig) {
        // method is not related to Silo
        sig = ISiloLens.getSiloIncentivesControllerProgramsNames.selector;
    }

    function _VERSION() internal pure returns (bytes4 sig) {
        // method is not related to Silo
        sig = IVersioned.VERSION.selector;
    }

    function _getVersion(address _contract) internal view returns (bytes4 sig) {
        // method is not related to Silo
        _lens.getVersion(_contract);
        sig = ISiloLens.getVersion.selector;
    }

    function _getVersions(address _contract) internal view returns (bytes4 sig) {
        address[] memory contracts = new address[](1);
        contracts[0] = _contract;
        _lens.getVersions(contracts);
        sig = ISiloLens.getVersions.selector;
    }

    function _getOracleAddresses(ISilo _silo) internal view returns (bytes4 sig) {
        // expect do not revert
        _lens.getOracleAddresses(_silo);
        sig = ISiloLens.getOracleAddresses.selector;
    }

    function _initializeSilosForChain(string memory _chainAlias) internal {
        _chainsToTest.push(_chainAlias);

        string memory root = vm.projectRoot();
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile(string.concat(root, "/", SiloDeployments.DEPLOYMENTS_FILE));

        string[] memory keys = vm.parseJsonKeys(json, string.concat(".", _chainAlias));

        for (uint256 i = 0; i < keys.length; i++) {
            ISiloConfig siloConfig = ISiloConfig(SiloDeployments.get(_chainAlias, keys[i]));

            _siloConfigs[_chainAlias].push(siloConfig);

            (address silo0, address silo1) = siloConfig.getSilos();

            _siloAddresses[_chainAlias].push(ISilo(silo0));
            _siloAddresses[_chainAlias].push(ISilo(silo1));

            IPartialLiquidation hookReceiver = IPartialLiquidation(IShareToken(silo0).hookReceiver());

            _hookReceivers[ISilo(silo0)] = hookReceiver;
            _hookReceivers[ISilo(silo1)] = hookReceiver;
        }
    }

    function _ensureAllFunctionsAreTested() internal {
        bool allCovered = true;
        string memory root = vm.projectRoot();
        string memory abiFile = "/cache/foundry/out/silo-core/SiloLens.sol/SiloLens.json";
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile(string.concat(root, "/", abiFile));

        string[] memory keys = vm.parseJsonKeys(json, ".methodIdentifiers");

        for (uint256 i = 0; i < keys.length; i++) {
            bytes4 sig = bytes4(keccak256(bytes(keys[i])));

            if (!_testedFunctions[sig]) {
                allCovered = false;

                emit log_string(string.concat("Method not found: ", keys[i]));
            }
        }

        assertTrue(allCovered, "All methods should be covered");
    }
}
