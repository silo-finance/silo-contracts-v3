// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

import {SiloIncentivesControllerFactoryDeploy} from "silo-core/deploy/SiloIncentivesControllerFactoryDeploy.s.sol";
import {ISiloIncentivesControllerFactory} from
    "silo-core/contracts/incentives/interfaces/ISiloIncentivesControllerFactory.sol";
import {RevertLib} from "silo-core/contracts/lib/RevertLib.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IBackwardsCompatibleGaugeLike} from
    "silo-core/contracts/incentives/interfaces/IBackwardsCompatibleGaugeLike.sol";

/*
this test will not check compatibility when:
- deal can not grant tokens to user
- oracle is not working
- silo is empty (no totalSupply)

FOUNDRY_PROFILE=core_test forge test --ffi --mc BackwardsCompatibleGaugeLikeTest -vv
*/
contract BackwardsCompatibleGaugeLikeTest is Test {
    // we can't move too far because oracle can revert
    uint256 public constant INTERVAL = 10 minutes;
    address public user = makeAddr("qaUser");

    uint256 public decimals0;
    uint256 public decimals1;

    string public symbol0;
    string public symbol1;

    // if deal can't work, we steal tokens from Silo
    bool public token1stolen;
    bool public token0stolen;

    mapping(string network => address[] siloConfigs) public deployedSiloConfigs;
    string[] public networks;

    ISiloIncentivesControllerFactory internal _factory;

    error CantRemoveActiveGauge();

    function setUp() public {
        _parseSiloDeployments();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_backwardsCompatibility_arbitrum_one -vv

    we go over all deployed silos and manage gauges + do silo moves to make sure nothing break 
    goal si to verify is new SiloIncentivesControllerFactory is backwards compatible with old ones
    */
    function test_backwardsCompatibility_arbitrum_one() public {
        _backwardsCompatibility_forNetwork(vm.envString("RPC_ARBITRUM"), "arbitrum_one");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_backwardsCompatibility_avalanche -vv
    */
    function test_backwardsCompatibility_avalanche() public {
        _backwardsCompatibility_forNetwork(vm.envString("RPC_AVALANCHE"), "avalanche");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_backwardsCompatibility_ink -vv
    */
    function test_backwardsCompatibility_ink() public pure {
        console2.log("INK deprecated");
        // _backwardsCompatibility_forNetwork(vm.envString("RPC_INK"), "ink");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_backwardsCompatibility_mainnet -vv
    */
    function test_backwardsCompatibility_mainnet() public {
        _backwardsCompatibility_forNetwork(vm.envString("RPC_MAINNET"), "mainnet");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_backwardsCompatibility_optimism -vv
    */
    function test_backwardsCompatibility_optimism() public {
        _backwardsCompatibility_forNetwork(vm.envString("RPC_OPTIMISM"), "optimism");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_backwardsCompatibility_sonic -vv
    */
    function test_backwardsCompatibility_sonic() public {
        _backwardsCompatibility_forNetwork(vm.envString("RPC_SONIC"), "sonic");
    }

    function _backwardsCompatibility_forNetwork(string memory _rpc, string memory _networkKey) internal {
        vm.createSelectFork(_rpc);

        uint256 snapshot = vm.snapshot();

        bytes32 sonicHash = keccak256(abi.encodePacked("sonic"));
        bytes32 networkHash = keccak256(abi.encodePacked(_networkKey));

        for (uint256 i = 0; i < deployedSiloConfigs[_networkKey].length; i++) {
            ISiloConfig siloConfig = ISiloConfig(deployedSiloConfigs[_networkKey][i]);
            uint256 siloId = siloConfig.SILO_ID();

            if (networkHash == sonicHash) {
                if (siloId == 54) continue; // live controller is not backwards compatible, missing is_killed()
                if (siloId == 121) continue; // wmetaUSD/USDC hacked token
                if (siloId == 125) continue; // wmetaUSD/scUSD hacked token
                if (siloId == 128) continue; // wmetaS/ wS hacked token
            }

            console2.log("_______ %s [%s] START SILO ID=%s _______", _networkKey, i, siloId);
            console2.log("_______ silo config %s", address(siloConfig));
            _check_backwardsCompatibility(siloConfig);
            console2.log("_______ %s [%s] DONE _______", _networkKey, i);

            vm.revertTo(snapshot);
        }
    }

    function _check_backwardsCompatibility(ISiloConfig _siloConfig) internal {
        console2.log("block.number: ", block.number);

        _deployFactory();
        (address silo0, address silo1) = _siloConfig.getSilos();

        if (ISilo(silo0).totalSupply() == 0 && ISilo(silo1).totalSupply() == 0) {
            console2.log("market is empty, skipping");
            return;
        }

        IGaugeHookReceiver hookReceiver = _getSiloHookReceiver(silo0);

        ISiloIncentivesController controller0 =
            ISiloIncentivesController(_factory.create(address(this), address(hookReceiver), silo0, bytes32(0)));
        ISiloIncentivesController controller1 =
            ISiloIncentivesController(_factory.create(address(this), address(hookReceiver), silo1, bytes32(0)));

        // QA

        _dealTokens(_siloConfig);

        _doSiloMoves(_siloConfig);

        assertTrue(_tryToSetNewGauge(controller0, true), "Failed to set new gauge for silo0");

        _doSiloMoves(_siloConfig);

        assertTrue(_tryToSetNewGauge(controller1, true), "Failed to set new gauge for silo1");

        _doSiloMoves(_siloConfig);

        // now remove new gauges without setting up anything new

        assertTrue(_killGauge(silo0) && _removeGauge(silo0), "Failed to KILL gauge for silo0 at the end");

        _doSiloMoves(_siloConfig);

        assertTrue(_killGauge(silo1) && _removeGauge(silo1), "Failed to KILL gauge for silo1 at the end");

        _doSiloMoves(_siloConfig);

        _printBalances(_siloConfig, "END");
    }

    function _dealTokens(ISiloConfig _siloConfig) internal {
        (address silo0, address silo1) = _siloConfig.getSilos();

        IERC20 asset0 = IERC20(IERC4626(silo0).asset());
        IERC20 asset1 = IERC20(IERC4626(silo1).asset());

        decimals0 = IERC20Metadata(address(asset0)).decimals();
        decimals1 = IERC20Metadata(address(asset1)).decimals();
        symbol0 = IERC20Metadata(address(asset0)).symbol();
        symbol1 = IERC20Metadata(address(asset1)).symbol();

        emit log_named_decimal_uint(string.concat("liquidity before deal ", symbol0), ISilo(silo0).getLiquidity(), decimals0);
        emit log_named_decimal_uint(string.concat("liquidity before deal ", symbol1), ISilo(silo1).getLiquidity(), decimals1);

        uint256 amount0 = 100_000 * (10 ** decimals0);
        uint256 amount1 = 100_000 * (10 ** decimals1);

        token0stolen = false;
        token1stolen = false;

        // must be huge amount in case there is no enough liquidity
        try this.dealTokens(address(asset0), amount0) {
            // OK
        } catch {
            console2.log("failed to deal %s, try direct transfer from Silo", symbol0);
            uint256 siloBalance = IERC20(IERC4626(silo0).asset()).balanceOf(silo0);
            emit log_named_decimal_uint("silo balance before stealing", siloBalance, decimals0);
            vm.prank(silo0);
            require(asset0.transfer(user, siloBalance / 1000), "transfer failed");
            token0stolen = true;
        }

        try this.dealTokens(address(asset1), amount1) {
            // OK
        } catch {
            console2.log("failed to deal %s, try direct transfer from Silo", symbol1);
            uint256 siloBalance = IERC20(IERC4626(silo1).asset()).balanceOf(silo1);
            emit log_named_decimal_uint("silo balance before stealing", siloBalance, decimals1);
            vm.prank(silo1);
            require(asset1.transfer(user, siloBalance / 1000), "transfer failed");
            token1stolen = true;
        }

        vm.startPrank(user);
        asset0.approve(silo0, type(uint256).max);
        asset1.approve(silo1, type(uint256).max);
        vm.stopPrank();

        _printBalances(_siloConfig, "START");
    }

    function dealTokens(address _asset, uint256 _amount) external {
        deal(_asset, user, _amount);
    }

    function _printBalances(ISiloConfig _siloConfig, string memory _prefix) internal {
        (address silo0, address silo1) = _siloConfig.getSilos();
        IERC20 asset0 = IERC20(IERC4626(silo0).asset());
        IERC20 asset1 = IERC20(IERC4626(silo1).asset());

        emit log_named_decimal_uint(
            string.concat(_prefix, " asset0 ", symbol0, " balance"), asset0.balanceOf(user), decimals0
        );

        emit log_named_decimal_uint(
            string.concat(_prefix, " asset1 ", symbol1, " balance"), asset1.balanceOf(user), decimals1
        );
    }

    function _doSiloMoves(ISiloConfig _siloConfig) internal {
        vm.startPrank(user);

        (address silo0, address silo1) = _siloConfig.getSilos();
        IERC20 asset0 = IERC20(IERC4626(silo0).asset());
        IERC20 asset1 = IERC20(IERC4626(silo1).asset());

        console2.log("----------- Silo %s/%s moves ---------", symbol0, symbol1);

        uint256 amount0 = asset0.balanceOf(user);
        uint256 amount1 = asset1.balanceOf(user);
        // leave some in wallet for fees
        uint256 depositAmount = amount0 * 99 / 100;

        
        if (depositAmount != 0) {
            console2.log("depositing %s %s", symbol0, depositAmount);
            IERC4626(silo0).deposit(depositAmount, user);
        }

        vm.warp(block.timestamp + INTERVAL);
        depositAmount = amount1 * 99 / 100;

        if (depositAmount != 0) {
            console2.log("depositing %s %s", symbol1, depositAmount);
            IERC4626(silo1).deposit(depositAmount, user);
        }

        vm.warp(block.timestamp + INTERVAL);

        if (_checkIfOracleWorking(ISilo(silo0))) {
            tryBorrow(_siloConfig, silo0, silo1, decimals0, symbol0);
            vm.warp(block.timestamp + INTERVAL);
        } else {
            console2.log("oracle is not working for silo#0");
        }

        if (_checkIfOracleWorking(ISilo(silo1))) {
            tryBorrow(_siloConfig, silo1, silo0, decimals1, symbol1);
            vm.warp(block.timestamp + INTERVAL);
        } else {
            console2.log("oracle is not working for silo#1");
        }

        uint256 maxWithdrawable0 = IERC4626(silo0).maxWithdraw(user);
        emit log_named_decimal_uint(string.concat("maxWithdrawable0 ", symbol0), maxWithdrawable0, decimals0);

        if (maxWithdrawable0 != 0) {
            try IERC4626(silo0).withdraw(maxWithdrawable0, user, user) {
                // OK
            } catch (bytes memory e) {
                if (!token0stolen) {
                    console2.log("failed to withdraw %s tokens on sil#0 %s", symbol0, vm.getLabel(address(silo0)));
                    emit log_named_decimal_uint("      silo balance", IERC20(IERC4626(silo0).asset()).balanceOf(silo0), decimals0);
                    emit log_named_decimal_uint("   total protected", ISilo(silo0).getTotalAssetsStorage(ISilo.AssetType.Protected), decimals0);
                    emit log_named_decimal_uint("         liquidity", ISilo(silo0).getLiquidity(), decimals0);
                    emit log_named_decimal_uint("  total collateral", ISilo(silo0).getCollateralAssets(), decimals0);
                    emit log_named_decimal_uint("collateral storage", ISilo(silo0).getTotalAssetsStorage(ISilo.AssetType.Collateral), decimals0);
                    emit log_named_decimal_uint("        total debt", ISilo(silo0).getDebtAssets(), decimals0);
                    RevertLib.revertBytes(e, "withdraw");
                }
            }
        }

        uint256 maxWithdrawable1 = IERC4626(silo1).maxWithdraw(user);
        emit log_named_decimal_uint(string.concat("maxWithdrawable1 ", symbol1), maxWithdrawable1, decimals1);

        if (maxWithdrawable1 != 0) {
            try IERC4626(silo1).withdraw(maxWithdrawable1, user, user) {
                // OK
            } catch (bytes memory e) {
                if (!token1stolen) {
                    console2.log("failed to withdraw %s tokens on silo#1 %s", symbol1, vm.getLabel(address(silo1)));
                    emit log_named_decimal_uint("      silo balance", IERC20(IERC4626(silo1).asset()).balanceOf(silo1), decimals1);
                    emit log_named_decimal_uint("   total protected", ISilo(silo1).getTotalAssetsStorage(ISilo.AssetType.Protected), decimals1);
                    emit log_named_decimal_uint("         liquidity", ISilo(silo1).getLiquidity(), decimals1);
                    emit log_named_decimal_uint("  total collateral", ISilo(silo1).getCollateralAssets(), decimals1);
                    emit log_named_decimal_uint("collateral storage", ISilo(silo1).getTotalAssetsStorage(ISilo.AssetType.Collateral), decimals1);
                    emit log_named_decimal_uint("        total debt", ISilo(silo1).getDebtAssets(), decimals1);
                    RevertLib.revertBytes(e, "withdraw");
                }
            }
        }

        vm.stopPrank();
    }

    function _borrowPossible(ISiloConfig _siloConfig, address _collateralSilo) internal view returns (bool success) {
        try _siloConfig.getConfig(_collateralSilo) returns (ISiloConfig.ConfigData memory config) {
            return config.maxLtv != 0;
        } catch {
            console2.log("config can not be pulled for silo#", vm.getLabel(address(_collateralSilo)));
            return false;
        }
    }

    function _checkIfOracleWorking(ISilo _debtSilo) internal view returns (bool working) {
        try _debtSilo.maxBorrow(user) {
            working = true;
        } catch {
            console2.log("oracle is not working for silo#", vm.getLabel(address(_debtSilo)));
            working = false;
        }
    }

    function tryBorrow(
        ISiloConfig _siloConfig,
        address _debtSilo,
        address _collateralSilo,
        uint256 _debtDecimals,
        string memory _debtSymbol
    ) internal returns (bool success) {
        if (!_borrowPossible({_siloConfig: _siloConfig, _collateralSilo: _collateralSilo})) return false;

        uint256 liquidity = ISilo(_debtSilo).getLiquidity();
        emit log_named_decimal_uint(string.concat(_debtSymbol, " liquidity on debt silo"), liquidity, _debtDecimals);

        uint256 maxBorrow = ISilo(_debtSilo).maxBorrow(user);
        uint256 borrowAmount = maxBorrow / 100;

        if (liquidity == 0 && borrowAmount == 0) {
            console2.log("liquidity is 0 and borrowAmount is 0 (possible bad debt), skipping");
            return false;
        } else if (liquidity != 0 && maxBorrow == 0) {
            emit log_named_decimal_uint(
                string.concat(_debtSymbol, " maxBorrow is 0, liquidity is "), liquidity, _debtDecimals
            );

            revert("maxBorrow is 0 but we do have liquidity");
        }

        emit log_named_decimal_uint(string.concat(_debtSymbol, " borrowAmount "), borrowAmount, _debtDecimals);

        ISilo(_debtSilo).borrow(borrowAmount, user, user);

        vm.warp(block.timestamp + INTERVAL);

        ISilo(_debtSilo).repayShares(ISilo(_debtSilo).maxRepayShares(user), user);
        console2.log("borrow/repay on silo %s done", _debtSymbol);
        return true;
    }

    function _tryToSetNewGauge(ISiloIncentivesController _controller, bool _kill) internal returns (bool success) {
        // usually share token is collateral, but let's be sure
        address silo = _controller.SHARE_TOKEN();
        console2.log("Silo sanity check: call for factory - ", address(ISilo(silo).factory()));

        if (_setGauge(_controller, silo)) return true;

        if (_removeGauge(silo) && _setGauge(_controller, silo)) return true;

        if (_kill) _killGauge(silo);

        return _removeGauge(silo) && _setGauge(_controller, silo);
    }

    function _killGauge(address _silo) internal returns (bool success) {
        IGaugeHookReceiver hookReceiver = _getSiloHookReceiver(_silo);
        address controller = address(hookReceiver.configuredGauges(IShareToken(_silo)));
        address owner = Ownable(address(controller)).owner();

        console2.log("trying to kill gauge: ", controller);

        vm.prank(owner);
        IBackwardsCompatibleGaugeLike(controller).killGauge();

        console2.log("is killed: ", IBackwardsCompatibleGaugeLike(controller).is_killed());
        success = true;
    }

    function _getSiloHookReceiver(address _silo) internal view returns (IGaugeHookReceiver) {
        return IGaugeHookReceiver(address(IShareToken(_silo).hookReceiver()));
    }

    function _setGauge(ISiloIncentivesController _controller, address _silo) internal returns (bool success) {
        IGaugeHookReceiver hookReceiver = _getSiloHookReceiver(_silo);
        address owner = Ownable(address(hookReceiver)).owner();

        vm.prank(owner);
        try hookReceiver.setGauge(_controller, IShareToken(_silo)) {
            console2.log("Gauge set successfully!");
            return true;
        } catch (bytes memory e) {
            bytes32 alreadyConfiguredHash =
                keccak256(abi.encodeWithSelector(IGaugeHookReceiver.GaugeAlreadyConfigured.selector));

            if (keccak256(e) == alreadyConfiguredHash) {
                console2.log("Gauge already configured on hook", address(hookReceiver));
                return false;
            } else {
                RevertLib.revertBytes(e, "_setGauge");
            }
        }
    }

    function _removeGauge(address _silo) internal returns (bool success) {
        IGaugeHookReceiver hookReceiver = _getSiloHookReceiver(_silo);
        address owner = Ownable(address(hookReceiver)).owner();

        vm.prank(owner);
        try hookReceiver.removeGauge(IShareToken(_silo)) {
            console2.log("Gauge removed successfully!");
            return true;
        } catch (bytes memory e) {
            bytes32 cantRemoveActiveGaugeHash = keccak256(abi.encodeWithSelector(CantRemoveActiveGauge.selector));

            if (keccak256(e) == cantRemoveActiveGaugeHash) {
                console2.log("Can't remove active gauge");
                return false;
            } else {
                RevertLib.revertBytes(e, "_removeGauge");
            }
        }
    }

    function _deployFactory() internal {
        SiloIncentivesControllerFactoryDeploy deploy = new SiloIncentivesControllerFactoryDeploy();
        deploy.disableDeploymentsSync();
        _factory = deploy.run();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_parseSiloDeployments
    */
    function _parseSiloDeployments() internal {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/silo-core/deploy/silo/_siloDeployments.json");
        string memory json = vm.readFile(path);

        networks = vm.parseJsonKeys(json, ".");

        for (uint256 i = 0; i < networks.length; i++) {
            string memory network = networks[i];
            string memory networkPath = string.concat(".", network);
            string[] memory siloKeys = vm.parseJsonKeys(json, networkPath);

            address[] memory addresses = new address[](siloKeys.length);

            for (uint256 j = 0; j < siloKeys.length; j++) {
                string memory siloPath = _buildJsonPath(networkPath, siloKeys[j]);
                addresses[j] = vm.parseJsonAddress(json, siloPath);
                require(addresses[j] != address(0), string.concat("address is 0 for key: ", siloKeys[j]));
            }

            deployedSiloConfigs[network] = addresses;
        }
    }

    function _buildJsonPath(string memory _basePath, string memory _key) internal pure returns (string memory) {
        // Use bracket notation: ['key.with.dots'] because of "." in keys
        return string.concat(_basePath, "['", _key, "']");
    }
}
