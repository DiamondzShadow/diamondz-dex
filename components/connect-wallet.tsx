"use client"

import { useState, useEffect } from "react"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog"
import { Wallet, AlertTriangle } from 'lucide-react'
import { useWallet } from "@/lib/wallet-connector"
import { chainConfig } from "@/lib/chain-config"

export function ConnectWallet() {
  const { isConnected, account, balance, connect, disconnect, isCorrectChain, switchChain } = useWallet()

  const [isDialogOpen, setIsDialogOpen] = useState(false)
  const [isWrongNetworkDialogOpen, setIsWrongNetworkDialogOpen] = useState(false)

  // Check if on wrong network when connected
  useEffect(() => {
    if (isConnected && !isCorrectChain) {
      setIsWrongNetworkDialogOpen(true)
    } else {
      setIsWrongNetworkDialogOpen(false)
    }
  }, [isConnected, isCorrectChain])

  const handleConnectWallet = async () => {
    await connect()
    setIsDialogOpen(false)
  }

  const handleSwitchNetwork = async () => {
    const success = await switchChain()
    if (success) {
      setIsWrongNetworkDialogOpen(false)
    }
  }

  return (
    <>
      {isConnected ? (
        <div className="flex items-center gap-2">
          <div className="hidden md:block text-right">
            <p className="text-sm font-medium">
              {balance} {chainConfig.nativeCurrency.symbol}
            </p>
            <p className="text-xs text-gray-400">
              {account?.substring(0, 6)}...{account?.substring(account.length - 4)}
            </p>
          </div>
          <Button variant="outline" onClick={disconnect} className="border-gray-700 text-gray-300 hover:text-white">
            <Wallet className="mr-2 h-4 w-4" />
            <span className="md:hidden">
              {account?.substring(0, 6)}...{account?.substring(account.length - 4)}
            </span>
            <span className="hidden md:inline">Disconnect</span>
          </Button>
        </div>
      ) : (
        <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
          <DialogTrigger asChild>
            <Button
              id="connect-wallet-button"
              variant="default"
              className="bg-gradient-to-r from-purple-500 to-pink-600 hover:from-purple-600 hover:to-pink-700"
            >
              <Wallet className="mr-2 h-4 w-4" />
              Connect Wallet
            </Button>
          </DialogTrigger>
          <DialogContent className="sm:max-w-md bg-gray-900 text-white border-gray-800">
            <DialogHeader>
              <DialogTitle>Connect your wallet</DialogTitle>
              <DialogDescription className="text-gray-400">
                Connect your wallet to access Diamondz DEX
              </DialogDescription>
            </DialogHeader>
            <div className="grid gap-4 py-4">
              <Button onClick={handleConnectWallet} className="w-full justify-start bg-gray-800 hover:bg-gray-700">
                <img src="/placeholder.svg?height=24&width=24" alt="MetaMask" className="mr-2 h-6 w-6" />
                MetaMask
              </Button>
              <Button onClick={handleConnectWallet} className="w-full justify-start bg-gray-800 hover:bg-gray-700">
                <img src="/placeholder.svg?height=24&width=24" alt="WalletConnect" className="mr-2 h-6 w-6" />
                WalletConnect
              </Button>
              <Button onClick={handleConnectWallet} className="w-full justify-start bg-gray-800 hover:bg-gray-700">
                <img src="/placeholder.svg?height=24&width=24" alt="Coinbase Wallet" className="mr-2 h-6 w-6" />
                Coinbase Wallet
              </Button>
            </div>
          </DialogContent>
        </Dialog>
      )}

      {/* Wrong Network Dialog */}
      <AlertDialog open={isWrongNetworkDialogOpen} onOpenChange={setIsWrongNetworkDialogOpen}>
        <AlertDialogContent className="bg-gray-900 text-white border-gray-800">
          <AlertDialogHeader>
            <AlertDialogTitle className="flex items-center gap-2">
              <AlertTriangle className="h-5 w-5 text-yellow-500" />
              Wrong Network
            </AlertDialogTitle>
            <AlertDialogDescription className="text-gray-400">
              Please switch to the {chainConfig.chainName} network to use Diamondz DEX.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel className="bg-gray-800 text-white hover:bg-gray-700">Cancel</AlertDialogCancel>
            <AlertDialogAction
              id="switch-network-button"
              onClick={handleSwitchNetwork}
              className="bg-gradient-to-r from-purple-500 to-pink-600 hover:from-purple-600 hover:to-pink-700"
            >
              Switch Network
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}
