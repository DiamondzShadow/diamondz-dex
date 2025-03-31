import { ethers } from "ethers"
import { contractAddresses } from "./chain-config"

// ABI imports
import DiamondRouterABI from "../abi/DiamondRouter.json"
import DiamondFactoryABI from "../abi/DiamondFactory.json"
import DiamondPairABI from "../abi/DiamondPair.json"
import ERC20ABI from "../abi/ERC20.json"

export class ContractService {
  private provider: ethers.providers.Web3Provider
  private signer: ethers.Signer

  // Contract instances
  private routerContract: ethers.Contract
  private factoryContract: ethers.Contract

  constructor(provider: ethers.providers.Web3Provider, signer: ethers.Signer) {
    this.provider = provider
    this.signer = signer

    // Initialize contracts
    this.routerContract = new ethers.Contract(contractAddresses.diamondRouter, DiamondRouterABI, this.signer)

    this.factoryContract = new ethers.Contract(contractAddresses.diamondFactory, DiamondFactoryABI, this.signer)
  }

  // Get token contract
  public getTokenContract(tokenAddress: string): ethers.Contract {
    return new ethers.Contract(tokenAddress, ERC20ABI, this.signer)
  }

  // Get pair contract
  public getPairContract(pairAddress: string): ethers.Contract {
    return new ethers.Contract(pairAddress, DiamondPairABI, this.signer)
  }

  // Get token balance
  public async getTokenBalance(tokenAddress: string, account: string): Promise<string> {
    const tokenContract = this.getTokenContract(tokenAddress)
    const balance = await tokenContract.balanceOf(account)
    const decimals = await tokenContract.decimals()
    return ethers.utils.formatUnits(balance, decimals)
  }
  // Get token allowance
  public async getTokenAllowance(tokenAddress: string, owner: string, spender: string): Promise<string> {
    const tokenContract = this.getTokenContract(tokenAddress)
    const allowance = await tokenContract.allowance(owner, spender)
    const decimals = await tokenContract.decimals()
    return ethers.utils.formatUnits(allowance, decimals)
  }

  // Approve token spending
  public async approveToken(
    tokenAddress: string,
    spender: string,
    amount: string,
  ): Promise<ethers.ContractTransaction> {
    const tokenContract = this.getTokenContract(tokenAddress)
    const decimals = await tokenContract.decimals()
    const parsedAmount = ethers.utils.parseUnits(amount, decimals)
    return tokenContract.approve(spender, parsedAmount)
  }

  // Get pair address
  public async getPairAddress(tokenA: string, tokenB: string): Promise<string> {
    return this.factoryContract.getPair(tokenA, tokenB)
  }

  // Get reserves for a pair
  public async getReserves(tokenA: string, tokenB: string): Promise<[string, string]> {
    const pairAddress = await this.getPairAddress(tokenA, tokenB)

    if (pairAddress === ethers.constants.AddressZero) {
      return ["0", "0"]
    }

    const pairContract = this.getPairContract(pairAddress)
    const [reserve0, reserve1] = await pairContract.getReserves()

    const token0 = await pairContract.token0()
    const isTokenAToken0 = tokenA.toLowerCase() === token0.toLowerCase()

    const tokenADecimals = await this.getTokenContract(tokenA).decimals()
    const tokenBDecimals = await this.getTokenContract(tokenB).decimals()

    if (isTokenAToken0) {
      return [ethers.utils.formatUnits(reserve0, tokenADecimals), ethers.utils.formatUnits(reserve1, tokenBDecimals)]
    } else {
      return [ethers.utils.formatUnits(reserve1, tokenADecimals), ethers.utils.formatUnits(reserve0, tokenBDecimals)]
    }
  }

  // Get amounts out (price calculation)
  public async getAmountsOut(amountIn: string, path: string[]): Promise<string[]> {
    if (!amountIn || Number.parseFloat(amountIn) === 0 || path.length < 2) {
      return Array(path.length).fill("0")
    }

    const tokenInContract = this.getTokenContract(path[0])
    const decimals = await tokenInContract.decimals()
    const parsedAmountIn = ethers.utils.parseUnits(amountIn, decimals)

    try {
      const amounts = await this.routerContract.getAmountsOut(parsedAmountIn, path)

      // Format each amount with the correct decimals
      const formattedAmounts = await Promise.all(
        amounts.map(async (amount: ethers.BigNumber, index: number) => {
          const tokenContract = this.getTokenContract(path[index])
          const tokenDecimals = await tokenContract.decimals()
          return ethers.utils.formatUnits(amount, tokenDecimals)
        }),
      )

      return formattedAmounts
    } catch (error) {
      console.error("Error getting amounts out:", error)
      return Array(path.length).fill("0")
    }
  }

