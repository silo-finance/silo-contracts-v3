// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {PropertiesAsserts} from "properties/util/PropertiesHelper.sol";
import {TestERC20Token} from "properties/ERC4626/util/TestERC20Token.sol";

import {IERC20} from "openzeppelin5/token/ERC20/ERC20.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";
import {Math} from "openzeppelin5/utils/math/Math.sol";

import {ISiloConfig} from "silo-core/contracts/SiloConfig.sol";
import {Silo, ISilo} from "silo-core/contracts/Silo.sol";
import {PartialLiquidation} from "silo-core/contracts/hooks/liquidation/PartialLiquidation.sol";
import {PartialLiquidationLib} from "silo-core/contracts/hooks/liquidation/lib/PartialLiquidationLib.sol";
import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {IInterestRateModel} from "silo-core/contracts/interfaces/IInterestRateModel.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ShareProtectedCollateralToken} from "silo-core/contracts/utils/ShareProtectedCollateralToken.sol";
import {ShareDebtToken} from "silo-core/contracts/utils/ShareDebtToken.sol";

import {Deployers} from "./utils/Deployers.sol";
import {Actor} from "./utils/Actor.sol";

// Note: In order to run this campaign all library functions marked as `public` or `external`
// Need to be changed to be `internal`. This includes all library contracts in contracts/lib/

