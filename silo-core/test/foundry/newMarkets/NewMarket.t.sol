// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "openzeppelin5/access/Ownable2Step.sol";

import {SiloConfig} from "silo-core/contracts/SiloConfig.sol";
import {ISilo, IERC4626} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {TokenHelper} from "silo-core/contracts/lib/TokenHelper.sol";
import {SiloLens, ISiloLens} from "silo-core/contracts/SiloLens.sol";
import {GaugeHookReceiver} from "silo-core/contracts/hooks/gauge/GaugeHookReceiver.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {Utils} from "silo-core/deploy/silo/verifier/Utils.sol";

interface OldGauge {
    function killGauge() external;
}

/*
    The test is designed to be run right after the silo lending market deployment.
    It is excluded from the general tests CI pipeline and has separate workflow.

    FOUNDRY_PROFILE=core_test CONFIG=0xaabC65A0c0F31907c1E6f785CE62433EBcCBD56d \
    EXTERNAL_PRICE_0=4147 \
    EXTERNAL_PRICE_1=1 \
    RPC_URL=$RPC_SONIC \
    forge test --mc "NewMarketTest" --ffi -vvv --mt test_newMarketTest_borrowSameAssetSilo0
 */
// solhint-disable var-name-mixedcase
contract NewMarketTest is Test {
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
            string.concat(TOKEN0.symbol(), "/", TOKEN1.symbol()),
            address(SILO_CONFIG)
        );

        _;
    }

    function setUp() public {
        AddrLib.init();

        address _siloConfig = vm.envAddress("CONFIG");
        uint256 _externalPrice0 = vm.envUint("EXTERNAL_PRICE_0");
        uint256 _externalPrice1 = vm.envUint("EXTERNAL_PRICE_1");
        string memory _rpc = vm.envString("RPC_URL");

        vm.createSelectFork(_rpc);

        SILO_CONFIG = SiloConfig(_siloConfig);
        EXTERNAL_PRICE0 = _externalPrice0;
        EXTERNAL_PRICE1 = _externalPrice1;

        (address silo0, address silo1) = SILO_CONFIG.getSilos();

        SILO0 = ISilo(silo0);
        SILO1 = ISilo(silo1);

        TOKEN0 = IERC20Metadata(SILO_CONFIG.getConfig(silo0).token);
        TOKEN1 = IERC20Metadata(SILO_CONFIG.getConfig(silo1).token);

        MAX_LTV0 = SILO_CONFIG.getConfig(silo0).maxLtv;
        MAX_LTV1 = SILO_CONFIG.getConfig(silo1).maxLtv;
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
            vm.warp(block.timestamp + _scenario.warpTimeBeforeRepay);
            console2.log("\twarp ", _scenario.warpTimeBeforeRepay);
        }

        uint256 maxBorrow = _scenario.debtSilo.maxBorrow(borrower);

        console2.log("\t- check for maxBorrow", maxBorrow);

        uint256 colateralMaxLtv = SILO_CONFIG.getConfig(address(_scenario.collateralSilo)).maxLtv;

        if (colateralMaxLtv == 0) {
            assertEq(maxBorrow, 0, "maxBorrow is zero when LTV is zero");
            vm.expectRevert(); // it can be ZeroQuote or AboveMaxLtv
            _scenario.debtSilo.borrow(1, borrower, borrower);

            // in some extream case we can get ZeroQuote, but we can debug this case if needed
            vm.expectRevert(ISilo.AboveMaxLtv.selector);
            _scenario.debtSilo.borrow(10, borrower, borrower);

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

        deal(address(_debtToken), address(this), maxRepay);

        assertEq(_debtToken.balanceOf(address(this)), maxRepay);
        _debtSilo.repayShares(sharesToRepay, address(this));
        assertEq((new SiloLens()).getLtv(_debtSilo, address(this)), 0, "Repay is successful, LTV==0");
        console2.log("\t- repaid debt");
    }

    function _siloDeposit(ISilo _silo, address _depositor, uint256 _amount) internal {
        IERC20Metadata token = IERC20Metadata(_silo.asset());

        deal(address(token), _depositor, _amount);
        vm.prank(_depositor);
        token.approve(address(_silo), _amount);

        vm.prank(_depositor);
        _silo.deposit(_amount, _depositor);
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
        assertEq(address(hookReceiver.configuredGauges(_shareToken)), address(0));

        console2.log(SUCCESS_SYMBOL, shareTokenName, "gauge is removable");
    }

    function _tryKillOldGauge(address _gauge) internal {
        vm.prank(Ownable(_gauge).owner());
        try OldGauge(_gauge).killGauge() {} catch {}
    }
}
