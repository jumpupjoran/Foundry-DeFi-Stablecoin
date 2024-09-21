// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract TestHelperConfig is Test {
    HelperConfig public helperConfig;
    HelperConfig.NetworkConfig config;

    function setUp() public {
        helperConfig = new HelperConfig();
        config = helperConfig.getActiveNetworkConfig();
    }

    modifier onlyAnvil() {
        require(block.chainid == 31337);
        _;
    }

    modifier onlySepolia() {
        require(block.chainid == 11155111);
        _;
    }

    function testActiveNetworkConfigIsSet() public view {
        // Check that the activeNetworkConfig is set based on the chainid

        if (block.chainid == 11155111) {
            // Sepolia configuration
            assertEq(config.wethUsdPriceFeed, 0x694AA1769357215DE4FAC081bf1f309aDC325306);
            assertEq(config.wbtcUsdPriceFeed, 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43);
            assertEq(config.weth, 0xdd13E55209Fd76AfE204dBda4007C227904f0a81);
            assertEq(config.wbtc, 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);
        } else {
            // Anvil or local configuration
            assert(config.wethUsdPriceFeed != address(0));
            assert(config.wbtcUsdPriceFeed != address(0));
            assert(config.weth != address(0));
            assert(config.wbtc != address(0));
        }
    }

    function testActiveNetworkConfigIsSetOnSepolia() public {
        vm.chainId(11155111);
        HelperConfig.NetworkConfig memory configAnvil = helperConfig.getSepoliaEthConfig();
        address expectedWethUsdPriceFeed = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        address expectedWbtcPriceFeed = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;
        address expectedWeth = 0xdd13E55209Fd76AfE204dBda4007C227904f0a81;
        address expectedWbtc = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
        // uint256 expectedDeployerKey = vm.envUint("PRIVATE_KEY_SEPOLIA");

        assertEq(configAnvil.wethUsdPriceFeed, expectedWethUsdPriceFeed);
        assertEq(configAnvil.wbtcUsdPriceFeed, expectedWbtcPriceFeed);
        assertEq(configAnvil.weth, expectedWeth);
        assertEq(configAnvil.wbtc, expectedWbtc);
        // assertEq(config.deployerKey, expectedDeployerKey);
    }

    function testGetORCreateAnvilConfig() public onlyAnvil {
        address initialWethUsdPriceFeed = config.wethUsdPriceFeed;
        address initialWbtcUsdPriceFeed = config.wbtcUsdPriceFeed;

        HelperConfig.NetworkConfig memory updatedConfig = helperConfig.getOrcreateAnvilConfig();

        address updatedWethUsdPriceFeed = updatedConfig.wethUsdPriceFeed;
        address updatedWbtcUsdPriceFeed = updatedConfig.wbtcUsdPriceFeed;

        assertEq(initialWethUsdPriceFeed, updatedWethUsdPriceFeed);
        assertEq(initialWbtcUsdPriceFeed, updatedWbtcUsdPriceFeed);
    }
}
