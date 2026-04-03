// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";
import {RevertLib} from "silo-core/contracts/lib/RevertLib.sol";

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {SiloConfig} from "silo-core/contracts/SiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {TokenHelper} from "silo-core/contracts/lib/TokenHelper.sol";
import {SiloLens} from "silo-core/contracts/SiloLens.sol";
import {GaugeHookReceiver} from "silo-core/contracts/hooks/gauge/GaugeHookReceiver.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {Utils} from "silo-core/deploy/silo/verifier/Utils.sol";
import {IWrappedNativeToken} from "silo-core/contracts/interfaces/IWrappedNativeToken.sol";
import {InjectiveWorkaround} from "../_common/InjectiveWorkaround.sol";

import {IManageableOracle} from "silo-oracles/contracts/interfaces/IManageableOracle.sol";
import {ChainlinkV3Oracle} from "silo-oracles/contracts/chainlinkV3/ChainlinkV3Oracle.sol";
import {AggregatorV3Interface} from "chainlink/v0.8/interfaces/AggregatorV3Interface.sol";

interface OldGauge {
    function killGauge() external;
}

// RedStone Interfaces
interface EthereumMultiFeedAdapterWithoutRoundsV3 {
    function getLastUpdateDetails(bytes32 dataFeedId)
        external
        view
        returns (uint256 lastDataTimestamp, uint256 lastBlockTimestamp, uint256 lastValue);
}

interface EthereumPriceFeedMsyFundamentalusdWithoutRoundsV1 {
    function description() external view returns (string memory);
    function getDataFeedId() external view returns (bytes32);
    function getPriceFeedAdapter() external view returns (EthereumMultiFeedAdapterWithoutRoundsV3);
}
// END

error InvalidLastUpdateDetails(
    bytes32 dataFeedId, uint256 lastDataTimestamp, uint256 lastBlockTimestamp, uint256 lastValue
);

/*
    The test is designed to be run right after the silo lending market deployment.
    It is excluded from the general tests CI pipeline and has separate workflow.

    FOUNDRY_INJECTIVE=true \
    FOUNDRY_PROFILE=core_test CONFIG=0xb61AD7976c49F1Fd651d183491f5e2a28d7Ece17 \
    EXTERNAL_PRICE_0=30 \
    EXTERNAL_PRICE_1=1000 \
    RPC_URL=$RPC_MAINNET \
    forge test --mc "NewMarketTest" --ffi -vvv --mt test_newMarketTest_borrowSilo1
 */