  // Swap exact tokens for tokens
  public async swapExactTokensForTokens(
    amountIn: string,
    amountOutMin: string,
    path: string[],
    to: string,
    deadline: number = Math.floor(Date.now() / 1000) + 20 * 60, // 20 minutes
  ): Promise<ethers.ContractTransaction> {
    const tokenInContract = this.getTokenContract(path[0])
    const tokenOutContract = this.getTokenContract(path[path.length - 1])

    const decimalsIn = await tokenInContract.decimals()
    const decimalsOut = await tokenOutContract.decimals()

    const parsedAmountIn = ethers.utils.parseUnits(amountIn, decimalsIn)
    const parsedAmountOutMin = ethers.utils.parseUnits(amountOutMin, decimalsOut)

    return this.routerContract.swapExactTokensForTokens(parsedAmountIn, parsedAmountOutMin, path, to, deadline)
  }

  // Add liquidity
  public async addLiquidity(
    tokenA: string,
    tokenB: string,
    amountADesired: string,
    amountBDesired: string,
    amountAMin: string,
    amountBMin: string,
    to: string,
    deadline: number = Math.floor(Date.now() / 1000) + 20 * 60, // 20 minutes
  ): Promise<ethers.ContractTransaction> {
    const tokenAContract = this.getTokenContract(tokenA)
    const tokenBContract = this.getTokenContract(tokenB)

    const decimalsA = await tokenAContract.decimals()
    const decimalsB = await tokenBContract.decimals()

    const parsedAmountADesired = ethers.utils.parseUnits(amountADesired, decimalsA)
    const parsedAmountBDesired = ethers.utils.parseUnits(amountBDesired, decimalsB)
    const parsedAmountAMin = ethers.utils.parseUnits(amountAMin, decimalsA)
    const parsedAmountBMin = ethers.utils.parseUnits(amountBMin, decimalsB)

    return this.routerContract.addLiquidity(
      tokenA,
      tokenB,
      parsedAmountADesired,
      parsedAmountBDesired,
      parsedAmountAMin,
      parsedAmountBMin,
      to,
      deadline,
    )
  }

  // Remove liquidity
  public async removeLiquidity(
    tokenA: string,
    tokenB: string,
    liquidity: string,
    amountAMin: string,
    amountBMin: string,
    to: string,
    deadline: number = Math.floor(Date.now() / 1000) + 20 * 60, // 20 minutes
  ): Promise<ethers.ContractTransaction> {
    const pairAddress = await this.getPairAddress(tokenA, tokenB)
    const pairContract = this.getPairContract(pairAddress)

    const tokenAContract = this.getTokenContract(tokenA)
    const tokenBContract = this.getTokenContract(tokenB)

    const decimalsA = await tokenAContract.decimals()
    const decimalsB = await tokenBContract.decimals()
    const decimalsPair = await pairContract.decimals()

    const parsedLiquidity = ethers.utils.parseUnits(liquidity, decimalsPair)
    const parsedAmountAMin = ethers.utils.parseUnits(amountAMin, decimalsA)
    const parsedAmountBMin = ethers.utils.parseUnits(amountBMin, decimalsB)

    return this.routerContract.removeLiquidity(
      tokenA,
      tokenB,
      parsedLiquidity,
      parsedAmountAMin,
      parsedAmountBMin,
      to,
      deadline,
    )
  }

  // Get all pairs
  public async getAllPairs(): Promise<string[]> {
    const pairsLength = await this.factoryContract.allPairsLength()
    const pairs = []

    for (let i = 0; i < pairsLength; i++) {
      const pairAddress = await this.factoryContract.allPairs(i)
      pairs.push(pairAddress)
    }

    return pairs
  }
}
EOL
