// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DiamondToken is ERC20, Ownable {
  constructor() ERC20("Diamondz Token", "DMDZ") {
      // Mint 1 million tokens to the contract deployer
      _mint(msg.sender, 1000000 * 10 ** decimals());
  }
  
  // Function to mint new tokens (only owner)
  function mint(address to, uint256 amount) public onlyOwner {
      _mint(to, amount);
  }
}
