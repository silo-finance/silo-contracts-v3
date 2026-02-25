// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {SiloCoreDeployments} from "silo-core/common/SiloCoreContracts.sol";
import {IDynamicKinkModelFactory} from "silo-core/contracts/interfaces/IDynamicKinkModelFactory.sol";

import {SiloDeployer} from "silo-core/contracts/SiloDeployer.sol";

/*
FOUNDRY_PROFILE=core_test RPC_URL=$RPC_BASE forge test -vv --ffi --mc SiloDeployerIntegrationTest

It check if SiloDeployer is using newest/current contract addresses
*/
contract SiloDeployerIntegrationTest is Test {
    SiloDeployer siloDeployer;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_URL"));

        AddrLib.init();
        siloDeployer = SiloDeployer(_getDeployedAddress(SiloCoreContracts.SILO_DEPLOYER));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_siloHookV1Deploy_run
    */
    function test_siloDeployer_addresses() public {
        _checkAddress(address(siloDeployer.IRM_CONFIG_FACTORY()), SiloCoreContracts.INTEREST_RATE_MODEL_V2_FACTORY);

        // Kink is new deployment, not available on all chains yet
        try siloDeployer.DYNAMIC_KINK_MODEL_FACTORY() returns (IDynamicKinkModelFactory dynamicKinkModelFactory) {
            _checkAddress(address(dynamicKinkModelFactory), SiloCoreContracts.DYNAMIC_KINK_MODEL_FACTORY);
        } catch {
            assertEq(
                _getDeployedAddress(SiloCoreContracts.DYNAMIC_KINK_MODEL_FACTORY),
                address(0),
                "deployer don't have DKINK so we expect it is not deployed"
            );
        }

        _checkAddress(address(siloDeployer.SILO_FACTORY()), SiloCoreContracts.SILO_FACTORY);

        _checkAddress(address(siloDeployer.SILO_IMPL()), SiloCoreContracts.SILO);

        _checkAddress(
            address(siloDeployer.SHARE_PROTECTED_COLLATERAL_TOKEN_IMPL()),
            SiloCoreContracts.SHARE_PROTECTED_COLLATERAL_TOKEN
        );

        _checkAddress(address(siloDeployer.SHARE_DEBT_TOKEN_IMPL()), SiloCoreContracts.SHARE_DEBT_TOKEN);
    }

    function _checkAddress(address _addressInDeployer, string memory _contractName) internal {
        address deployedAddress = _getDeployedAddress(_contractName);
        assertNotEq(deployedAddress, address(0), string.concat(_contractName, " not deployed"));

        console2.log("%s: %s", _contractName, Strings.toHexString(deployedAddress));

        assertEq(
            _addressInDeployer,
            deployedAddress,
            string.concat(
                _contractName,
                "does not match newest deployment address, got ",
                Strings.toHexString(_addressInDeployer),
                " but expected ",
                Strings.toHexString(deployedAddress)
            )
        );
    }

    function _getDeployedAddress(string memory _contractName) internal returns (address deployedAddress) {
        console2.log("looking for ", _contractName, " on ", ChainsLib.chainAlias());
        deployedAddress = SiloCoreDeployments.get(_contractName, ChainsLib.chainAlias());
    }

    function _x_() internal pure virtual returns (string memory) {
        return string.concat(unicode"❌", " ");
    }

    function _ok_() internal pure virtual returns (string memory) {
        return string.concat(unicode"✅", " ");
    }

    function _warn_() internal pure virtual returns (string memory) {
        return string.concat(unicode"🚸", " ");
    }

    function _printMatch(bool _match, string memory _contractName) internal pure {
        console2.log(
            _contractName, _match ? string.concat(_ok_(), "address match") : string.concat(_x_(), "DOES NOT MATCH")
        );
    }
}
