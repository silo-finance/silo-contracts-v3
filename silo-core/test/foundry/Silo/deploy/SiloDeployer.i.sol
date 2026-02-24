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
    FOUNDRY_PROFILE=core_test RPC_URL=$RPC_ARBITRUM forge test -vv --ffi --mt test_compareToOldDeployer
    */
    function test_compareToOldDeployer() public view {
        string memory i = " (This is verification test, adjust it when needed)";
        SiloDeployer oldDeployer = _getPreviousDeployer();

        console2.log("chain %s (%s)", ChainsLib.chainAlias(), ChainsLib.getChainId());

        assertNotEq(address(oldDeployer), address(0), string.concat("Previous deployer not found", i));
        assertNotEq(
            address(oldDeployer),
            address(siloDeployer),
            string.concat("Update old deployer address, it is the same as new one", i)
        );

        bool irmConfigFactoryMatch = oldDeployer.IRM_CONFIG_FACTORY() == siloDeployer.IRM_CONFIG_FACTORY();
        bool dynamicKinkModelFactoryMatch;

        try oldDeployer.DYNAMIC_KINK_MODEL_FACTORY() returns (IDynamicKinkModelFactory dynamicKinkModelFactory) {
            dynamicKinkModelFactoryMatch = dynamicKinkModelFactory == siloDeployer.DYNAMIC_KINK_MODEL_FACTORY();
        } catch {
            console2.log("dynamic kink model factory not found on OLD deployer");
        }

        bool siloFactoryMatch = oldDeployer.SILO_FACTORY() == siloDeployer.SILO_FACTORY();
        bool siloImplMatch = oldDeployer.SILO_IMPL() == siloDeployer.SILO_IMPL();
        bool shareProtectedCollateralTokenImplMatch = oldDeployer.SHARE_PROTECTED_COLLATERAL_TOKEN_IMPL()
            == siloDeployer.SHARE_PROTECTED_COLLATERAL_TOKEN_IMPL();
        bool shareDebtTokenImplMatch = oldDeployer.SHARE_DEBT_TOKEN_IMPL() == siloDeployer.SHARE_DEBT_TOKEN_IMPL();

        _printMatch(irmConfigFactoryMatch, SiloCoreContracts.INTEREST_RATE_MODEL_V2_FACTORY);
        _printMatch(dynamicKinkModelFactoryMatch, SiloCoreContracts.DYNAMIC_KINK_MODEL_FACTORY);
        _printMatch(siloFactoryMatch, SiloCoreContracts.SILO_FACTORY);
        _printMatch(siloImplMatch, SiloCoreContracts.SILO);
        _printMatch(shareProtectedCollateralTokenImplMatch, SiloCoreContracts.SHARE_PROTECTED_COLLATERAL_TOKEN);
        _printMatch(shareDebtTokenImplMatch, SiloCoreContracts.SHARE_DEBT_TOKEN);
    }

    function _getPreviousDeployer() internal view returns (SiloDeployer) {
        uint256 chainId = ChainsLib.getChainId();

        if (chainId == ChainsLib.AVALANCHE_CHAIN_ID) {
            return SiloDeployer(0xcf8d34CffF69F8d4ab388395E24EF9c46f9a8992);
        } else if (chainId == ChainsLib.SONIC_CHAIN_ID) {
            return SiloDeployer(0x931e59f06b83dD3d9A622FD4537989B6C63B9bde);
        } else if (chainId == ChainsLib.MAINNET_CHAIN_ID) {
            return SiloDeployer(0x5418cC3C992C19fB7A3AF812Da0d8bbb28eD558C);
        } else if (chainId == ChainsLib.OPTIMISM_CHAIN_ID) {
            return SiloDeployer(0x6225eF6256f945f490204D7F71e80B0FF84523dD);
        } else if (chainId == ChainsLib.ARBITRUM_ONE_CHAIN_ID) {
            return SiloDeployer(0x8c3024280BF126db4bDbA2B5dE5b22ccCb26db98);
        } else if (chainId == ChainsLib.INJECTIVE_CHAIN_ID) {
            return SiloDeployer(0x931e59f06b83dD3d9A622FD4537989B6C63B9bde);
        } else if (chainId == ChainsLib.BASE_CHAIN_ID) {
            return SiloDeployer(0x315a8319e94eFF8aa5FB11923c32E73Fca00E479);
        } else if (chainId == ChainsLib.BNB_CHAIN_ID) {
            return SiloDeployer(0xB2886994d8E7d84759b6e08D465094E71BfBad67);
        } else if (chainId == ChainsLib.OKX_CHAIN_ID) {
            return SiloDeployer(0xB2886994d8E7d84759b6e08D465094E71BfBad67);
        }

        revert("Chain not supported");
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
