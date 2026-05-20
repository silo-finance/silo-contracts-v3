// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {console2} from "forge-std/console2.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";

import {SiloCoreContracts, SiloCoreDeployments} from "silo-core/common/SiloCoreContracts.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {ISiloDeployer} from "silo-core/contracts/interfaces/ISiloDeployer.sol";
import {IERC3156FlashBorrower} from "silo-core/contracts/interfaces/IERC3156FlashBorrower.sol";
import {SiloDeployerFlashloan} from "silo-core/contracts/utils/siloFlashloan/SiloDeployerFlashloan.sol";
import {SiloFlashloan} from "silo-core/contracts/utils/siloFlashloan/SiloFlashloan.sol";
import {IDynamicKinkModelFactory} from "silo-core/contracts/interfaces/IDynamicKinkModelFactory.sol";

import {IPoolAddressesProvider} from "aave-v3-origin/interfaces/IPoolAddressesProvider.sol";
import {IPool} from "aave-v3-origin/interfaces/IPool.sol";

bytes32 constant FLASHLOAN_CALLBACK = keccak256("ERC3156FlashBorrower.onFlashLoan");

contract FlashLoanReceiverMock is IERC3156FlashBorrower {
    uint256 public callbackCount;
    address public lastInitiator;
    address public lastToken;
    uint256 public lastInputAmount;
    uint256 public lastBalanceOf;
    uint256 public lastFee;

    function onFlashLoan(address _initiator, address _token, uint256 _amount, uint256 _fee, bytes calldata)
        external
        returns (bytes32)
    {
        console2.log("[onFlashLoan]", _token, _amount, _fee);
        console2.log("[onFlashLoan] balance of", IERC20(_token).balanceOf(address(this)));

        callbackCount++;
        lastInitiator = _initiator;
        lastToken = _token;
        lastInputAmount = _amount;
        lastBalanceOf = IERC20(_token).balanceOf(address(this));
        lastFee = _fee;

        IERC20(_token).approve({spender: msg.sender, value: _amount + _fee});
        return FLASHLOAN_CALLBACK;
    }
}

