// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC721Metadata} from "openzeppelin5/token/ERC721/extensions/IERC721Metadata.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";
import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {IERC721Errors} from "openzeppelin5/interfaces/draft-IERC6093.sol";

import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";

import {ISiloFactory} from "silo-core/contracts/SiloFactory.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {SiloConfigData} from "silo-core/deploy/input-readers/SiloConfigData.sol";
import {InterestRateModelConfigData} from "silo-core/deploy/input-readers/InterestRateModelConfigData.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";

import {SiloLittleHelper} from "silo-core/test/foundry/_common/SiloLittleHelper.sol";

/*
forge test -vv --ffi --mc SiloFactoryTest
*/
contract SiloFactoryTest is SiloLittleHelper, IntegrationTest {
    string public constant SILO_TO_DEPLOY = SiloConfigsNames.SILO_ETH_USDC_UNI_V3;

    ISiloConfig siloConfig;
    SiloConfigData siloData;
    InterestRateModelConfigData modelData;

    function setUp() public {
        siloData = new SiloConfigData();
        modelData = new InterestRateModelConfigData();

        siloConfig = _setUpLocalFixture();

        siloFactory = ISiloFactory(getAddress(SiloCoreContracts.SILO_FACTORY));

        assertTrue(siloConfig.getConfig(address(silo0)).maxLtv != 0, "we need borrow to be allowed");
    }

    /*
    forge test -vv --ffi --mt test_burnCreatedSiloToken
    */
    function test_burnCreatedSiloToken() public {
        uint256 firstSiloId = siloFactory.getNextSiloId() - 1;

        (, address owner) = siloFactory.getFeeReceivers(address(silo0));

        assertNotEq(owner, address(0), "owner is 0");

        bool isSilo = siloFactory.isSilo(address(silo0));
        assertTrue(isSilo, "silo0 is not a silo");
        isSilo = siloFactory.isSilo(address(silo1));
        assertTrue(isSilo, "silo1 is not a silo");

        vm.expectRevert(ISiloFactory.NotYourSilo.selector);
        siloFactory.burn(firstSiloId);

        vm.prank(owner);
        siloFactory.burn(firstSiloId);

        (, owner) = siloFactory.getFeeReceivers(address(silo0));

        assertEq(owner, address(0), "owner is not 0 after burn");

        isSilo = siloFactory.isSilo(address(silo0));
        assertTrue(isSilo, "silo0 is not a silo after burn");
        isSilo = siloFactory.isSilo(address(silo1));
        assertTrue(isSilo, "silo1 is not a silo after burn");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_tokenURI
    */
    function test_tokenURI() public view {
        uint256 firstSiloId = siloFactory.getNextSiloId() - 1;
        address siloConfigFromFactory = siloFactory.idToSiloConfig(firstSiloId);

        string memory expectedURI = string.concat(
            "https://v2.app.silo.finance/markets/",
            Strings.toString(block.chainid),
            "/",
            Strings.toHexString(siloConfigFromFactory)
        );

        // The example of a link. The foundry may generate different addresses/hashes, address of a Config may change.
        // https://v2.app.silo.finance/markets/31337/0x45c9fcf98d9d4b4a7d0daba0411208139a9b06a3
        string memory tokenURI = IERC721Metadata(address(siloFactory)).tokenURI(firstSiloId);
        assertEq(tokenURI, expectedURI, "actual token URI does not match with expected");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_tokenURIUpdate
    */
    function test_tokenURIUpdate(string calldata _newBaseURI) public {
        uint256 firstSiloId = siloFactory.getNextSiloId() - 1;
        address siloConfigFromFactory = siloFactory.idToSiloConfig(firstSiloId);

        string memory expectedURI = string.concat(
            _newBaseURI, Strings.toString(block.chainid), "/", Strings.toHexString(siloConfigFromFactory)
        );

        vm.expectEmit(true, true, true, true);
        emit ISiloFactory.BaseURI(_newBaseURI);

        vm.prank(Ownable(address(siloFactory)).owner());
        siloFactory.setBaseURI(_newBaseURI);

        string memory tokenURI = IERC721Metadata(address(siloFactory)).tokenURI(firstSiloId);
        assertEq(tokenURI, expectedURI, "actual token URI does not match with expected");
    }

    /*
    forge test -vv --ffi --mt test_tokenURIRevertsNonExistingSilo
    */
    function test_tokenURIRevertsNonExistingSilo() public {
        uint256 existingSiloId = siloFactory.getNextSiloId() - 1;
        uint256 nonExistingSiloId = existingSiloId + 2;

        assertTrue(
            bytes(IERC721Metadata(address(siloFactory)).tokenURI(existingSiloId)).length > 0,
            "token URI does not exist for existing Silo"
        );

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, nonExistingSiloId));
        IERC721Metadata(address(siloFactory)).tokenURI(nonExistingSiloId);
    }

    /*
    forge test -vv --ffi --mt test_isSilo
    */
    function test_isSilo() public {
        // 1. Test real silos
        bool isSilo = siloFactory.isSilo(address(silo0));
        assertTrue(isSilo, "silo0 is not a silo");
        isSilo = siloFactory.isSilo(address(silo1));
        assertTrue(isSilo, "silo1 is not a silo");

        // 2. Test empty address
        isSilo = siloFactory.isSilo(address(0));
        assertFalse(isSilo, "address(0) is a silo");

        // 3. Some random address
        isSilo = siloFactory.isSilo(makeAddr("random"));
        assertFalse(isSilo, "random is a silo");
    }
}