/*
Command to run:
./silo-core/scripts/echidnaBefore.sh
SOLC_VERSION=0.8.24 echidna silo-core/test/echidna/EchidnaE2E.sol \
    --contract EchidnaE2E \
    --config silo-core/test/echidna/e2e-internal.yaml \
    --workers 10
*/
contract EchidnaE2E is Deployers, PropertiesAsserts {
    using SiloLensLib for Silo;
    using Strings for uint256;

    ISiloConfig internal siloConfig;

    address internal deployer;
    uint256 internal startTimestamp = 1706745600;
    // The same block height also needs to be set in the e2e.yaml file
    uint256 internal startBlockHeight = 17336000;

    address internal _vault0;
    address internal _vault1;
    Silo internal vault0;
    Silo internal vault1;

    TestERC20Token internal _asset0;
    TestERC20Token internal _asset1;

    Actor[] internal actors;

    event ExactAmount(string msg, uint256 amount);

    constructor() payable {
        deployer = msg.sender;

        hevm.warp(startTimestamp);
        hevm.roll(startBlockHeight);

        // Deploy the relevant contracts
        core_setUp(address(this));
        _setupBasicData();

        _asset0 = new TestERC20Token("Test Token0", "TT0", 18);
        _asset1 = new TestERC20Token("Test Token1", "TT1", 18);
        _initData(address(_asset0), address(_asset1));

        address siloImpl = address(new Silo(siloFactory));
        address shareProtectedCollateralTokenImpl = address(new ShareProtectedCollateralToken());
        address shareDebtTokenImpl = address(new ShareDebtToken());

        // deploy silo config
        siloConfig =
            _deploySiloConfig(siloData["MOCK"], siloImpl, shareProtectedCollateralTokenImpl, shareDebtTokenImpl);

        // deploy silo
        siloFactory.createSilo(
            siloConfig,
            siloImpl,
            shareProtectedCollateralTokenImpl,
            shareDebtTokenImpl,
            siloData["MOCK"].deployer,
            msg.sender
        );

        (_vault0, _vault1) = siloConfig.getSilos();
        vault0 = Silo(payable(_vault0));
        vault1 = Silo(payable(_vault1));
        liquidationModule = PartialLiquidation(vault0.config().getConfig(_vault0).hookReceiver);

        // Set up actors
        for (uint256 i; i < 3; i++) {
            actors.push(new Actor(Silo(payable(_vault0)), Silo(payable(_vault1))));
        }
    }

    /* ================================================================
                            Echidna invariants
       ================================================================ */

    function echidna_isSolventIsTheSameEverywhere() public view returns (bool success) {
        for (uint256 i; i < actors.length; i++) {
            address actor = address(actors[i]);
            assert(vault0.isSolvent(actor) == vault1.isSolvent(actor));
            assert(vault0.getLtv(actor) == vault1.getLtv(actor));
        }

        success = true;
    }

    /* ================================================================
                            Functions used for system interaction
       ================================================================ */

    function deposit(uint8 _actorIndex, bool _vaultZero, uint256 _amount) public returns (uint256 shares) {
        emit LogUint256("[deposit] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);

        shares = actor.deposit(_vaultZero, _amount);
        emit LogString(
            string.concat(
                "Deposited",
                _amount.toString(),
                "assets into vault",
                _vaultZero ? "Zero" : "One",
                "and minted",
                shares.toString(),
                "shares"
            )
        );
    }

    function depositAssetType(uint8 _actorIndex, bool _vaultZero, uint256 _amount, ISilo.CollateralType assetType)
        public
        returns (uint256 shares)
    {
        emit LogUint256("[depositAssetType] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);

        shares = actor.depositAssetType(_vaultZero, _amount, assetType);

        emit LogString(
            string.concat(
                "Deposited",
                _amount.toString(),
                assetType == ISilo.CollateralType.Collateral ? " collateral" : " protected",
                " assets into vault",
                _vaultZero ? "Zero" : "One",
                "and minted",
                shares.toString(),
                "shares"
            )
        );
    }

    function mint(uint8 _actorIndex, bool _vaultZero, uint256 shares) public returns (uint256 assets) {
        emit LogUint256("[mint] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);

        assets = actor.mint(_vaultZero, shares);
        emit LogString(
            string.concat(
                "Minted",
                shares.toString(),
                " shares from vault",
                _vaultZero ? "Zero" : "One",
                "and deposited",
                assets.toString(),
                "assets"
            )
        );
    }

    function mintAssetType(uint8 _actorIndex, bool _vaultZero, uint256 shares, ISilo.CollateralType assetType)
        public
        returns (uint256 assets)
    {
        emit LogUint256("[mintAssetType] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);

        assets = actor.mintAssetType(_vaultZero, shares, assetType);

        emit LogString(
            string.concat(
                "Minted",
                shares.toString(),
                " shares from vault",
                _vaultZero ? "Zero" : "One",
                "and deposited",
                assets.toString(),
                assetType == ISilo.CollateralType.Collateral ? " collateral" : " protected",
                " assets"
            )
        );
    }

    function withdraw(uint8 _actorIndex, bool _vaultZero, uint256 assets) public {
        emit LogUint256("[withdraw] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        actor.withdraw(_vaultZero, assets);
    }

    function withdrawAssetType(uint8 _actorIndex, bool _vaultZero, uint256 assets, ISilo.CollateralType assetType)
        public
    {
        emit LogUint256("[withdrawAssetType] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        actor.withdrawAssetType(_vaultZero, assets, assetType);
    }

    function redeem(uint8 _actorIndex, bool _vaultZero, uint256 shares) public {
        emit LogUint256("[redeem] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        actor.redeem(_vaultZero, shares);
    }

    function redeemAssetType(uint8 _actorIndex, bool _vaultZero, uint256 shares, ISilo.CollateralType assetType)
        public
    {
        emit LogUint256("[redeemAssetType] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        actor.redeemAssetType(_vaultZero, shares, assetType);
    }

    function borrow(uint8 _actorIndex, bool _vaultZero, uint256 assets) public {
        emit LogUint256("[borrow] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        actor.borrow(_vaultZero, assets);
    }

    function borrowShares(uint8 _actorIndex, bool _vaultZero, uint256 shares) public {
        emit LogUint256("[borrowShares] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        actor.borrowShares(_vaultZero, shares);
    }

    function repay(uint8 _actorIndex, bool _vaultZero, uint256 _amount) public {
        emit LogUint256("[repay] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        actor.repay(_vaultZero, _amount);
    }

    function repayShares(uint8 _actorIndex, bool _vaultZero, uint256 shares) public returns (uint256 assets) {
        emit LogUint256("[repayShares] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        assets = actor.repayShares(_vaultZero, shares);
    }

    function accrueInterest(bool _vaultZero) public {
        emit LogUint256("[accrueInterest] block.timestamp:", block.timestamp);

        Silo vault = _vaultZero ? vault0 : vault1;
        vault.accrueInterest();
    }

    function withdrawFees(bool _vaultZero) public {
        emit LogUint256("[withdrawFees] block.timestamp:", block.timestamp);

        Silo vault = _vaultZero ? vault0 : vault1;
        vault.withdrawFees();
    }

    function transitionCollateral(
        uint8 _actorIndex,
        bool _vaultZero,
        uint256 shares,
        ISilo.CollateralType withdrawType
    ) public returns (uint256 assets) {
        emit LogUint256("[transitionCollateral] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        assets = actor.transitionCollateral(_vaultZero, shares, withdrawType);
    }

    function flashLoan(uint8 _actorIndex, bool _vaultZero, uint256 _amount) public {
        emit LogUint256("[flashLoan] block.timestamp:", block.timestamp);

        require(_amount != 0);
        require(_amount < _balanceOfSilo(_vaultZero), "we only want possible flashloans");
        require(_amount < type(uint192).max, "we dont want to revert with FeeOverflow");

        Actor actor = _selectActor(_actorIndex);

        try actor.flashLoan(_vaultZero, _amount) returns (bool success) {
            emit LogString("[flashLoan] we expect success");
            assert(success);
        } catch {
            emit LogString("[flashLoan] we should never fail if we repay with fee");
            assert(false);
        }
    }

    function liquidationCall(
        uint8 actorIndexBorrower,
        uint8 actorIndexLiquidator,
        uint256 debtToCover,
        bool receiveSToken
    ) public {
        emit LogUint256("[liquidationCall] block.timestamp:", block.timestamp);

        Actor borrower = _selectActor(actorIndexBorrower);
        Actor liquidator = _selectActor(actorIndexLiquidator);

        _invariant_insolventHasDebt(address(borrower));

        liquidator.liquidationCall(address(borrower), debtToCover, receiveSToken, siloConfig);
    }

    /* ================================================================
                            Properties:
            checking if max* functions are aligned with ERC4626
       ================================================================ */

    // maxDeposit functions are aligned with ERC4626 standard
    function maxDeposit_correctMax(uint8 _actorIndex) public {
        emit LogUint256("[maxDeposit_correctMax] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        uint256 maxAssets = vault0.maxDeposit(address(actor));
        require(maxAssets != 0, "max deposit is zero");

        uint256 userTokenBalance = _asset0.balanceOf(address(actor));
        uint256 totalSupply = _asset0.totalSupply();
        _overflowCheck(totalSupply, maxAssets);
        require(userTokenBalance >= maxAssets, "Not enough assets for deposit");

        emit LogString(string.concat("Max Assets to deposit:", maxAssets.toString()));

        try actor.deposit(true, maxAssets) {}
        catch {
            emit LogString("[maxDeposit_correctMax] failed on deposit");
            assert(false);
        }
    }

    function maxMint_correctMax(uint8 _actorIndex, bool _vaultZero) public {
        emit LogUint256("[maxMint_correctMax] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        Silo vault = _vaultZero ? vault0 : vault1;
        TestERC20Token token = _vaultZero ? _asset0 : _asset1;

        uint256 maxShares = vault.maxMint(address(actor));
        require(maxShares != 0, "max mint is zero");

        uint256 assets = vault.previewMint(maxShares);
        uint256 userTokenBalance = token.balanceOf(address(actor));
        require(userTokenBalance >= assets, "Not enough assets for mint");

        uint256 totalSupply = token.totalSupply();
        _overflowCheck(totalSupply, assets);

        emit LogString(string.concat("Max Shares to mint:", maxShares.toString()));

        try actor.mint(_vaultZero, maxShares) {}
        catch {
            emit LogString("[maxMint_correctMax] failed on mint");
            assert(false);
        }
    }

    function maxWithdraw_correctMax(uint8 _actorIndex) public {
        emit LogUint256("[maxWithdraw_correctMax] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);

        (, bool _vaultWithCollateral) = _invariant_onlySolventUserCanRedeem(address(actor));
        Silo vault = _vaultWithCollateral ? vault0 : vault1;
        require(_requireHealthySilos(), "we dont want IRM to fail");

        uint256 maxAssets = vault.maxWithdraw(address(actor));

        if (maxAssets == 0) {
            (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) =
                siloConfig.getConfigsForSolvency(address(actor));

            uint256 shareBalance = IERC20(collateralConfig.collateralShareToken).balanceOf(address(actor));
            uint256 debtShareBalance = IERC20(debtConfig.debtShareToken).balanceOf(address(actor));
            uint256 vaultLiquidity = vault.getLiquidity();
            uint256 ltv = vault.getLtv(address(actor));
            bool isSolvent = vault.isSolvent(address(actor));

            // below are all cases where maxAssets can be 0
            if (shareBalance == 0 || !isSolvent || vaultLiquidity == 0) {
                // we good
            } else {
                emit LogString("[maxWithdraw_correctMax] maxAssets is zero for no reason");
                emit LogString(isSolvent ? "actor solvent" : "actor not solvent");
                emit LogUint256("shareBalance", shareBalance);
                emit LogUint256("debtShareBalance", debtShareBalance);
                emit LogUint256("vault.getLiquidity()", vaultLiquidity);
                emit LogUint256("ltv (is it close to LT?)", ltv);
            }
        }

        if (maxAssets == 0) return;

        uint256 liquidity = vault.getLiquidity(); // includes interest
        emit LogString(string.concat("Max Assets to withdraw:", maxAssets.toString()));
        emit LogString(string.concat("Available liquidity:", liquidity.toString()));

        try actor.withdraw(_vaultWithCollateral, maxAssets) {
            emit LogString("Withdrawal succeeded");
        } catch {
            emit LogString("Withdrawal failed, but it should not!");
            assert(false);
        }
    }

    function maxRedeem_correctMax(uint8 _actorIndex) public {
        emit LogUint256("[maxRedeem_correctMax] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);

        (, bool _vaultWithCollateral) = _invariant_onlySolventUserCanRedeem(address(actor));
        Silo vault = _vaultWithCollateral ? vault0 : vault1;
        require(_requireHealthySilos(), "we dont want IRM to fail");

        uint256 maxShares = vault.maxRedeem(address(actor));
        require(maxShares != 0, "Zero shares to withdraw");

        emit LogString(string.concat("Max Shares to redeem:", maxShares.toString()));

        try actor.redeem(_vaultWithCollateral, maxShares) {}
        catch {
            assert(false);
        }
    }

    function maxBorrow_correctReturnValue(uint8 _actorIndex) public {
        emit LogUint256("[maxBorrow_correctReturnValue] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        uint256 maxAssets = vault0.maxBorrow(address(actor));
        require(maxAssets != 0, "Zero assets to borrow");

        emit LogString(string.concat("Max Assets to borrow:", maxAssets.toString()));
        emit ExactAmount("maxAssets:", maxAssets);

        (address protShareToken, address collShareToken,) = siloConfig.getShareTokens(address(vault1));
        emit ExactAmount("protected share decimals:", TestERC20Token(protShareToken).decimals());
        emit ExactAmount("protected decimals:", _asset0.decimals());
        emit ExactAmount("collateral balance:", TestERC20Token(collShareToken).balanceOf(address(actor)));
        emit ExactAmount("collateral share decimals:", TestERC20Token(collShareToken).decimals());
        emit ExactAmount("collateral decimals:", _asset1.decimals());

        try actor.borrow(true, maxAssets) {}
        catch {
            assert(false);
        }
    }

    function maxBorrowShares_correctReturnValue(uint8 _actorIndex) public {
        emit LogUint256("[maxBorrowShares_correctReturnValue] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        uint256 maxShares = vault0.maxBorrowShares(address(actor));
        require(maxShares != 0, "Zero assets to borrow");

        emit LogString(string.concat("Max Shares to borrow:", maxShares.toString()));
        _dumpState(address(actor));

        try actor.borrowShares(true, maxShares) {}
        catch {
            assert(false);
        }
    }

    function maxRepay_correctReturnValue(uint8 _actorIndex) public {
        emit LogUint256("[maxRepay_correctReturnValue] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        uint256 maxAssets = vault0.maxRepay(address(actor));
        require(maxAssets != 0, "Zero assets to repay");
        require(_asset0.balanceOf(address(actor)) >= maxAssets, "Insufficient balance for debt repayment");

        (,, address debtShareToken0) = siloConfig.getShareTokens(address(vault0));
        uint256 actorDebt = IERC20(debtShareToken0).balanceOf(address(actor));
        require(actorDebt > 0, "Actor has no debt");

        emit LogString(string.concat("Max Assets to repay:", maxAssets.toString()));

        try actor.repay(true, maxAssets) {}
        catch {
            assert(false);
        }
    }

    function maxRepayShares_correctReturnValue(uint8 _actorIndex) public {
        emit LogUint256("[maxRepayShares_correctReturnValue] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        uint256 maxShares = vault0.maxRepayShares(address(actor));
        require(maxShares != 0, "Zero shares to repay");
        (,, address debtShareToken0) = siloConfig.getShareTokens(address(vault0));
        uint256 actorDebt = IERC20(debtShareToken0).balanceOf(address(actor));
        require(actorDebt > 0, "Actor has no debt");

        uint256 assets = vault0.previewRepayShares(maxShares);
        require(_asset0.balanceOf(address(actor)) >= assets, "Not enough assets to repay");

        emit LogString(string.concat("User debt shares:", actorDebt.toString()));
        emit LogString(string.concat("Max Shares to repay:", maxShares.toString()));

        try actor.repayShares(true, maxShares) {}
        catch {
            assert(false);
        }
    }

    function maxLiquidation_correctReturnValue(uint8 _actorIndex) public {
        emit LogUint256("[maxLiquidation_correctReturnValue] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        Actor secondActor = _selectActor(_actorIndex + 1);

        (bool isSolvent, bool _vaultZeroWithDebt) = _invariant_insolventHasDebt(address(actor));
        require(!isSolvent, "user not solvent");

        Silo siloWithDebt = _vaultZeroWithDebt ? vault0 : vault1;

        (uint256 collateralToLiquidate, uint256 debtToRepay,) = liquidationModule.maxLiquidation(address(actor));

        require(collateralToLiquidate != 0 && debtToRepay != 0, "Nothing to liquidate");

        emit LogString(string.concat("debtToRepay:", debtToRepay.toString()));
        emit LogString(string.concat("collateralToLiquidate:", collateralToLiquidate.toString()));

        emit LogString(
            string.concat("borrower LTV before liquidation:", siloWithDebt.getLtv(address(actor)).toString())
        );

        try secondActor.liquidationCall(address(actor), debtToRepay, false, siloConfig) {}
        catch {
            assert(false);
        }
    }

    /* ================================================================
                            Properties:
            checking if preview* functions are aligned with ERC4626
       ================================================================ */

    function previewDeposit_doesNotReturnMoreThanDeposit(uint8 _actorIndex, uint256 assets) public {
        emit LogUint256("[previewDeposit_doesNotReturnMoreThanDeposit] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        uint256 previewShares = vault0.previewDeposit(assets);
        uint256 shares = actor.deposit(true, assets);
        assertLte(previewShares, shares, "previewDeposit overestimates shares!");
    }

    function previewMint_DoesNotReturnLessThanMint(uint8 _actorIndex, uint256 shares) public {
        emit LogUint256("[previewMint_DoesNotReturnLessThanMint] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        uint256 previewAssets = vault0.previewMint(shares);
        uint256 assets = actor.mint(true, shares);
        assertGte(previewAssets, assets, "previewMint underestimates assets!");
    }

    function previewWithdraw_doesNotReturnLessThanWithdraw(uint8 _actorIndex, uint256 assets) public {
        emit LogUint256("[previewWithdraw_doesNotReturnLessThanWithdraw] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        uint256 previewShares = vault0.previewWithdraw(assets);
        uint256 shares = actor.withdraw(true, assets);
        assertGte(previewShares, shares, "previewWithdraw underestimates shares!");
    }

    function previewRedeem_doesNotReturnMoreThanRedeem(uint8 _actorIndex, uint256 shares) public {
        emit LogUint256("[previewRedeem_doesNotReturnMoreThanRedeem] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        uint256 previewAssets = vault0.previewRedeem(shares);
        uint256 assets = actor.redeem(true, shares);
        assertLte(previewAssets, assets, "previewRedeem overestimates assets!");
    }

    /* ================================================================
                            Properties:
            Check if shares or assets can round down to zero
       ================================================================ */
    function depositNeverMintsZeroShares(uint8 _actorIndex, bool _vaultZero, uint256 _amount) public {
        emit LogUint256("[depositNeverMintsZeroShares] block.timestamp:", block.timestamp);

        uint256 shares = deposit(_actorIndex, _vaultZero, _amount);
        assertNeq(shares, 0, "Deposit minted zero shares");
    }

    function repayNeverReturnsZeroAssets(uint8 _actorIndex, bool _vaultZero, uint256 shares) public {
        emit LogUint256("[repayNeverReturnsZeroAssets] block.timestamp:", block.timestamp);

        uint256 assets = repayShares(_actorIndex, _vaultZero, shares);
        assertNeq(assets, 0, "repayShares returned zero assets");
    }

    /* ================================================================
                            Other properties
       ================================================================ */

    // Property: Total debt shares should never be larger than total debt
    function debtSharesNeverLargerThanDebt() public view {
        uint256 debt0 = vault0.getDebtAssets();
        uint256 debt1 = vault1.getDebtAssets();

        (,, address debtShareToken0) = siloConfig.getShareTokens(address(vault0));
        (,, address debtShareToken1) = siloConfig.getShareTokens(address(vault1));

        uint256 debtShareBalance0 = IERC20(debtShareToken0).totalSupply();
        uint256 debtShareBalance1 = IERC20(debtShareToken1).totalSupply();

        assert(debt0 >= debtShareBalance0);
        assert(debt1 >= debtShareBalance1);
    }

    // Property: A user who's debt is above the liquidation threshold cannot be liquidated by another user
    function cannotLiquidateUserUnderLt(uint8 _actorIndex, bool receiveShares) public {
        emit LogUint256("[cannotLiquidateUserUnderLt] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        Actor liquidator = _selectActor(_actorIndex + 1);

        (bool isSolvent, bool _vaultZeroWithDebt) = _invariant_insolventHasDebt(address(actor));

        Silo vault = _vaultZeroWithDebt ? vault0 : vault1;

        require(isSolvent, "User LTV too large");

        uint256 lt = vault.getLt();
        uint256 ltv = vault.getLtv(address(actor));

        (, uint256 debtToRepay,) = liquidationModule.maxLiquidation(address(actor));

        try liquidator.liquidationCall(address(actor), debtToRepay, receiveShares, siloConfig) {
            emit LogString(string.concat("User LTV:", ltv.toString(), " Liq Threshold:", lt.toString()));
            emit LogString("User liquidated!");
            assert(false);
        } catch {
            // do nothing, it is expected
        }
    }

    // Property: A user who's debt is above the liquidation threshold cannot be liquidated by another user
    function cannotLiquidateASolventUser(uint8 _actorIndex, bool receiveShares) public {
        emit LogUint256("[cannotLiquidateASolventUser] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        Actor liquidator = _selectActor(_actorIndex + 1);

        (bool isSolvent, bool _vaultZeroWithDebt) = _invariant_insolventHasDebt(address(actor));

        require(isSolvent, "user not solvent - ignoring this case");

        (, uint256 debtToRepay,) = liquidationModule.maxLiquidation(address(actor));

        _requireTotalCap(_vaultZeroWithDebt, address(liquidator), debtToRepay);

        try liquidator.liquidationCall(address(actor), debtToRepay, receiveShares, siloConfig) {
            emit LogString("Solvent user liquidated!");
            assert(false);
        } catch {
            // do nothing
        }
    }

    // Property: An insolvent user cannot prevent others from liquidating his debt
    function cannotPreventInsolventUserFromBeingLiquidated(uint8 _actorIndex, bool receiveShares) public {
        emit LogUint256("[cannotPreventInsolventUserFromBeingLiquidated] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        Actor liquidator = _selectActor(_actorIndex + 1);

        (bool isSolvent, bool _vaultZeroWithDebt) = _invariant_insolventHasDebt(address(actor));
        require(!isSolvent, "[cannotPreventInsolventUserFromBeingLiquidated] user must be insolvent");

        emit LogString(isSolvent ? "user is solvent" : "user is NOT solvent");

        (, uint256 debtToRepay,) = liquidationModule.maxLiquidation(address(actor));

        _requireTotalCap(_vaultZeroWithDebt, address(liquidator), debtToRepay);

        try liquidator.liquidationCall(address(actor), debtToRepay, receiveShares, siloConfig) {}
        catch {
            emit LogString("Cannot liquidate insolvent user!");
            assert(false);
        }
    }

    // Property: A slightly insolvent user cannot be fully liquidated, if he is below "dust" treshhold
    // it is hard to figure out, if this case is partial or we need to force full,
    // we forcing full when `repayValue/_totalBorrowerDebtValue` > _FULL_LIQUIDATION_THRESHOLD
    // so max repay value under dust level is `repayValue = _totalBorrowerDebtValue * _FULL_LIQUIDATION_THRESHOLD`
    // based on this we will make decision if this is partial or full liquidation and we will run some checks
    function cannotFullyLiquidateSmallLtv(uint8 _actorIndex) public {
        emit LogUint256("[cannotFullyLiquidateSmallLtv] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        Actor actorTwo = _selectActor(_actorIndex + 1);

        (bool isSolvent, bool _vaultZeroWithDebt) = _invariant_insolventHasDebt(address(actor));
        require(!isSolvent, "we only want insolvent cases here");

        Silo vault = _vaultZeroWithDebt ? vault0 : vault1;

        uint256 ltvBefore = vault.getLtv(address(actor));

        uint256 maxRepay = vault.maxRepay(address(actor));
        // we assume we do not have oracle and price is 1:1
        uint256 maxPartialRepayValue = maxRepay * PartialLiquidationLib._FULL_LIQUIDATION_THRESHOLD / 1e18;
        (, uint256 debtToRepay,) = liquidationModule.maxLiquidation(address(actor));

        bool isPartial = debtToRepay < maxPartialRepayValue;

        if (!isPartial) {
            assertEq(debtToRepay, maxRepay, "we assume, this is full liquidation");
        }

        _requireTotalCap(_vaultZeroWithDebt, address(actorTwo), debtToRepay);

        actorTwo.liquidationCall(address(actor), debtToRepay, false, siloConfig);

        uint256 ltvAfter = vault.getLtv(address(actor));
        emit LogString(string.concat("User afterLtv:", ltvAfter.toString()));

        if (isPartial) {
            assertLt(ltvAfter, ltvBefore, "we expect LTV to go down after partial liquidation");

            Silo siloWithCollateral = _vaultZeroWithDebt ? vault1 : vault0;
            uint256 lt = siloWithCollateral.getLt();
            emit LogString(string.concat("User LTV:", ltvAfter.toString(), " Liq Threshold:", lt.toString()));

            assert(ltvAfter > 0 && ltvAfter < lt);
        } else {
            assertEq(ltvAfter, 0, "when not partial, user should be completely liquidated");
        }
    }

    // Property: A user transitioning his collateral cannot receive more shares
    function transitionCollateral_doesNotResultInMoreShares(
        uint8 _actorIndex,
        bool _vaultZero,
        uint256 shares,
        ISilo.CollateralType assetType
    ) public {
        emit LogUint256("[transitionCollateral_doesNotResultInMoreShares] block.timestamp:", block.timestamp);

        Actor actor = _selectActor(_actorIndex);
        Silo vault = _vaultZero ? vault0 : vault1;

        (address protected, address collateral,) = siloConfig.getShareTokens(address(vault));

        uint256 maxWithdrawSumBefore;

        uint256 protBalanceBefore = IShareToken(protected).balanceOf(address(actor));
        uint256 collBalanceBefore = IShareToken(collateral).balanceOf(address(actor));

        {
            // too deep
            uint256 maxCollateralBefore = vault.maxWithdraw(address(actor), ISilo.CollateralType.Collateral);
            uint256 maxProtectedBefore = vault.maxWithdraw(address(actor), ISilo.CollateralType.Protected);
            maxWithdrawSumBefore = maxCollateralBefore + maxProtectedBefore;
        }

        actor.transitionCollateral(_vaultZero, shares, assetType);

        uint256 protBalanceAfter = IShareToken(protected).balanceOf(address(actor));
        uint256 collBalanceAfter = IShareToken(collateral).balanceOf(address(actor));

        {
            // too deep
            uint256 maxCollateralAfter = vault.maxWithdraw(address(actor), ISilo.CollateralType.Collateral);
            uint256 maxProtectedAfter = vault.maxWithdraw(address(actor), ISilo.CollateralType.Protected);
            uint256 maxAssetsSumAfter = maxCollateralAfter + maxProtectedAfter;

            assertGte(
                maxWithdrawSumBefore,
                maxAssetsSumAfter,
                "price is flat, so there should be no gains (we accept 2 wei loss)"
            );

            assertLte(maxWithdrawSumBefore - maxAssetsSumAfter, 1, "we accept 1 wei loss");
        }

        {
            // too deep
            // note: this could result in false positives due to interest calculation, and differences between
            // protected and unprotected shares/balances. Another way to check this property would be to
            // transitionCollateral in one direction, and then in the opposite direction, and only check shares/assets
            // after the second transition.

            (uint256 sharesTransitioned, ISilo.CollateralType withdrawType) = assetType
                == ISilo.CollateralType.Collateral
                ? (protBalanceAfter - protBalanceBefore, ISilo.CollateralType.Protected)
                : (collBalanceAfter - collBalanceBefore, ISilo.CollateralType.Collateral);

            // transition back, so we can verify number of shares
            actor.transitionCollateral(_vaultZero, sharesTransitioned, withdrawType);

            protBalanceAfter = IShareToken(protected).balanceOf(address(actor));
            collBalanceAfter = IShareToken(collateral).balanceOf(address(actor));

            uint256 maxCollateralBack = vault.maxWithdraw(address(actor), ISilo.CollateralType.Collateral);
            uint256 maxProtectedBack = vault.maxWithdraw(address(actor), ISilo.CollateralType.Protected);
            uint256 maxAssetsSumBack = maxCollateralBack + maxProtectedBack;

            assertGte(
                maxWithdrawSumBefore,
                maxAssetsSumBack,
                "price is flat, so there should be no gains (we accept 1 wei diff)"
            );

            assertLte(maxWithdrawSumBefore - maxAssetsSumBack, 1, "we accept 1 wei diff");

            assertLte(
                protBalanceBefore - protBalanceAfter,
                25,
                "[protected] there should be no gain in shares, accepting 25 wei loss because of rounding policy"
            );

            assertLte(
                collBalanceBefore - collBalanceAfter,
                25,
                "[collateral] there should be no gain in shares, accepting 25 wei loss because of rounding policy"
            );
        }
    }

    function _checkForInterest(Silo _silo) internal returns (bool noInterest) {
        (, uint256 interestRateTimestamp,,,) = _silo.getSiloStorage();
        noInterest = block.timestamp == interestRateTimestamp;

        if (noInterest) assertEq(_silo.accrueInterest(), 0, "no interest should be applied");
    }

    function _invariant_insolventHasDebt(address _user)
        internal
        returns (bool isSolvent, bool _vaultZeroWithDebt)
    {
        isSolvent = vault0.isSolvent(_user);

        (,, address debtShareToken0) = siloConfig.getShareTokens(_vault0);
        (,, address debtShareToken1) = siloConfig.getShareTokens(_vault1);

        uint256 balance0 = IShareToken(debtShareToken0).balanceOf(_user);
        uint256 balance1 = IShareToken(debtShareToken1).balanceOf(_user);

        if (isSolvent) return (isSolvent, balance0 > 0);

        assertEq(balance0 * balance1, 0, "[_invariant_insolventHasDebt] one balance must be 0");
        assertGt(balance0 + balance1, 0, "user should have debt if he is insolvent");

        return (isSolvent, balance0 > 0);
    }

    function _invariant_onlySolventUserCanRedeem(address _user)
        internal
        returns (bool isSolvent, bool vaultZeroWithCollateral)
    {
        // _dumpState(_user);

        isSolvent = vault0.isSolvent(_user);

        (address protectedShareToken0, address collateralShareToken0, address debtShareToken0) =
            siloConfig.getShareTokens(address(_vault0));

        (,, address debtShareToken1) = siloConfig.getShareTokens(_vault1);

        uint256 debtBalance0 = IShareToken(debtShareToken0).balanceOf(_user);
        uint256 debtBalance1 = IShareToken(debtShareToken1).balanceOf(_user);

        assertEq(debtBalance0 * debtBalance1, 0, "[onlySolventUserCanRedeem] one balance must be 0");

        if (debtBalance0 + debtBalance1 != 0) return (isSolvent, debtBalance0 == 0);

        uint256 protectedBalance0 = IShareToken(protectedShareToken0).balanceOf(_user);
        uint256 collateralBalance0 = IShareToken(collateralShareToken0).balanceOf(_user);

        vaultZeroWithCollateral = protectedBalance0 + collateralBalance0 != 0;
    }

    function _requireHealthySilos() internal view returns (bool healthy) {
        return _requireHealthySilo(vault0) && _requireHealthySilo(vault1);
    }

    function _requireHealthySilo(Silo _silo) internal view returns (bool healthy) {
        ISiloConfig.ConfigData memory cfg = siloConfig.getConfig(address(_silo));

        try IInterestRateModel(cfg.interestRateModel).getCompoundInterestRate(address(_silo), block.timestamp) {
            // we only accepting cased were we do not revert
            healthy = true;
        } catch {
            // we dont want case, where IRM fail
        }
    }

    function _dumpState(address _actor) internal {
        emit ExactAmount("block.number:", block.number);
        emit ExactAmount("block.timestamp:", block.timestamp);

        (uint256 collectedFees0, uint256 irmTimestamp0,,,) = vault0.getSiloStorage();
        (uint256 collectedFees1, uint256 irmTimestamp1,,,) = vault1.getSiloStorage();

        emit ExactAmount("collectedFees0:", collectedFees0);
        emit ExactAmount("irmTimestamp0:", irmTimestamp0);
        emit ExactAmount("collectedFees1:", collectedFees1);
        emit ExactAmount("irmTimestamp1:", irmTimestamp1);

        emit ExactAmount("LTV0:", vault0.getLtv(_actor));
        emit ExactAmount("LTV1:", vault1.getLtv(_actor));

        (address protectedToken0, address collateralToken0, address debtShareToken0) =
            siloConfig.getShareTokens(_vault0);

        (address protectedToken1, address collateralToken1, address debtShareToken1) =
            siloConfig.getShareTokens(_vault1);

        emit ExactAmount("protectedToken0.balanceOf:", IShareToken(protectedToken0).balanceOf(_actor));
        emit ExactAmount("collateralToken0.balanceOf:", IShareToken(collateralToken0).balanceOf(_actor));
        emit ExactAmount("debtShareToken0.balanceOf:", IShareToken(debtShareToken0).balanceOf(_actor));

        emit ExactAmount("protectedToken1.balanceOf:", IShareToken(protectedToken1).balanceOf(_actor));
        emit ExactAmount("collateralToken1.balanceOf:", IShareToken(collateralToken1).balanceOf(_actor));
        emit ExactAmount("debtShareToken1.balanceOf:", IShareToken(debtShareToken1).balanceOf(_actor));

        emit ExactAmount("maxWithdraw0:", vault0.maxWithdraw(_actor));
        emit ExactAmount("maxWithdraw1:", vault1.maxWithdraw(_actor));

        {
            // too deep
            uint256 maxBorrow0 = vault0.maxBorrow(_actor);
            uint256 maxBorrow1 = vault1.maxBorrow(_actor);
            emit ExactAmount("maxBorrow0:", maxBorrow0);
            emit ExactAmount("maxBorrow1:", maxBorrow1);

            emit ExactAmount(
                "convertToShares(maxBorrow0):", vault0.convertToShares(maxBorrow0, ISilo.AssetType.Debt)
            );
            emit ExactAmount(
                "convertToShares(maxBorrow1):", vault1.convertToShares(maxBorrow1, ISilo.AssetType.Debt)
            );
        }

        emit ExactAmount("maxBorrowShares0:", vault0.maxBorrowShares(_actor));
        emit ExactAmount("maxBorrowShares1:", vault1.maxBorrowShares(_actor));
    }

    function _requireTotalCap(bool _vaultZero, address actor, uint256 requiredBalance) internal view {
        TestERC20Token token = _vaultZero ? _asset0 : _asset1;
        uint256 balance = token.balanceOf(actor);

        if (balance < requiredBalance) {
            require(type(uint256).max - token.totalSupply() >= requiredBalance - balance, "total supply limit");
        }
    }

    /* ================================================================
                            Utility functions
       ================================================================ */
    function _selectActor(uint8 index) internal returns (Actor actor) {
        uint256 actorIndex = clampBetween(uint256(index), 0, actors.length - 1);
        emit LogString(string.concat("Actor selected index:", actorIndex.toString()));

        return actors[actorIndex];
    }

    function _overflowCheck(uint256 a, uint256 b) internal pure {
        uint256 c;
        unchecked {
            c = a + b;
        }

        require(c >= a, "OVERFLOW!");
    }

    function _balanceOfSilo(bool _vaultZero) internal view returns (uint256 assets) {
        address vault = _vaultZero ? _vault0 : _vault1;
        TestERC20Token asset = _vaultZero ? _asset0 : _asset1;
        assets = asset.balanceOf(vault);
    }
}
