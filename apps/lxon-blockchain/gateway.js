#!/usr/bin/env node
const http = require('http');

const CHAIN_ID = parseInt(process.env.CHAIN_ID || '724', 10);
const GATEWAY_PORT = parseInt(process.env.GATEWAY_PORT || '8545', 10);
const UPSTREAM = process.env.UPSTREAM || 'http://127.0.0.1:8546';

const WEI = 10n ** 18n;
const GAS_BASE = 0x3b9aca00;          // 1 gwei
const GAS_PRIORITY = 0x3b9aca00;      // 1 gwei
const ESTIMATE_GAS = 0x5208;          // 21000

function upstreamRequest(method, params) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify({ jsonrpc: '2.0', id: 1, method, params: params || [] });
    const url = new URL(UPSTREAM);
    const req = http.request(
      { host: url.hostname, port: url.port || 80, path: '/', method: 'POST', headers: { 'Content-Type': 'application/json' } },
      (res) => {
        let body = '';
        res.on('data', (c) => (body += c));
        res.on('end', () => {
          try {
            resolve(JSON.parse(body));
          } catch (e) {
            resolve({ jsonrpc: '2.0', id: 1, error: { code: -32603, message: 'Bad upstream response' } });
          }
        });
      }
    );
    req.on('error', reject);
    req.setTimeout(5000, () => {
      req.destroy(new Error('Upstream timeout'));
    });
    req.end(payload);
  });
}

async function getUpstreamHealth() {
  return new Promise((resolve) => {
    const url = new URL(UPSTREAM);
    const req = http.get({ host: url.hostname, port: url.port || 80, path: '/health', timeout: 3000 }, (res) => {
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => {
        try {
          resolve(JSON.parse(body));
        } catch (e) {
          resolve(null);
        }
      });
    });
    req.on('error', () => resolve(null));
  });
}

async function getBlockNumber() {
  const health = await getUpstreamHealth();
  if (health && health.blockNumber !== undefined) return parseInt(health.blockNumber, 10);
  const rpc = await upstreamRequest('lxon_blockNumber', []);
  if (rpc && rpc.result) return parseInt(rpc.result, 16);
  return 0;
}

async function upstreamResult(method, params, fallback) {
  try {
    const rpc = await upstreamRequest(method, params);
    if (rpc && rpc.result !== undefined) return rpc.result;
  } catch (e) { /* fall through */ }
  return fallback;
}