// solhint-disable var-name-mixedcase
contract NewMarketTest is InjectiveWorkaround {
    struct BorrowScenario {
        ISilo collateralSilo;
        IERC20Metadata collateralToken;
        ISilo debtSilo;
        IERC20Metadata debtToken;
        uint256 warpTimeBeforeRepay;
    }

    string public constant SUCCESS_SYMBOL = unicode"✅";
    string public constant SKIPPED_SYMBOL = unicode"⏩";
    string public constant DELIMITER = "------------------------------";

    SiloConfig public SILO_CONFIG;
    uint256 public EXTERNAL_PRICE0;
    uint256 public EXTERNAL_PRICE1;

    ISilo public SILO0;
    ISilo public SILO1;

    IERC20Metadata public TOKEN0;
    IERC20Metadata public TOKEN1;

    uint256 public MAX_LTV0;
    uint256 public MAX_LTV1;

    modifier logSiloConfigName() {
        console2.log(
            "Integration test for SiloConfig",
            string.concat(TOKEN0.symbol(), " / ", TOKEN1.symbol()),
            address(SILO_CONFIG)
        );

        _;
    }

    function setUp() public virtual {
        address _siloConfig = vm.envAddress("CONFIG");
        uint256 _externalPrice0 = vm.envUint("EXTERNAL_PRICE_0");
        uint256 _externalPrice1 = vm.envUint("EXTERNAL_PRICE_1");
        string memory _rpc = vm.envString("RPC_URL");

        vm.createSelectFork(_rpc);

        console2.log("block.timestamp", block.timestamp);
        console2.log("block.number", block.number);

        _customMocksOnInjective();

        AddrLib.init();

        SILO_CONFIG = SiloConfig(_siloConfig);
        EXTERNAL_PRICE0 = _externalPrice0;
        EXTERNAL_PRICE1 = _externalPrice1;

        (address silo0, address silo1) = SILO_CONFIG.getSilos();

        SILO0 = ISilo(silo0);
        SILO1 = ISilo(silo1);

        TOKEN0 = IERC20Metadata(SILO_CONFIG.getConfig(silo0).token);
        TOKEN1 = IERC20Metadata(SILO_CONFIG.getConfig(silo1).token);

        _registerInjectiveMetadataHook(address(TOKEN0));
        _registerInjectiveMetadataHook(address(TOKEN1));

        MAX_LTV0 = SILO_CONFIG.getConfig(silo0).maxLtv;
        MAX_LTV1 = SILO_CONFIG.getConfig(silo1).maxLtv;

        vm.label(address(this), "Depositor");
    }

    function test_newMarketTest_borrowSilo1() public logSiloConfigName {
        _borrowScenario(
            BorrowScenario({
                collateralSilo: SILO0,
                collateralToken: TOKEN0,
                debtSilo: SILO1,
                debtToken: TOKEN1,
                warpTimeBeforeRepay: 0
            })
        );

        _borrowScenario(
            BorrowScenario({
                collateralSilo: SILO0,
                collateralToken: TOKEN0,
                debtSilo: SILO1,
                debtToken: TOKEN1,
                warpTimeBeforeRepay: 10 days
            })
        );
    }

    function test_newMarketTest_borrowSilo0() public logSiloConfigName {
        _borrowScenario(
            BorrowScenario({
                collateralSilo: SILO1,
                collateralToken: TOKEN1,
                debtSilo: SILO0,
                debtToken: TOKEN0,
                warpTimeBeforeRepay: 0
            })
        );

        _borrowScenario(
            BorrowScenario({
                collateralSilo: SILO1,
                collateralToken: TOKEN1,
                debtSilo: SILO0,
                debtToken: TOKEN0,
                warpTimeBeforeRepay: 10 days
            })
        );
    }

    function test_checkGauges() public logSiloConfigName {
        _checkGauges(ISiloConfig(SILO_CONFIG).getConfig(address(SILO0)));
        _checkGauges(ISiloConfig(SILO_CONFIG).getConfig(address(SILO1)));
    }

    function _borrowScenario(BorrowScenario memory _scenario) internal {
        uint256 collateralDecimals = TokenHelper.assertAndGetDecimals(address(_scenario.collateralToken));
        uint256 debtDecimals = TokenHelper.assertAndGetDecimals(address(_scenario.debtToken));

        uint256 collateralAmount = 1000 * 10 ** collateralDecimals;

        address borrower = address(this);

        // 1. Deposit
        _siloDeposit(_scenario.collateralSilo, borrower, collateralAmount);
        _siloDeposit(_scenario.debtSilo, makeAddr("stranger"), 1000 * 10 ** debtDecimals);
        console2.log("\t- deposited collateral");

        if (_scenario.warpTimeBeforeRepay > 0) {
            console2.log("\t- warping...");
            vm.warp(block.timestamp + _scenario.warpTimeBeforeRepay);
            console2.log("\twarp ", _scenario.warpTimeBeforeRepay);
        }

        console2.log("\t- check for maxBorrow...");
        uint256 maxBorrow;

        try _scenario.debtSilo.maxBorrow(borrower) returns (uint256 _maxBorrow) {
            maxBorrow = _maxBorrow;
        } catch (bytes memory returnData) {
            (bool isRedstone, uint256 aggregatorLastPrice) = _checkIfRedstoneInvalidLastUpdateDetails(returnData);

            if (isRedstone) {
                address oracle =
                    _scenario.collateralSilo.config().getConfig(address(_scenario.collateralSilo)).solvencyOracle;
                _mockRedstoneAggretatorWithLastValue(oracle, aggregatorLastPrice);
                maxBorrow = _scenario.debtSilo.maxBorrow(borrower);
            } else {
                RevertLib.revertBytes(returnData, "max borrow failed");
            }
        }

        console2.log("\t- check for maxBorrow", maxBorrow);

        uint256 colateralMaxLtv = SILO_CONFIG.getConfig(address(_scenario.collateralSilo)).maxLtv;

        if (colateralMaxLtv == 0) {
            assertEq(maxBorrow, 0, "maxBorrow is zero when LTV is zero");
            vm.expectRevert(); // it can be ZeroQuote or AboveMaxLtv
            _scenario.debtSilo.borrow(1, borrower, borrower);

            uint256 nonZeroAmount = _findNonZeroQuote(_scenario.debtSilo);

            console2.log("\t- check with amount", nonZeroAmount);

            // in some extream case we can get ZeroQuote, but we can debug this case if needed
            vm.expectRevert(ISilo.AboveMaxLtv.selector);
            _scenario.debtSilo.borrow(nonZeroAmount, borrower, borrower);

            console2.log("\t- expect revert on borrow: OK");

            console2.log(
                string.concat(
                    SKIPPED_SYMBOL,
                    "Borrow scenario is skipped because asset is not borrowable, collateral: ",
                    _scenario.collateralSilo.symbol(),
                    " -> debt: ",
                    _scenario.debtSilo.symbol()
                )
            );

            return;
        }

        assertGt(maxBorrow, 0, "expect to borrow at least some tokens");

        // 2. Borrow
        _scenario.debtSilo.borrow(maxBorrow, borrower, borrower);

        uint256 borrowed = _scenario.debtToken.balanceOf(borrower);
        assertTrue(borrowed >= maxBorrow, "Borrowed more or equal to calculated maxBorrow based on prices");

        if (_scenario.warpTimeBeforeRepay > 0) {
            uint256 maxRepayBefore = _scenario.debtSilo.maxRepay(borrower);
            assertGt(maxRepayBefore, 0, "maxRepayBefore should be greater than 0");

            vm.warp(block.timestamp + _scenario.warpTimeBeforeRepay);
            console2.log("\t- warp %s days to get interest", _scenario.warpTimeBeforeRepay / 1 days);

            assertLt(maxRepayBefore, _scenario.debtSilo.maxRepay(borrower), "we have to generate interest");
        }

        // 3. Repay
        _repayAndCheck({_debtSilo: _scenario.debtSilo, _debtToken: _scenario.debtToken});

        // 4. Withdraw
        _withdrawAndCheck({
            _collateralSilo: _scenario.collateralSilo,
            _collateralToken: _scenario.collateralToken,
            _initiallyDeposited: collateralAmount
        });

        console2.log(
            string.concat(
                SUCCESS_SYMBOL,
                "Borrow scenario success for direction ",
                _scenario.collateralSilo.symbol(),
                " -> ",
                _scenario.debtSilo.symbol()
            )
        );
    }

    function _withdrawAndCheck(ISilo _collateralSilo, IERC20Metadata _collateralToken, uint256 _initiallyDeposited)
        internal
    {
        assertEq(_collateralToken.balanceOf(address(this)), 0, "no collateralToken yet");
        _collateralSilo.redeem(_collateralSilo.balanceOf(address(this)), address(this), address(this));
        console2.log("\t- redeemed collateral");

        assertGe(
            _collateralToken.balanceOf(address(this)),
            _initiallyDeposited - 1,
            "we can loose 1 wei due to rounding unless we got interest"
        );
    }

    // solve stack too deep
    function _repayAndCheck(ISilo _debtSilo, IERC20Metadata _debtToken) internal {
        uint256 sharesToRepay = _debtSilo.maxRepayShares(address(this));
        uint256 maxRepay = _debtSilo.previewRepayShares(sharesToRepay);
        _debtToken.approve(address(_debtSilo), maxRepay);

        _dealTokens(address(_debtToken), address(this), maxRepay);

        assertGe(_debtToken.balanceOf(address(this)), maxRepay, "we need enough tokens for repay");
        _debtSilo.repayShares(sharesToRepay, address(this));
        assertEq((new SiloLens()).getLtv(_debtSilo, address(this)), 0, "Repay is successful, LTV==0");
        console2.log("\t- repaid debt");
    }

    function _siloDeposit(ISilo _silo, address _depositor, uint256 _amount) internal {
        IERC20Metadata token = IERC20Metadata(_silo.asset());

        _dealTokens(address(token), _depositor, _amount);
        vm.prank(_depositor);
        token.approve(address(_silo), _amount);

        vm.prank(_depositor);
        _silo.deposit(_amount, _depositor);
    }

    function _dealTokens(address _token, address _depositor, uint256 _amount) internal {
        uint256 balanceBefore = IERC20(_token).balanceOf(_depositor);

        if (ChainsLib.getChainId() == ChainsLib.INJECTIVE_CHAIN_ID) {
            if (balanceBefore != 0) require(IERC20(_token).transfer(makeAddr("out"), balanceBefore));

            if (address(_token) == AddrLib.getAddress(AddrKey.WINJ)) {
                vm.deal(_depositor, _amount);
                vm.prank(_depositor);
                IWrappedNativeToken(payable(_token)).deposit{value: _amount}();
            } else {
                vm.prank(_token);
                BANK_MODULE.mint(_depositor, _amount);
            }
        } else {
            deal(_token, _depositor, _amount);
        }
    }

    function _checkGauges(ISiloConfig.ConfigData memory _configData) internal {
        _checkGauge({_configData: _configData, _shareToken: IShareToken(_configData.protectedShareToken)});

        _checkGauge({_configData: _configData, _shareToken: IShareToken(_configData.collateralShareToken)});

        _checkGauge({_configData: _configData, _shareToken: IShareToken(_configData.debtShareToken)});
    }

    function _checkGauge(ISiloConfig.ConfigData memory _configData, IShareToken _shareToken) internal {
        GaugeHookReceiver hookReceiver = GaugeHookReceiver(_configData.hookReceiver);
        string memory shareTokenName = Utils.tryGetTokenSymbol(address(_shareToken));
        address gauge = address(hookReceiver.configuredGauges(_shareToken));

        if (gauge == address(0)) {
            console2.log(SKIPPED_SYMBOL, shareTokenName, "gauge does not exist");
            return;
        }

        _tryKillOldGauge(gauge);

        vm.prank(hookReceiver.owner());
        hookReceiver.removeGauge(_shareToken);
        assertEq(
            address(hookReceiver.configuredGauges(_shareToken)),
            address(0),
            "gauge mapping should be cleared after removeGauge"
        );

        console2.log(SUCCESS_SYMBOL, shareTokenName, "gauge is removable");
    }

    function _tryKillOldGauge(address _gauge) internal {
        vm.prank(Ownable(_gauge).owner());
        try OldGauge(_gauge).killGauge() {} catch {}
    }

    function _findNonZeroQuote(ISilo _debtSilo) internal returns (uint256 nonZeroAmount) {
        uint256 power;
        do {
            ISiloOracle oracle = ISiloOracle(_debtSilo.config().getConfig(address(_debtSilo)).solvencyOracle);

            try oracle.quote(10 ** power, address(_debtSilo.asset())) returns (uint256) {
                return 10 ** power;
            } catch (bytes memory returnData) {
                (bool isRedstone, uint256 aggregatorLastPrice) = _checkIfRedstoneInvalidLastUpdateDetails(returnData);

                if (isRedstone) {
                    _mockRedstoneAggretatorWithLastValue(address(oracle), aggregatorLastPrice);
                    return 10 ** power;
                }

                console2.log("fail for", 10 ** power);
                power++;
            }
        } while (power < 6);

        revert("No non-zero quote found");
    }

    /// @dev Revert payload: 4-byte selector + abi.encode(bytes32,uint256,uint256,uint256).
    function _returnDataAfterSelector(bytes memory returnData) internal pure returns (bytes memory payload) {
        require(returnData.length > 4, "returnData too short");
        payload = new bytes(returnData.length - 4);
        for (uint256 i; i < payload.length; ++i) {
            payload[i] = returnData[i + 4];
        }
    }

    function _checkIfRedstoneInvalidLastUpdateDetails(bytes memory returnData)
        internal
        pure
        returns (bool check, uint256 aggregatorLastPrice)
    {
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes4 sel = bytes4(returnData);

        if (sel == InvalidLastUpdateDetails.selector) {
            (, uint256 lastDataTimestamp, uint256 lastBlockTimestamp, uint256 lastValue) =
                abi.decode(_returnDataAfterSelector(returnData), (bytes32, uint256, uint256, uint256));

            console2.log("\t\tInvalidLastUpdateDetails on Redstone aggregator");
            console2.log("\t\tlastDataTimestamp", lastDataTimestamp);
            console2.log("\t\tlastBlockTimestamp", lastBlockTimestamp);
            console2.log("\t\tlastValue", lastValue);

            return (true, lastValue);
        }
    }

    function _mockRedstoneAggretatorWithLastValue(address _oracle, uint256 _lastValue) internal {
        ChainlinkV3Oracle c = ChainlinkV3Oracle(_oracle);

        try IManageableOracle(_oracle).oracle() returns (ISiloOracle oracle) {
            c = ChainlinkV3Oracle(address(oracle));
            console2.log("\t\tOracle is ManageableOracle -> ChainlinkV3Oracle");
        } catch {
            console2.log("\t\tOracle is ChainlinkV3Oracle");
        }

        address aggregator = address(c.oracleConfig().getConfig().primaryAggregator);

        vm.mockCall(
            aggregator,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(0, _lastValue, 0, 0, 0)
        );
    }
}