/*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mc SiloFlashloanMethodsSonicForkTest
*/
contract SiloFlashloanMethodsSonicForkTest is Test {
    ISiloFactory internal _siloFactory;
    SiloDeployerFlashloan internal _siloDeployerFlashloan;

    ISilo internal _flashloanSilo;
    address internal _asset;
    IPool internal _pool;
    ISilo silo20 = ISilo(0x322e1d5384aa4ED66AeCa770B95686271de61dc3);

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_SONIC"), 71073457);

        AddrLib.init();

        IPoolAddressesProvider provider = IPoolAddressesProvider(AddrLib.getAddress(AddrKey.AAVE_POOL_ADDRESSES_PROVIDER));
        _pool = IPool(provider.getPool());

        _siloFactory = ISiloFactory(
            SiloCoreDeployments.get({ 
                _contract: SiloCoreContracts.SILO_FACTORY, 
                _network: ChainsLib.SONIC_ALIAS 
            })
        );

        address dkinkFactory = SiloCoreDeployments.get({
            _contract: SiloCoreContracts.DYNAMIC_KINK_MODEL_FACTORY,
            _network: ChainsLib.SONIC_ALIAS
        });

        SiloFlashloan siloImpl = new SiloFlashloan(ISiloFactory(address(1)), provider);

        address shareProtectedCollateralTokenImpl = SiloCoreDeployments.get({
            _contract: SiloCoreContracts.SHARE_PROTECTED_COLLATERAL_TOKEN,
            _network: ChainsLib.SONIC_ALIAS
        });
        address shareDebtTokenImpl = SiloCoreDeployments.get({
            _contract: SiloCoreContracts.SHARE_DEBT_TOKEN,
            _network: ChainsLib.SONIC_ALIAS
        });

        _siloDeployerFlashloan = new SiloDeployerFlashloan({
            _dynamicKinkModelFactory: IDynamicKinkModelFactory(dkinkFactory),
            _siloFactory: _siloFactory,
            _siloImpl: address(siloImpl),
            _shareProtectedCollateralTokenImpl: shareProtectedCollateralTokenImpl,
            _shareDebtTokenImpl: shareDebtTokenImpl
        });

        ISiloConfig.InitData memory initData = _prepareInitDataFromLatestMarket();

        ISiloConfig deployedConfig = ISiloDeployer(address(_siloDeployerFlashloan)).deploy({
            _oracles: _emptyOracles(),
            _irmConfigData0: "",
            _irmConfigData1: "",
            _clonableHookReceiver: ISiloDeployer.ClonableHookReceiver({implementation: address(0), initializationData: ""}),
            _siloInitData: initData,
            _marketOptions: ISiloDeployer.MarketOptions({permissionedLiquidators: new address[](0)})
        });

        (, address silo1) = deployedConfig.getSilos();
        _flashloanSilo = ISilo(silo1);
 
        _asset = silo20.asset();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_maxFlashLoan
    */
    function test_maxFlashLoan() public view {
        uint256 maxLoan = _flashloanSilo.maxFlashLoan(_asset);
        address aToken = _pool.getReserveAToken(_asset);
        uint256 expected = IERC20(_asset).balanceOf(aToken);

        assertEq(maxLoan, expected, "maxFlashLoan should equal Aave reserve liquidity");
        assertEq(maxLoan, 1_356_675.402753e6, "max flashloan");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_flashFee
    */
    function test_flashFee() public view {
        uint256 amount = _normalizedAmount();
        uint256 fee = _flashloanSilo.flashFee(_asset, amount);
        uint256 expected = uint256(_pool.FLASHLOAN_PREMIUM_TOTAL()) * amount / 10_000;

        assertEq(fee, expected, "flashFee should match Aave premium");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_flashLoan
    */
    function test_flashLoan() public {
        FlashLoanReceiverMock receiver = new FlashLoanReceiverMock();

        uint256 amount = _normalizedAmount();
        uint256 fee = _flashloanSilo.flashFee(_asset, amount);
        deal(_asset, address(receiver), fee);

        bool success = _flashloanSilo.flashLoan({
            _receiver: IERC3156FlashBorrower(address(receiver)),
            _token: _asset,
            _amount: amount,
            _data: ""
        });

        assertTrue(success, "flashLoan should return true");
        assertEq(receiver.callbackCount(), 1, "onFlashLoan should be called once");
        assertEq(receiver.lastInitiator(), address(this), "receiver should get test as initiator");
        assertEq(receiver.lastToken(), _asset, "receiver should get market asset");
        assertEq(receiver.lastInputAmount(), amount, "receiver should get borrowed amount");
        assertEq(receiver.lastBalanceOf(), amount + fee, "balance of should be full amount + fee");
        assertEq(receiver.lastFee(), fee, "receiver should get computed fee");
    }

    function _prepareInitDataFromLatestMarket() internal view returns (ISiloConfig.InitData memory initData) {
        ISiloConfig seedConfig = ISiloConfig(silo20.config());

        (address seedSilo0, address seedSilo1) = seedConfig.getSilos();
        ISiloConfig.ConfigData memory cfg0 = seedConfig.getConfig(seedSilo0);
        ISiloConfig.ConfigData memory cfg1 = seedConfig.getConfig(seedSilo1);

        initData.deployer = address(0);
        initData.hookReceiver = cfg0.hookReceiver;
        initData.deployerFee = 0;
        initData.daoFee = cfg0.daoFee;

        initData.token0 = cfg0.token;
        initData.solvencyOracle0 = cfg0.solvencyOracle;
        initData.maxLtvOracle0 = cfg0.maxLtvOracle;
        initData.interestRateModel0 = cfg0.interestRateModel;
        initData.maxLtv0 = cfg0.maxLtv;
        initData.lt0 = cfg0.lt;
        initData.liquidationTargetLtv0 = cfg0.liquidationTargetLtv;
        initData.liquidationFee0 = cfg0.liquidationFee;
        initData.flashloanFee0 = cfg0.flashloanFee;
        initData.callBeforeQuote0 = cfg0.callBeforeQuote;

        initData.token1 = cfg1.token;
        initData.solvencyOracle1 = cfg1.solvencyOracle;
        initData.maxLtvOracle1 = cfg1.maxLtvOracle;
        initData.interestRateModel1 = cfg1.interestRateModel;
        initData.maxLtv1 = cfg1.maxLtv;
        initData.lt1 = cfg1.lt;
        initData.liquidationTargetLtv1 = cfg1.liquidationTargetLtv;
        initData.liquidationFee1 = cfg1.liquidationFee;
        initData.flashloanFee1 = cfg1.flashloanFee;
        initData.callBeforeQuote1 = cfg1.callBeforeQuote;
    }

    function _emptyOracles() internal pure returns (ISiloDeployer.Oracles memory oracles) {
        ISiloDeployer.OracleCreationTxData memory emptyData =
            ISiloDeployer.OracleCreationTxData({deployed: address(0), factory: address(0), txInput: ""});

        oracles = ISiloDeployer.Oracles({
            solvencyOracle0: emptyData,
            maxLtvOracle0: emptyData,
            solvencyOracle1: emptyData,
            maxLtvOracle1: emptyData
        });
    }

    function _normalizedAmount() internal view returns (uint256 amount) {
        uint256 maxLoan = _flashloanSilo.maxFlashLoan(_asset);
        require(maxLoan > 100, "insufficient max flash loan");
        amount = maxLoan / 100;
        if (amount == 0) amount = 1;
    }
}
