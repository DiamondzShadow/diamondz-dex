export const chainConfig = {
  chainId: 55951,
  chainName: "Diamondz Chain",
  nativeCurrency: {
    name: "Diamondz",
    symbol: "DMDZ",
    decimals: 18,
  },
  rpcUrls: ["https://rpc-tdiamondz-chain-ilxp72z9o0.t.conduit.xyz"],
  blockExplorerUrls: ["https://explorer-tdiamondz-chain-ilxp72z9o0.t.conduit.xyz"],
}

export const contractAddresses = {
  diamondRouter: "0x966F30b7F591B3cd41EF4861ACbF2b8E1aAf6a51",
  diamondFactory: "0xcB5b856284E929d54e56CB31c3038F21c778C062",
  diamondToken: "0x0e5BDba7B52f7ed1245DaCC9E1105792856ca3df",
  WETH: "0x22829634ca3aed54cf4Fc0343602291872C542a1",
}

export async function addNetworkToMetaMask() {
  if (typeof window !== "undefined" && window.ethereum) {
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
    } catch (error) {
      console.error("Error adding network to MetaMask:", error)
      return false
    }
  }
  return false
}
