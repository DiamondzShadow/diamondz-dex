// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./DiamondPair.sol";

contract DiamondFactory is Ownable {
  // Events
  event PairCreated(address indexed token0, address indexed token1, address pair, uint);
  
  // State variables
  mapping(address => mapping(address => address)) public getPair;
  address[] public allPairs;
  
  // Protocol fee settings
  address public feeTo;
  uint public protocolFeeDenominator = 5; // 1/5 of the 0.3% fee = 0.06%
  
  // Create a new pair
  function createPair(address tokenA, address tokenB) external returns (address pair) {
      require(tokenA != tokenB, 'DiamondFactory: IDENTICAL_ADDRESSES');
      (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
      require(token0 != address(0), 'DiamondFactory: ZERO_ADDRESS');
      require(getPair[token0][token1] == address(0), 'DiamondFactory: PAIR_EXISTS');
      
      // Create new pair contract
      bytes memory bytecode = type(DiamondPair).creationCode;
      bytes32 salt = keccak256(abi.encodePacked(token0, token1));
      assembly {
          pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
      }
      
      // Initialize the pair
      DiamondPair(pair).initialize(token0, token1);
      
      // Store the pair
      getPair[token0][token1] = pair;
      getPair[token1][token0] = pair; // populate mapping in both directions
      allPairs.push(pair);
      
      emit PairCreated(token0, token1, pair, allPairs.length);
  }
  
  // Set the fee recipient
  function setFeeTo(address _feeTo) external onlyOwner {
      feeTo = _feeTo;
  }// Set the protocol fee denominator
  function setProtocolFeeDenominator(uint _protocolFeeDenominator) external onlyOwner {
      require(_protocolFeeDenominator > 0, 'DiamondFactory: INVALID_DENOMINATOR');
      protocolFeeDenominator = _protocolFeeDenominator;
  }
  
  // Get all pairs length
  function allPairsLength() external view returns (uint) {
      return allPairs.length;
  }
}
