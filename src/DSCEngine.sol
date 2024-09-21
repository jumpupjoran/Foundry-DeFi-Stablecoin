// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralisedStableCoin} from "./DecentralisedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/Test.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author Joran Vanwesenbeeck
 * The system is designed to be as minimal as possible and have the tokens maintain a 1 token == $1 peg.
 * Properties of the stablecoin:
 * Collateral: Exogenous (ETH&BTC)
 * algoritmically stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
 *
 * Our DSC system should always be "over-collateralized".
 *
 * @notice This contract is the core of the DSC System. It handles all the logic for minign and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is a very  loosely based on MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    /////////////////////////////////////////////////
    ///////////////////errors////////////////////////
    /////////////////////////////////////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAndPriceFeedAddressesMustBeTheSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorBelowOne();
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOK();
    error DSCEngine__HealthFactorNotImproved();
    /////////////////////////////////////////////////
    ///////////////////Types/////////////////////////
    /////////////////////////////////////////////////

    using OracleLib for AggregatorV3Interface;

    /////////////////////////////////////////////////
    ///////////////state variables///////////////////
    /////////////////////////////////////////////////
    DecentralisedStableCoin private immutable i_dsc; // the DSC token

    uint256 private constant ADDIDTION_FEED_PRECISSION = 1e10;
    uint256 private constant PRECISSION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralised, we can only mint half as much as we deposit
    uint256 private constant LIQUIDATION_PRECISSION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // if health factor is below 1, then the user can be liquidated
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidating a user

    // @dev Mapping of token to pricefeed address
    mapping(address token => address priceFeed) private s_priceFeeds;
    // @dev 2D mapping of user to token to collateral
    mapping(address user => mapping(address token => uint256 collateral)) private s_collateralDeposited;
    // @dev mapping of user to amount DSC minted
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    // @dev array of all the allowed collateral tokens
    address[] private s_collateralTokens;

    /////////////////////////////////////////////////
    ///////////////////Events////////////////////////
    /////////////////////////////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address redeemedTo, address indexed token, uint256 amount);

    /////////////////////////////////////////////////
    /////////////////modifiers///////////////////////
    /////////////////////////////////////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    /////////////////////////////////////////////////
    /////////////////Functions///////////////////////
    /////////////////////////////////////////////////
    /**
     * @param tokenAddresses The addresses of the tokens to be used as collateral
     * @param priceFeedAddresses The addresses of the price feeds for the tokens
     * @param dscAddress The address of the DSC token
     * @notice this constructor will set the price feeds for the tokens and the DSC token
     */
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            // checking if the token and pricefeed addresses are the same length
            revert DSCEngine__TokenAndPriceFeedAddressesMustBeTheSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            // filling in the empty mapping (so it knows where to find the price of each token)
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralisedStableCoin(dscAddress); // setting the DSC token
    }

    /////////////////////////////////////////////////
    //////////////external functions/////////////////
    /////////////////////////////////////////////////

    /**
     * @param tokenCollateralAddress The address of the token to be deposited as collateral
     * @param amountCollateral The amount of collateral to be deposited
     * @param amountDscToMint The amount of DSC to mint
     * @notice this function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }

    /**
     * @param tokenCollateralAddress The address of the token to be deposited as collateral
     * @param amountCollateral The amount of collateral to be deposited
     * @param  amountDscToBurn The amount of DSC to burn
     * @notice This function burns DSC and redeems collateral in one transaction
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
        moreThanZero(amountDscToBurn)
    {
        burnDSC(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral); // redeemCollateral already checks health factor
    }

    /**
     * @param collaterAddress The address of the collateral to be liquidated
     * @param user The address of the user who has broken the MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC to burn to improve the users health factor
     * @notice you can partially liquidate a user
     * @notice you will get a bonus for liquidating a user
     * @notice This funciton working assumes the protocol will be roughly 200% overcollateralised in order for this to work
     * @notice a know bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentive the liquidation of users
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(address collaterAddress, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthfactor = _healthFactor(user);
        if (startingUserHealthfactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOK();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collaterAddress, debtToCover);
        uint256 bonusCollatteral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISSION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollatteral;
        _redeemCollateral(user, msg.sender, collaterAddress, totalCollateralToRedeem);
        _burnDSC(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthfactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /////////////////////////////////////////////////
    //////////////Public functions///////////////////
    /////////////////////////////////////////////////
    /**
     * @notice follows CEI pattern
     * @param amountDscToMint The amount of DSC to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDSC(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // if they minted too much
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * @notice follows CEI pattern
     * @param tokenCollateralAddress The address of the token to be deposited as collateral
     * @param amountCollateral The amount of collateral to be deposited
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool succes = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!succes) {
            revert DSCEngine__TransferFailed();
        }
    }
    /**
     * @param tokenCollateralAddress The address of the token to be redeemed
     * @param amountCollateral The amount of collateral to be redeemed
     * @notice This function will redeem the collateral
     */

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param amountDscToBurn The amount of DSC to burn
     * @notice This function burns DSC
     */
    function burnDSC(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) {
        _burnDSC(amountDscToBurn, msg.sender, msg.sender);

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /////////////////////////////////////////////////
    //////////////Private functions//////////////////
    /////////////////////////////////////////////////

    /**
     * @dev Low-Level internal function, do not call unless the function that is calling it
     * is also checking that the health factor doesnt go to low
     */
    function _burnDSC(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        // in the newer version of solidity you dont have to check if they have enough collateral, solidity will revert if he doesnt have enought
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        // calculat the health factor after the collateral is pulled out
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /////////////////////////////////////////////////
    ////////private & internal view functions////////
    /////////////////////////////////////////////////

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @notice this function will calculate the health factor of a user
     * @param user The address of the user
     * @return the health factor of the user
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        private
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISSION;
        uint256 healthFactor = (collateralAdjustedForThreshold * PRECISSION) / totalDscMinted;
        return healthFactor;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor <= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorBelowOne();
        }
    }

    /////////////////////////////////////////////////
    /////////public & external view functions////////
    /////////////////////////////////////////////////

    /**
     * @param token The address of the token
     * @param usdAmountInWei The amount in USD
     * @return the amount of tokens in wei
     */
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISSION) / (uint256(price) * ADDIDTION_FEED_PRECISSION);
    }

    /**
     * @param user The address of the user
     * @return totalCollateralValueInUsd the total collateral value in USD
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    /**
     * @param token The address of the token
     * @param amount The amount of the token
     * @return the value of the token in USD
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (uint256(price) * ADDIDTION_FEED_PRECISSION * amount) / PRECISSION;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function getDSCMinted(address user) public view returns (uint256) {
        return s_DSCMinted[user];
    }

    function getHealthFactor(address user) public view returns (uint256) {
        return _healthFactor(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISSION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISSION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getCollateralBalanceOfUser(address user, address token) public view returns (uint256) {
        return s_collateralDeposited[user][token];
    }
}