async function handle(method, params) {
  const address = params && params[0] ? String(params[0]) : '0x';
  switch (method) {
    case 'eth_chainId':
      return '0x' + CHAIN_ID.toString(16);
    case 'net_version':
      return String(CHAIN_ID);
    case 'web3_clientVersion':
      return 'LXON/v1.0.0/mainnet';
    case 'lxon_chainId':
      return '0x' + CHAIN_ID.toString(16);
    case 'eth_blockNumber':
    case 'lxon_blockNumber': {
      const height = await getBlockNumber();
      return '0x' + height.toString(16);
    }
    case 'eth_getBalance':
      return await upstreamResult('lxon_getBalance', [address], '0x0');
    case 'eth_getTransactionCount':
      return await upstreamResult('lxon_getTransactionCount', [address], '0x0');
    case 'eth_accounts':
      return [];
    case 'eth_gasPrice':
      return '0x' + GAS_BASE.toString(16);
    case 'eth_maxPriorityFeePerGas':
      return '0x' + GAS_PRIORITY.toString(16);
    case 'eth_feeHistory': {
      const count = params && params[0] !== undefined ? Number(params[0]) : 1;
      let newestTag = params && params[1] !== undefined ? params[1] : 'latest';
      let base = await getBlockNumber();
      if (typeof newestTag === 'string' && /^0x/.test(newestTag)) base = parseInt(newestTag, 16) + 1;
      const start = Math.max(1, base - count);
      const baseFees = [];
      const rewards = [];
      for (let i = start; i <= base; i++) {
        baseFees.push('0x' + GAS_BASE.toString(16));
        rewards.push(['0x' + GAS_PRIORITY.toString(16)]);
      }
      return {
        oldestBlock: '0x' + start.toString(16),
        baseFeePerGas: baseFees,
        gasUsedRatio: Array(count).fill(0),
        reward: rewards,
      };
    }
    case 'eth_estimateGas':
      return '0x' + ESTIMATE_GAS.toString(16);
    case 'eth_getCode':
      return '0x';
    case 'eth_call':
      return '0x';
    case 'eth_sendRawTransaction': {
      // The node executes LXON-native transactions. MetaMask/Coinbase Wallet
      // produce EVM-signed raw txs which the LXON consensus layer cannot run yet.
      // Failing truthfully here is safer for wallets than farming a hash that
      // will never produce a receipt.
      throw new Error(
        'EVM-style raw transaction (`eth_sendRawTransaction`) is not executable on LXON yet. ' +
        'Use the LXON SDK or the web wallet at https://www.lxon.in/apps/wallet/ .'
      );
    }
    case 'eth_getBlockByNumber':
    case 'eth_getBlockByHash': {
      const height = await getBlockNumber();
      const blockTag = params && params[0] !== undefined ? params[0] : 'latest';
      let number = height;
      if (blockTag === 'latest' || blockTag === 'pending') number = height;
      else if (/^0x/.test(String(blockTag))) number = parseInt(blockTag, 16);
      const ts = Math.floor(Date.now() / 1000);
      return {
        number: '0x' + number.toString(16),
        hash: '0x' + Buffer.from('lxon-block-' + number).toString('hex').padStart(64, '0'),
        parentHash: '0x' + Buffer.from('lxon-block-' + Math.max(0, number - 1)).toString('hex').padStart(64, '0'),
        timestamp: '0x' + ts.toString(16),
        gasLimit: '0x1c9c380',
        gasUsed: '0x0',
        miner: '0x' + '0'.repeat(40),
        difficulty: '0x0',
        totalDifficulty: '0x0',
        size: '0x0',
        transactions: [],
        uncles: [],
        baseFeePerGas: '0x' + GAS_BASE.toString(16),
        extraData: '0x',
        mixHash: '0x' + '0'.repeat(64),
        nonce: '0x' + '0'.repeat(16),
      };
    }
    case 'eth_getTransactionByHash':
    case 'eth_getTransactionReceipt':
      return null;
    case 'lxon_getMetrics':
    case 'lxon_getPrices':
    case 'lxon_getPeers': {
      const rpc = await upstreamRequest(method, params);
      if (rpc && rpc.error) throw new Error(rpc.error.message || 'Upstream error');
      return rpc && rpc.result !== undefined ? rpc.result : null;
    }
    case 'lxon_sendTransaction':
      throw new Error(
        'LXON-native transaction execution is not available yet. Use the web wallet at https://www.lxon.in/apps/wallet/ .'
      );
    default:
      const passthrough = await upstreamRequest(method, params);
      if (passthrough && passthrough.error) throw new Error(passthrough.error.message);
      return passthrough && passthrough.result !== undefined ? passthrough.result : null;
  }
}

const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const url = req.url || '/';

  if (req.method === 'GET' && (url === '/health' || url === '/healthz')) {
    const health = await getUpstreamHealth();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(health || { status: 'UNHEALTHY', chainId: CHAIN_ID }));
    return;
  }

  if (req.method === 'GET' && url === '/metrics') {
    const metrics = await upstreamRequest('lxon_getMetrics', []);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(metrics && metrics.result ? metrics.result : {}));
    return;
  }

  if (req.method === 'POST' && (url === '/' || url === '/rpc')) {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', async () => {
      try {
        const parsed = JSON.parse(body);
        const requests = Array.isArray(parsed) ? parsed : [parsed];
        const responses = [];
        for (const rpcReq of requests) {
          try {
            const result = await handle(rpcReq.method, rpcReq.params || []);
            responses.push({ jsonrpc: '2.0', id: rpcReq.id ?? 1, result });
          } catch (err) {
            responses.push({ jsonrpc: '2.0', id: rpcReq.id ?? 1, error: { code: -32601, message: err.message || 'Method not available' } });
          }
        }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(Array.isArray(parsed) ? responses : responses[0]));
      } catch (err) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } }));
      }
    });
    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found' }));
});

server.listen(GATEWAY_PORT, '0.0.0.0', () => {
  console.log('LXON RPC gateway listening on port ' + GATEWAY_PORT + ' (upstream: ' + UPSTREAM + ')');
});