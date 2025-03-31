// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IDiamondFactory {
  function feeTo() external view returns (address);
  function protocolFeeDenominator() external view returns (uint);
}

contract DiamondPair is ERC20, ReentrancyGuard {
  using SafeMath for uint;
  
  // Constants
  uint public constant MINIMUM_LIQUIDITY = 10**3;
  
  // State variables
  address public factory;
  address public token0;
  address public token1;
  
  uint112 private reserve0;
  uint112 private reserve1;
  uint32 private blockTimestampLast;
  
  uint public price0CumulativeLast;
  uint public price1CumulativeLast;
  uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event
  
  // Events
  event Mint(address indexed sender, uint amount0, uint amount1);
  event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
  event Swap(
      address indexed sender,
      uint amount0In,
      uint amount1In,
      uint amount0Out,
      uint amount1Out,
      address indexed to
  );
  event Sync(uint112 reserve0, uint112 reserve1);
  
  // Modifiers
  modifier onlyFactory() {
      require(msg.sender == factory, 'DiamondPair: FORBIDDEN');
      _;
  }
  
  constructor() ERC20("Diamondz LP Token", "DMDZ-LP") {
      factory = msg.sender;
  }
  
  // Initialize the pair with tokens
  function initialize(address _token0, address _token1) external onlyFactory {
      token0 = _token0;
      token1 = _token1;
  }
  
  // Update reserves and, on the first call per block, price accumulators
  function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
      require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, 'DiamondPair: OVERFLOW');
      uint32 blockTimestamp = uint32(block.timestamp % 2**32);
      uint32 timeElapsed = blockTimestamp - blockTimestampLast;
      
      // Simplified price accumulation
      if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
          // Update price accumulators using simple division
          if (_reserve0 > 0) {
              price0CumulativeLast += (uint(_reserve1) * 1e18 / _reserve0) * timeElapsed;
          }
          if (_reserve1 > 0) {
              price1CumulativeLast += (uint(_reserve0) * 1e18 / _reserve1) * timeElapsed;
          }
      }
      
      reserve0 = uint112(balance0);
      reserve1 = uint112(balance1);
      blockTimestampLast = blockTimestamp;
      emit Sync(reserve0, reserve1);
  }
  
  // Mint liquidity tokens
  function mint(address to) external nonReentrant returns (uint liquidity) {
      (uint112 _reserve0, uint112 _reserve1,) = getReserves();
      uint balance0 = IERC20(token0).balanceOf(address(this));
      uint balance1 = IERC20(token1).balanceOf(address(this));
      uint amount0 = balance0.sub(_reserve0);
      uint amount1 = balance1.sub(_reserve1);
      
      bool feeOn = _mintFee(_reserve0, _reserve1);
      uint _totalSupply = totalSupply();
      
      if (_totalSupply == 0) {
          liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
          _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
      } else {
          liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
      }
      
      require(liquidity > 0, 'DiamondPair: INSUFFICIENT_LIQUIDITY_MINTED');
      _mint(to, liquidity);
      
      _update(balance0, balance1, _reserve0, _reserve1);
      if (feeOn) kLast = uint(reserve0).mul(reserve1);
      
      emit Mint(msg.sender, amount0, amount1);
  }
  
  // Burn liquidity tokens
  function burn(address to) external nonReentrant returns (uint amount0, uint amount1) {
      (uint112 _reserve0, uint112 _reserve1,) = getReserves();
      address _token0 = token0;
      address _token1 = token1;
      uint balance0 = IERC20(_token0).balanceOf(address(this));
      uint balance1 = IERC20(_token1).balanceOf(address(this));
      uint liquidity = balanceOf(address(this));
      
      bool feeOn = _mintFee(_reserve0, _reserve1);
      uint _totalSupply = totalSupply();
      
      amount0 = liquidity.mul(balance0) / _totalSupply;
      amount1 = liquidity.mul(balance1) / _totalSupply;
      
      require(amount0 > 0 && amount1 > 0, 'DiamondPair: INSUFFICIENT_LIQUIDITY_BURNED');
      _burn(address(this), liquidity);
      
      _safeTransfer(_token0, to, amount0);
      _safeTransfer(_token1, to, amount1);
      
      balance0 = IERC20(_token0).balanceOf(address(this));
      balance1 = IERC20(_token1).balanceOf(address(this));
      
      _update(balance0, balance1, _reserve0, _reserve1);
      if (feeOn) kLast = uint(reserve0).mul(reserve1);
      
      emit Burn(msg.sender, amount0, amount1, to);
  }

  // Swap tokens
  function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external nonReentrant {
      require(amount0Out > 0 || amount1Out > 0, 'DiamondPair: INSUFFICIENT_OUTPUT_AMOUNT');
      (uint112 _reserve0, uint112 _reserve1,) = getReserves();
      require(amount0Out < _reserve0 && amount1Out < _reserve1, 'DiamondPair: INSUFFICIENT_LIQUIDITY');
      
      uint balance0;
      uint balance1;
      { // scope for _token{0,1}, avoids stack too deep errors
          address _token0 = token0;
          address _token1 = token1;
          require(to != _token0 && to != _token1, 'DiamondPair: INVALID_TO');
          
          if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out);
          if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out);
          if (data.length > 0) IDiamondCallee(to).diamondCall(msg.sender, amount0Out, amount1Out, data);
          
          balance0 = IERC20(_token0).balanceOf(address(this));
          balance1 = IERC20(_token1).balanceOf(address(this));
      }
      
      uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
      uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
      require(amount0In > 0 || amount1In > 0, 'DiamondPair: INSUFFICIENT_INPUT_AMOUNT');
      
      { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
          uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
          uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
          require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'DiamondPair: K');
      }
      
      _update(balance0, balance1, _reserve0, _reserve1);
      emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
  }
  
  // Force balances to match reserves
  function skim(address to) external nonReentrant {
      address _token0 = token0;
      address _token1 = token1;
      _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
      _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
  }
  
  // Force reserves to match balances
  function sync() external nonReentrant {
      _update(
          IERC20(token0).balanceOf(address(this)),
          IERC20(token1).balanceOf(address(this)),
          reserve0,
          reserve1
      );
  }
  
  // Get reserves
  function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
      _reserve0 = reserve0;
      _reserve1 = reserve1;
      _blockTimestampLast = blockTimestampLast;
  }
  
  // Mint fee for protocol
  function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
      address feeTo = IDiamondFactory(factory).feeTo();
      feeOn = feeTo != address(0);
      uint _kLast = kLast;
      
      if (feeOn) {
          if (_kLast != 0) {
              uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
              uint rootKLast = Math.sqrt(_kLast);
              
              if (rootK > rootKLast) {
                  uint numerator = totalSupply().mul(rootK.sub(rootKLast));
                  uint denominator = rootK.mul(IDiamondFactory(factory).protocolFeeDenominator()).add(rootKLast);
                  uint liquidity = numerator / denominator;
                  
                  if (liquidity > 0) _mint(feeTo, liquidity);
              }
          }
      } else if (_kLast != 0) {
          kLast = 0;
      }
  }
  
  // Safe transfer
  function _safeTransfer(address token, address to, uint value) private {
      (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
      require(success && (data.length == 0 || abi.decode(data, (bool))), 'DiamondPair: TRANSFER_FAILED');
  }
}

// Helper library for square root calculations
library Math {
  function min(uint x, uint y) internal pure returns (uint z) {
      z = x < y ? x : y;
  }

  function sqrt(uint y) internal pure returns (uint z) {
      if (y > 3) {
          z = y;
          uint x = y / 2 + 1;
          while (x < z) {
              z = x;
              x = (y / x + x) / 2;
          }
      } else if (y != 0) {
          z = 1;
      }
  }
}

interface IDiamondCallee {
  function diamondCall(address sender, uint amount0, uint amount1, bytes calldata data) external;
}

