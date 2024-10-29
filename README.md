# Decentralized Stablecoin System

This repository contains the code for a Decentralized Stablecoin System, designed to maintain a stable value through collateralization. The system is built using Solidity and tested with Foundry, featuring an automated deployment setup and comprehensive testing suite.

## Table of Contents

- [Overview](#overview)
- [Getting Started](#getting-started)
- [Architecture](#architecture)
- [Contracts](#contracts)
- [Contract Addresses](#contract-addresses)
- [Deployment](#deployment)
- [Testing](#testing)
- [Security Considerations](#security-considerations)

## Overview

The Decentralized Stablecoin System (DSC) is a DeFi application that allows users to mint a stablecoin by depositing collateral in the form of ERC20 tokens. The stablecoin is backed by this collateral, ensuring that its value remains stable. This project leverages various components, including price oracles, collateral management, and invariant checks to ensure the robustness of the system.

## Getting Started

### Prerequisites

- **Foundry**: Ensure you have Foundry installed. Foundry is a blazing fast, portable, and modular toolkit for Ethereum application development.
- **Node.js**: Node.js is recommended for running any associated scripts or tools.

### Installation

1. Clone the repository:

```bash
git clone https://github.com/your-username/your-repo-name.git
cd your-repo-name
```

2. Install dependencies:

```bash
forge install
```

3. Compile the contracts:

```bash
forge build
```

4. deploying the contracts:

   1. localNode

   ```bash
   make deploy
   ```

   2. Sepolia

   ```bash
   make deploy-sepolia
   ```

   3. Amoy

   ```bash
   make deploy-amoy
   ```

5. Running tests:

```bash
forge test
```

## Architecture

### Core Components

- **Decentralized Stablecoin (DSC)**: The stablecoin issued by the system, which is fully collateralized by assets deposited by users.
- **DSC Engine**: The core engine that handles all operations related to collateral management, minting, and redeeming DSC. It also ensures that the system remains over-collateralized at all times.

- **Price Feeds**: The system uses price feeds to determine the value of collateral. These are implemented using oracles, which provide the necessary data to maintain the stability of the DSC.

### High-Level Workflow

1. **Collateral Deposit**: Users deposit ERC20 tokens as collateral.
2. **Minting**: Based on the value of the deposited collateral, users can mint DSC.
3. **Redemption**: Users can redeem their DSC for the underlying collateral, adjusting the collateral balance accordingly.
4. **Price Stability**: The system continuously checks the health of collateralization using price feeds and liquidates positions if necessary to maintain stability.

## Contracts

### 1. **DecentralisedStableCoin.sol**

- Implements the core stablecoin logic.
- Handles minting, burning, and maintaining balances.
- Ensures that the stablecoin is fully backed by collateral at all times.

### 2. **DSCEngine.sol**

- Manages collateral deposits, redemptions, and stability checks.
- Integrates with price oracles to assess the value of collateral and determine minting limits.
- Facilitates liquidation processes if a user's collateral falls below the required threshold.

### 3. **HelperConfig.sol**

- Provides configuration settings based on the network (e.g., Sepolia,Amoy, Anvil).
- Supplies addresses for price feeds and other critical components depending on the environment.

### 4. **MockV3Aggregator.sol**

- A mock implementation of an aggregator used for testing price feeds.
- Allows the system to be tested in various scenarios without relying on live data.

## Contract Addresses

Here you can find the deployed contract addresses if you want to interact with the protocol on following testnets:

### Sepolia

1. contract DecentralisedStableCoin 0x24A0561Ee261cf7517C49B90d6f7cE2e1dC10bd0
2. contract DSCEngine 0x6C7EFc8bB079060Ba2767087C197fc43F8611AB5
3. contract HelperConfig 0xC7f2Cf4845C6db0e1a1e91ED41Bcd0FcC1b0E141

### Amoy

1. contract DecentralisedStableCoin 0xeF4F4fdfaF20A79D31503c70A1Ea9A3727ECc70D
2. contract DSCEngine 0x1997bA1f2211b696c5E338814890A3cFacE2Cd17
3. contract HelperConfig 0xC7f2Cf4845C6db0e1a1e91ED41Bcd0FcC1b0E141

## Deployment

Deployment scripts are provided to streamline the process of deploying the DSC system to different networks. The deployment process is fully automated and can be tailored to specific environments.

### Key Scripts:

- **DeployDSC.s.sol**

  - Handles the deployment of the DSC and DSCEngine contracts.
  - Sets up the initial configuration required for the system to operate.

- **HelperConfig.s.sol**
  - Configures the system for different networks, ensuring that correct addresses and settings are used.

### Deployment Instructions

To deploy the contracts, use the following command:

```bash
forge script script/DeployDSC.s.sol --rpc-url <NETWORK_RPC_URL> --private-key <PRIVATE_KEY> --broadcast
```

## Testing

The project includes a comprehensive suite of tests written using Foundry. These tests ensure the correctness and security of the contracts, covering both unit tests and invariant tests.

### Testing Strategy

1. **Unit Tests**:

   - Test individual components such as the minting and redemption processes, price feed integration, and error handling.
   - Key test files include `DSCTest.t.sol`, `DSCEngineTest.t.sol`, and `MockV3AggregatorTest.t.sol`.

2. **Invariant Tests**:

   - Ensure that certain properties always hold true, such as the system being over-collateralized.
   - Key test files include `Invariants.t.sol`, `OpenInvariantsTest.t.sol`, and `Handler.t.sol`.

3. **Mocks and Helpers**:
   - Utilize mocks like `MockV3Aggregator` to simulate external dependencies such as price feeds.
   - The `HelperconfigTest.t.sol` file verifies network-specific configurations.

### Running Tests

Run the tests using Foundry:

```bash
forge test
```

## Security Considerations

While this project includes thorough testing, deploying a decentralized stablecoin system to production requires additional security measures, including but not limited to:

- **Formal Verification**: Consider formally verifying the critical contracts.
- **Audits**: Have the contracts audited by professional security auditors.
- **Bug Bounty Program**: Implement a bug bounty program to incentivize the discovery of potential vulnerabilities.
