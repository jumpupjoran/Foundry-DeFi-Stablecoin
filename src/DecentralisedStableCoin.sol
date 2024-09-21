// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralisedStableCoin
 * @author Joran Vanwesenbeeck
 * Collateral: Exogenous (ETH&BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to US Dollar
 *
 * This is the contract meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our stablecoinSystem.
 */
contract DecentralisedStableCoin is ERC20Burnable, Ownable {
    error DecentralisedStableCoin__MustBeMoreThanZero();
    error DecentralisedStableCoin__BurnAmountExceedsBalance();
    error DecentralisedStableCoin__MintToZeroAddress();

    constructor() ERC20("DecentralisedStableCoin", "DSC") Ownable(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266) {}

    /**
     * @dev Function to burn the stablecoin tokens
     * @param _amount The amount of tokens to burn
     */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralisedStableCoin__MustBeMoreThanZero();
        }
        if (_amount > balance) {
            revert DecentralisedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount); // super keyword is used to call the parent contract's function, in this case we want to call the burn function from ERC20Burnable
    }

    /**
     * @dev Function to mint stablecoin tokens
     * @param _to The address to mint the tokens to
     * @param _amount The amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralisedStableCoin__MintToZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralisedStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount); // we dont have to say super.mint because we are not overriding the mint function from ERC20. our mint function is called mint and the one from ERC20 is called _mint
        return true;
    }
}
