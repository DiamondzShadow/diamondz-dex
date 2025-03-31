"use client"

import { useState, useEffect, createContext, useContext, type ReactNode } from "react"
import { ethers } from "ethers"
import { chainConfig } from "./chain-config"

type WalletContextType = {
  provider: ethers.providers.Web3Provider | null
  signer: ethers.Signer | null
  account: string | null
  chainId: number | null
  isConnected: boolean
  isCorrectChain: boolean
  balance: string
  connect: () => Promise<void>
  disconnect: () => void
  switchChain: () => Promise<boolean>
}

const WalletContext = createContext<WalletContextType>({
  provider: null,
  signer: null,
  account: null,
  chainId: null,
  isConnected: false,
  isCorrectChain: false,
  balance: "0",
  connect: async () => {},
  disconnect: () => {},
  switchChain: async () => false,
})

export const useWallet = () => useContext(WalletContext)

export const WalletProvider = ({ children }: { children: ReactNode }) => {
  const [provider, setProvider] = useState<ethers.providers.Web3Provider | null>(null)
  const [signer, setSigner] = useState<ethers.Signer | null>(null)
  const [account, setAccount] = useState<string | null>(null)
  const [chainId, setChainId] = useState<number | null>(null)
  const [isConnected, setIsConnected] = useState(false)
  const [isCorrectChain, setIsCorrectChain] = useState(false)
  const [balance, setBalance] = useState("0")

  // Initialize provider from window.ethereum
  useEffect(() => {
    if (typeof window !== "undefined" && window.ethereum) {
      const ethersProvider = new ethers.providers.Web3Provider(window.ethereum, "any")
      setProvider(ethersProvider)

      // Check if already connected
      ethersProvider.listAccounts().then((accounts) => {
        if (accounts.length > 0) {
          handleAccountsChanged(accounts)
        }
      })

      // Listen for chain changes
      window.ethereum.on("chainChanged", (chainIdHex: string) => {
        const newChainId = Number.parseInt(chainIdHex, 16)
        setChainId(newChainId)
        setIsCorrectChain(newChainId === chainConfig.chainId)

        // Refresh provider and signer on chain change
        const updatedProvider = new ethers.providers.Web3Provider(window.ethereum, "any")
        setProvider(updatedProvider)
        if (account) {
          const updatedSigner = updatedProvider.getSigner()
          setSigner(updatedSigner)
          fetchBalance(updatedProvider, account)
        }
      })

      // Listen for account changes
      window.ethereum.on("accountsChanged", handleAccountsChanged)

      return () => {
        window.ethereum.removeListener("chainChanged", () => {})
        window.ethereum.removeListener("accountsChanged", handleAccountsChanged)
      }
    }
  }, [])

  // Handle account changes
  const handleAccountsChanged = async (accounts: string[]) => {
    if (accounts.length === 0) {
      // User disconnected
      setAccount(null)
      setSigner(null)
      setIsConnected(false)
      setBalance("0")
    } else {
      // User connected or switched accounts
      const newAccount = accounts[0]
      setAccount(newAccount)
      setIsConnected(true)

      if (provider) {
        const newSigner = provider.getSigner()
        setSigner(newSigner)

        // Get chain ID
        const network = await provider.getNetwork()
        const newChainId = network.chainId
        setChainId(newChainId)
        setIsCorrectChain(newChainId === chainConfig.chainId)

        // Get balance
        fetchBalance(provider, newAccount)
      }
    }
  }

  // Fetch account balance
  const fetchBalance = async (provider: ethers.providers.Web3Provider, account: string) => {
    try {
      const rawBalance = await provider.getBalance(account)
      const formattedBalance = ethers.utils.formatEther(rawBalance)
      setBalance(Number.parseFloat(formattedBalance).toFixed(4))
    } catch (error) {
      console.error("Error fetching balance:", error)
      setBalance("0")
    }
  }

  // Connect wallet
  const connect = async () => {
    if (!provider) {
      console.error("No provider available")
      return
    }

    try {
      // Request accounts
      const accounts = await window.ethereum.request({ method: "eth_requestAccounts" })
      handleAccountsChanged(accounts)
    } catch (error) {
      console.error("Error connecting wallet:", error)
    }
  }

  // Disconnect wallet (clear state only, can't force disconnect MetaMask)
  const disconnect = () => {
    setAccount(null)
    setSigner(null)
    setIsConnected(false)
    setBalance("0")
  }

  // Switch to the correct chain
  const switchChain = async (): Promise<boolean> => {
    if (!provider) return false

    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: `0x${chainConfig.chainId.toString(16)}` }],
      })
      return true
    } catch (switchError: any) {
      // This error code indicates that the chain has not been added to MetaMask
      if (switchError.code === 4902) {
        try {
          await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [
              {
                chainId: `0x${chainConfig.chainId.toString(16)}`,
                chainName: chainConfig.chainName,
                nativeCurrency: chainConfig.nativeCurrency,
                rpcUrls: chainConfig.rpcUrls,
                blockExplorerUrls: chainConfig.blockExplorerUrls,
              },
            ],
          })
          return true
        } catch (addError) {
          console.error("Error adding chain:", addError)
          return false
        }
      }
      console.error("Error switching chain:", switchError)
      return false
    }
  }

  return (
    <WalletContext.Provider
      value={{
        provider,
        signer,
        account,
        chainId,
        isConnected,
        isCorrectChain,
        balance,
        connect,
        disconnect,
        switchChain,
      }}
    >
      {children}
    </WalletContext.Provider>
  )
}
