// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./Pair.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DEXFactory
 * @dev Factory contract to create trading pairs dynamically
 * Based on Uniswap V2 Factory pattern
 */
contract DEXFactory is Ownable {
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    address public feeTo;
    address public feeToSetter;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    constructor(address _feeToSetter) Ownable(msg.sender) {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "DEXFactory: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "DEXFactory: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "DEXFactory: PAIR_EXISTS");

        // Deploy new pair using new keyword
        pair = address(new Pair(token0, token1));

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "DEXFactory: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "DEXFactory: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }
}
