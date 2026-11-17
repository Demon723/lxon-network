import express from 'express';
import cors from 'cors';
import { ethers } from 'ethers';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = process.env.PORT || 3002;
const RPC_URL = process.env.RPC_URL || 'http://localhost:8545';

const CONTRACTS = {
  LXON_TOKEN: process.env.LXON_TOKEN || '0x5FC8d32690cc91D4c39d9d3abcBD16989F875707',
  SWAP: process.env.SWAP || '0x0165878A594ca255338adfa4d48449f69242Eb8F',
  CHAIN_ID: parseInt(process.env.CHAIN_ID || '31337')
};

const LXON_ABI = [
  'function balanceOf(address owner) view returns (uint256)',
  'function approve(address spender, uint256 amount) returns (bool)',
  'function transfer(address to, uint256 amount) returns (bool)',
  'function name() view returns (string)',
  'function symbol() view returns (string)',
  'function decimals() view returns (uint8)',
  'function totalSupply() view returns (uint256)'
];

const SWAP_ABI = [
  'function getReserves() view returns (uint256, uint256)',
  'function addLiquidity(uint256 tokenAmount) payable',
  'function swapNativeForToken() payable returns (uint256)',
  'function swapTokenForNative(uint256 tokenAmount) returns (uint256)'
];

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, '../')));

let provider: ethers.JsonRpcProvider;

try {
  provider = new ethers.JsonRpcProvider(RPC_URL);
} catch (error) {
  console.warn('Failed to initialize RPC provider:', error);
}

// Health check
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    rpc: RPC_URL,
    connected: provider !== undefined,
    contracts: CONTRACTS
  });
});

// Get pool reserves
app.get('/api/pool/reserves', async (req, res) => {
  try {
    const swap = new ethers.Contract(CONTRACTS.SWAP, SWAP_ABI, provider);
    const [reserveNative, reserveToken] = await swap.getReserves();
    res.json({
      reserveNative: reserveNative.toString(),
      reserveToken: reserveToken.toString(),
      pricePerToken: (Number(reserveNative) / Number(reserveToken)).toFixed(6)
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch pool reserves' });
  }
});

// Get token info
app.get('/api/token/info', async (req, res) => {
  try {
    const token = new ethers.Contract(CONTRACTS.LXON_TOKEN, LXON_ABI, provider);
    const [name, symbol, decimals, totalSupply] = await Promise.all([
      token.name(),
      token.symbol(),
      token.decimals(),
      token.totalSupply()
    ]);
    res.json({
      name,
      symbol,
      decimals: decimals.toString(),
      totalSupply: totalSupply.toString()
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch token info' });
  }
});

// Get account balances
app.get('/api/account/:address/balances', async (req, res) => {
  try {
    const { address } = req.params;
    const token = new ethers.Contract(CONTRACTS.LXON_TOKEN, LXON_ABI, provider);
    const [tokenBalance, nativeBalance] = await Promise.all([
      token.balanceOf(address),
      provider.getBalance(address)
    ]);
    res.json({
      tokenBalance: tokenBalance.toString(),
      nativeBalance: nativeBalance.toString()
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch balances' });
  }
});

// Get swap quote
app.get('/api/swap/quote', async (req, res) => {
  try {
    const { fromToken, amount } = req.query;
    const swap = new ethers.Contract(CONTRACTS.SWAP, SWAP_ABI, provider);
    const parsedAmount = ethers.parseEther(amount as string);

    let quote;
    if (fromToken === 'NATIVE') {
      quote = await swap.swapNativeForToken.staticCall({ value: parsedAmount });
    } else {
      quote = await swap.swapTokenForNative.staticCall(parsedAmount);
    }

    res.json({ quote: quote.toString() });
  } catch (error) {
    res.status(500).json({ error: 'Failed to get quote' });
  }
});

// Execute swap (requires signer - this is a placeholder)
app.post('/api/swap/execute', async (req, res) => {
  try {
    const { fromToken, amount, signature } = req.body;
    // This would require wallet integration on the client side
    // For now, return a simulated response
    res.json({
      success: true,
      message: 'Swap execution requires wallet signature. Please use the frontend with MetaMask.',
      fromToken,
      amount
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to execute swap' });
  }
});

// Get network info
app.get('/api/network', (req, res) => {
  res.json({
    chainId: CONTRACTS.CHAIN_ID,
    rpcUrl: RPC_URL,
    contracts: CONTRACTS
  });
});

app.listen(PORT, () => {
  console.log(`🔄 Contracts UI server running on http://localhost:${PORT}`);
  console.log(`📡 RPC connected to: ${RPC_URL}`);
  console.log(`📜 Serving swap.html and trading-interface.html`);
});
