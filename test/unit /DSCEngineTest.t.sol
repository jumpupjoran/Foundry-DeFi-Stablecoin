// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralisedStableCoin} from "src/DecentralisedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngingeTest is Test {
    DeployDSC deployer;
    DecentralisedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    address weth;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("LIQUIDATOR");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant MINT_AMOUNT = 100 ether;

    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralised, we can only mint half as much as we deposit
    uint256 private constant PRECISSION = 1e18;
    uint256 private constant LIQUIDATION_PRECISSION = 100;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address redeemedTo, address indexed token, uint256 amount);

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    /////////////////////
    /////Constructor/////
    /////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAndPriceFeedAddressesMustBeTheSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////////
    /////Price Tests/////
    /////////////////////
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        //15e18 * 2000/ether = 30000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 30000e18;
        //30000e18 / 2000/ether = 15e18
        uint256 expectedAmount = 15e18;
        uint256 actualAmount = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualAmount, expectedAmount);
    }

    //////////////////////////////////////////
    ////////////deposit collataral test///////
    //////////////////////////////////////////

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approveInternal(USER, address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnaprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock("Ran", "Ran", USER, AMOUNT_COLLATERAL);
        ERC20Mock(randomToken).approveInternal(USER, address(dscEngine), AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approveInternal(USER, address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralWithoutMining() public depositedCollateral {
        assertEq(dsc.balanceOf(USER), 0);
    }

    function testCanDepositCollateralAndGetAccountInformation() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedCollateralValueInUsd = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
    }

    function testCorrectAmountIsDeposited() public depositedCollateral {
        uint256 expectedDepositAmountInUsd = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 actualDepositAmountInUsd = dscEngine.getAccountCollateralValue(USER);
        assertEq(actualDepositAmountInUsd, expectedDepositAmountInUsd);
    }

    function testDepositingCollateralEmitsEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approveInternal(USER, address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false, address(dscEngine));
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);

        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    //////////////////////////////////////////
    ////////////Redeem collataral test////////
    //////////////////////////////////////////

    function testRedeemCollateralFailsWhenRedeemingZero() public depositedCollateral {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
    }

    function testRedeemCollateralWorks() public depositedCollateral {
        uint256 expectedCollateralValueInUsdLeft = 0;
        vm.prank(USER);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        (, uint256 actualCollateralValueInUsdLeft) = dscEngine.getAccountInformation(USER);
        assertEq(actualCollateralValueInUsdLeft, expectedCollateralValueInUsdLeft);
    }

    function testRedeemCollateralRevertsWhenRedeemingToMuch() public depositedCollateral {
        vm.prank(USER);
        vm.expectRevert();
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL * 2);
    }

    function testRedeemCollateralEmitsEvent() public depositedCollateral {
        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    //////////////////////////////////////////
    ////////////redeemCollateralForDsc////////
    //////////////////////////////////////////
    function testredeemCollateralForDscFailsWhenRedeemingZero() public depositedCollateral {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateralForDsc(weth, 0, 0);
    }

    function testredeemCollateralForDscFailsWhenRedeemingToMuch() public depositedCollateral {
        vm.expectRevert();
        dscEngine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_COLLATERAL * 2);
    }

    function testRedeemCollateralForUsdWorks() public depositedCollateral mintedDSC {
        uint256 expectedCollateralValueInUsdLeft = 0;
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), MINT_AMOUNT);
        dscEngine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, MINT_AMOUNT);
        vm.stopPrank();
        (, uint256 actualCollateralValueInUsdLeft) = dscEngine.getAccountInformation(USER);
        assertEq(actualCollateralValueInUsdLeft, expectedCollateralValueInUsdLeft);
    }

    //////////////////////////////////////////
    ////////////Mint Function test////////////
    //////////////////////////////////////////

    modifier mintedDSC() {
        vm.prank(USER);
        dscEngine.mintDSC(MINT_AMOUNT);
        _;
    }

    function testMintFunctionWorks() public depositedCollateral mintedDSC {
        assertEq(dsc.balanceOf(USER), MINT_AMOUNT);
    }

    function testCorrectAmountIsMinted() public depositedCollateral mintedDSC {
        uint256 actualMintedAmount = dscEngine.getDSCMinted(USER);
        assertEq(actualMintedAmount, MINT_AMOUNT);
    }

    function testRevertsWhenMintAmountIsToMuch() public depositedCollateral {
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorBelowOne.selector);
        dscEngine.mintDSC(AMOUNT_COLLATERAL * 10000000000000);
    }

    function testDepositCollateralAndMintDscInOneTransaction() public {
        uint256 expectedDepositedColleteral = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 expectedMintedDsc = MINT_AMOUNT;
        vm.startPrank(USER);
        ERC20Mock(weth).approveInternal(USER, address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, MINT_AMOUNT);
        vm.stopPrank();

        uint256 actualDepositedCollateral = dscEngine.getAccountCollateralValue(USER);
        uint256 actualMintedDsc = dscEngine.getDSCMinted(USER);
        assertEq(actualDepositedCollateral, expectedDepositedColleteral);
        assertEq(actualMintedDsc, expectedMintedDsc);
    }

    //////////////////////////////////////////
    ////////////Burn Function test////////////
    //////////////////////////////////////////

    function testRevertsWhenBurnAmountIsZero() public depositedCollateral {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.burnDSC(0);
    }

    function testRevertsWhenBurnAmountExeedsMintedDsc() public depositedCollateral mintedDSC {
        vm.prank(USER);
        vm.expectRevert();
        dscEngine.burnDSC(MINT_AMOUNT * 2);
    }

    function testRevertsWhenNothingMinted() public depositedCollateral {
        vm.expectRevert();
        dscEngine.burnDSC(MINT_AMOUNT);
    }

    function testBurnFunctionWorks() public depositedCollateral mintedDSC {
        uint256 burnAmount = MINT_AMOUNT / 10;
        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(USER);
        console.log("totalDscMinted: ", totalDscMinted);
        console.log("burnAmount: ", burnAmount);
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), burnAmount);
        dscEngine.burnDSC(burnAmount);
        vm.stopPrank();
        uint256 expectedAmountDscBurned = MINT_AMOUNT - burnAmount;
        assertEq(dsc.balanceOf(USER), expectedAmountDscBurned);
    }

    //////////////////////////////////////////
    ////////GetAccountInformation Test////////
    //////////////////////////////////////////

    function testGetAccountInformation() public depositedCollateral mintedDSC {
        uint256 expectedAmountDscMinted = MINT_AMOUNT;
        uint256 expectedCollateralValueInUsd = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        (uint256 actualAmountDscMinted, uint256 actualCollateralValueInUsd) = dscEngine.getAccountInformation(USER);
        assertEq(actualAmountDscMinted, expectedAmountDscMinted);
        assertEq(actualCollateralValueInUsd, expectedCollateralValueInUsd);
    }

    //////////////////////////////////////////
    ///////////getHealthFactor Test///////////
    //////////////////////////////////////////

    function testHealtFactorIsCorrect() public depositedCollateral mintedDSC {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 expectedcollateralAdjustedForThreshold =
            (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISSION;
        uint256 expectedHealthFactor = (expectedcollateralAdjustedForThreshold * PRECISSION) / totalDscMinted;
        uint256 actualHealthFactor = dscEngine.getHealthFactor(USER);
        assertEq(actualHealthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateral mintedDSC {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);
        console.log("userHealthFactor: ", userHealthFactor);
        uint256 expectedHealthFactor = 0.9 ether;
        console.log("expectedHealthFactor: ", expectedHealthFactor);

        assertEq(userHealthFactor, 0.9 ether);
    }

    //////////////////////////////////////////
    /////////liquidate function Test//////////
    //////////////////////////////////////////

    modifier LIQUIDATOR_Deposited_and_minted() {
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE * 100000);

        ERC20Mock(weth).approveInternal(LIQUIDATOR, address(dscEngine), AMOUNT_COLLATERAL * 100000);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL * 100000);
        dscEngine.mintDSC(MINT_AMOUNT);
        DecentralisedStableCoin(address(dsc)).approve(address(dscEngine), MINT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testRevertsWhenLiquidatingUserWithHealthFactorAboveOne()
        public
        depositedCollateral
        mintedDSC
        LIQUIDATOR_Deposited_and_minted
    {
        // checking that the health factor of the user is above one
        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);
        assert(userHealthFactor > 1);

        vm.prank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOK.selector);
        dscEngine.liquidate(weth, USER, MINT_AMOUNT);
    }

    function testLiquidatingUserWithHealthFactorUnderOneWorks()
        public
        depositedCollateral
        mintedDSC
        LIQUIDATOR_Deposited_and_minted
    {
        // change the price of eth to make the health factor of the user under one
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $20
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        // checks
        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);
        assert((userHealthFactor / PRECISSION) < 1);

        //checks before liquidating
        uint256 userBeginningHealth = dscEngine.getHealthFactor(USER);

        uint256 userBeginningCollateralBalance = dscEngine.getAccountCollateralValue(USER);

        //   LIQUIDATING
        vm.startPrank(LIQUIDATOR);
        dscEngine.liquidate(weth, USER, MINT_AMOUNT);

        // assertions after liquidating
        uint256 userEndingCollateralValue = dscEngine.getAccountCollateralValue(USER);
        uint256 userEndingHealth = dscEngine.getHealthFactor(USER);

        uint256 expectedLiquidatorDscEndingBalance = MINT_AMOUNT - MINT_AMOUNT;
        uint256 actualLiquidatorDscEndingBalance = dsc.balanceOf(LIQUIDATOR);
        assertEq(actualLiquidatorDscEndingBalance, expectedLiquidatorDscEndingBalance);

        assert(expectedLiquidatorDscEndingBalance == actualLiquidatorDscEndingBalance);
        assert(userEndingHealth > userBeginningHealth);
        assert(userBeginningCollateralBalance > userEndingCollateralValue);

        vm.stopPrank();
    }

    //////////////////////////////////////////
    /////////////getter functions/////////////
    //////////////////////////////////////////

    function testGetAccountCollateralValueWorks() public depositedCollateral {
        uint256 expectedCollateralValueInUsd = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 actualCollateralValueInUsd = dscEngine.getAccountCollateralValue(USER);
        assertEq(actualCollateralValueInUsd, expectedCollateralValueInUsd);
    }
}
