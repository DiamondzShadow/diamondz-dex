// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IDiamondPair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function token0() external view returns (address);
    function token1() external view returns (address);
    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function transferFrom(address from, address to, uint value) external returns (bool);
}

interface IDiamondFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);
}

contract DiamondRouter is Ownable, ReentrancyGuard {
    using SafeMath for uint;

    address public immutable factory;
    address public immutable WETH;
    
    // Events
    event Swap(
        address indexed sender,
        uint amountIn,
        uint amountOut,
        address indexed tokenIn,
        address indexed tokenOut
    );
    
    event LiquidityAdded(
        address indexed provider,
        address indexed tokenA,
        address indexed tokenB,
        uint amountA,
        uint amountB,
        uint liquidity
    );
    
    event LiquidityRemoved(
        address indexed provider,
        address indexed tokenA,
        address indexed tokenB,
        uint amountA,
        uint amountB,
        uint liquidity
    );

    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    // Helper function to sort token addresses
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'DiamondRouter: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'DiamondRouter: ZERO_ADDRESS');
    }
    
    // Get pair address from factory
    function pairFor(address tokenA, address tokenB) public view returns (address pair) {
        return IDiamondFactory(factory).getPair(tokenA, tokenB);
    }
    
    // Get reserves for a token pair
    function getReserves(address tokenA, address tokenB) public view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        address pair = pairFor(tokenA, tokenB);
        
        if (pair == address(0)) {
            return (0, 0);
        }
        
        (uint reserve0, uint reserve1,) = IDiamondPair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }
    
    // Quote function to calculate equivalent amount
    function quote(uint amountA, uint reserveA, uint reserveB) public pure returns (uint amountB) {
        require(amountA > 0, 'DiamondRouter: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'DiamondRouter: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }
    
    // Calculate optimal amounts for adding liquidity
    function _calculateLiquidityAmounts(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal view returns (uint amountA, uint amountB) {
        // Check if pair exists
        address pair = pairFor(tokenA, tokenB);
        
        // If pair doesn't exist, just return the desired amounts
        if (pair == address(0)) {
            return (amountADesired, amountBDesired);
        }
        
        // Get reserves
        (uint reserveA, uint reserveB) = getReserves(tokenA, tokenB);
        
        if (reserveA == 0 && reserveB == 0) {
            return (amountADesired, amountBDesired);
        }
        
        // Calculate optimal amounts
        uint amountBOptimal = quote(amountADesired, reserveA, reserveB);
        if (amountBOptimal <= amountBDesired) {
            require(amountBOptimal >= amountBMin, 'DiamondRouter: INSUFFICIENT_B_AMOUNT');
            return (amountADesired, amountBOptimal);
        } else {
            uint amountAOptimal = quote(amountBDesired, reserveB, reserveA);
            assert(amountAOptimal <= amountADesired);
            require(amountAOptimal >= amountAMin, 'DiamondRouter: INSUFFICIENT_A_AMOUNT');
            return (amountAOptimal, amountBDesired);
        }
    }

    // Add liquidity to a pair
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to
    ) external nonReentrant returns (uint amountA, uint amountB, uint liquidity) {
        // Check if pair exists and create it if it doesn't
        address pair = pairFor(tokenA, tokenB);
        if (pair == address(0)) {
            pair = IDiamondFactory(factory).createPair(tokenA, tokenB);
        }
        
        // Calculate optimal amounts
        (amountA, amountB) = _calculateLiquidityAmounts(
            tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin
        );
        
        // Transfer tokens to the pair
        _safeTransferFrom(tokenA, msg.sender, pair, amountA);
        _safeTransferFrom(tokenB, msg.sender, pair, amountB);
        
        // Add liquidity to the pair
        liquidity = IDiamondPair(pair).mint(to);
        
        emit LiquidityAdded(msg.sender, tokenA, tokenB, amountA, amountB, liquidity);
    }
    
    // Remove liquidity from a pair
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to
    ) public nonReentrant returns (uint amountA, uint amountB) {
        address pair = pairFor(tokenA, tokenB);
        
        // Transfer LP tokens to the pair
        IDiamondPair(pair).transferFrom(msg.sender, pair, liquidity);
        
        // Burn LP tokens and get tokens back
        (amountA, amountB) = IDiamondPair(pair).burn(to);
        
        require(amountA >= amountAMin, 'DiamondRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'DiamondRouter: INSUFFICIENT_B_AMOUNT');
        
        emit LiquidityRemoved(msg.sender, tokenA, tokenB, amountA, amountB, liquidity);
    }
    
    // Calculate amount out based on amount in and reserves
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure returns (uint amountOut) {
        require(amountIn > 0, 'DiamondRouter: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'DiamondRouter: INSUFFICIENT_LIQUIDITY');
        
        uint amountInWithFee = amountIn.mul(997); // 0.3% fee
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }
    
    // Calculate amount in based on amount out and reserves
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) public pure returns (uint amountIn) {
        require(amountOut > 0, 'DiamondRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'DiamondRouter: INSUFFICIENT_LIQUIDITY');
        
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }
    
    // Get amounts out for a path
    function getAmountsOut(uint amountIn, address[] memory path) public view returns (uint[] memory amounts) {
        require(path.length >= 2, 'DiamondRouter: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // Get amounts in for a path
    function getAmountsIn(uint amountOut, address[] memory path) public view returns (uint[] memory amounts) {
        require(path.length >= 2, 'DiamondRouter: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
    
    // Swap exact tokens for tokens
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to
    ) external nonReentrant returns (uint[] memory amounts) {
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'DiamondRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        _safeTransferFrom(path[0], msg.sender, pairFor(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
        
        emit Swap(msg.sender, amountIn, amounts[amounts.length - 1], path[0], path[path.length - 1]);
    }
    
    // Swap tokens for exact tokens
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to
    ) external nonReentrant returns (uint[] memory amounts) {
        amounts = getAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, 'DiamondRouter: EXCESSIVE_INPUT_AMOUNT');
        _safeTransferFrom(path[0], msg.sender, pairFor(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
        
        emit Swap(msg.sender, amounts[0], amountOut, path[0], path[path.length - 1]);
    }
    
    // Internal swap function
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? pairFor(output, path[i + 2]) : _to;
            IDiamondPair(pairFor(input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    
    // Safe transfer from
    function _safeTransferFrom(address token, address from, address to, uint value) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'DiamondRouter: TRANSFER_FAILED');
    }
}
