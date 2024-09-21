// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract MockV3AggregatorTest is Test {
    MockV3Aggregator public mockV3Aggregator;
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000 * 1e8;

    function setUp() public {
        mockV3Aggregator = new MockV3Aggregator(8, ETH_USD_PRICE);
    }

    function testInitialization() public view {
        (, int256 actualETHUSDPrice, , , ) = mockV3Aggregator.latestRoundData();

        assertEq(mockV3Aggregator.decimals(), DECIMALS);
        assertEq(actualETHUSDPrice, ETH_USD_PRICE);
        assertEq(mockV3Aggregator.latestRound(), 1);
    }

    function testUpdateAnswer() public {
        int256 newPrice = 3000 * 1e8;
        mockV3Aggregator.updateAnswer(newPrice);

        (, int256 actualETHUSDPrice, , , ) = mockV3Aggregator.latestRoundData();

        assertEq(actualETHUSDPrice, newPrice);
        assertEq(mockV3Aggregator.latestRound(), 2);
    }

    function testUpdateRoundData() public {
        uint80 roundId = 10;
        int256 roundAnswer = 3000 * 10e8;
        uint256 timestamp = block.timestamp;
        uint256 startedAt = block.timestamp;

        mockV3Aggregator.updateRoundData(
            roundId,
            roundAnswer,
            timestamp,
            startedAt
        );

        // Check that the round data is updated correctly
        (
            uint80 id,
            int256 answer,
            uint256 started,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = mockV3Aggregator.getRoundData(roundId);
        assertEq(id, roundId);
        assertEq(answer, roundAnswer);
        assertEq(started, startedAt);
        assertEq(updatedAt, timestamp);
        assertEq(answeredInRound, roundId);

        // Check that the latest round data is correct
        (
            uint80 latestRoundId,
            int256 latestAnswer,
            ,
            uint256 latestUpdatedAt,

        ) = mockV3Aggregator.latestRoundData();
        assertEq(latestRoundId, roundId);
        assertEq(latestAnswer, roundAnswer);
        assertEq(latestUpdatedAt, timestamp);
    }
}
