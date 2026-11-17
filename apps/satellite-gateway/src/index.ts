#!/usr/bin/env node
import express from 'express';
import pino from 'pino';
import { randomBytes } from 'crypto';
import { BlockstreamAdapter } from './adapters/blockstream';
import { SpacecoinAdapter } from './adapters/spacecoin';
import { SealcoinAdapter } from './adapters/sealcoin';
import { AstrocastAdapter } from './adapters/astrocast-adapter';
import { Router } from './services/routing';
import { Billing } from './services/billing';
import { makeRouter } from './api/router';
import { UplinkHoney } from './honey/uplink-honey';
import { marketHoneyRoutes } from './honey/market-routes';
import { SecondaryAttestor } from './honey/secondary-attestor';

const log = pino({ level: process.env.LOG_LEVEL ?? 'info', base: { service: 'satellite-gateway' } });
const PORT = Number(process.env.PORT ?? 4100);

const adapters = [];
if (process.env.BLOCKSTREAM_API_BASE) {
  adapters.push(new BlockstreamAdapter({ apiBase: process.env.BLOCKSTREAM_API_BASE, apiKey: process.env.BLOCKSTREAM_API_KEY }));
}
if (process.env.SPACECOIN_API_BASE) {
  adapters.push(new SpacecoinAdapter({ apiBase: process.env.SPACECOIN_API_BASE, apiKey: process.env.SPACECOIN_API_KEY!, networkId: Number(process.env.SPACECOIN_NETWORK_ID ?? 0) }));
}
if (process.env.SEALCOIN_API_BASE) {
  adapters.push(new SealcoinAdapter({ apiBase: process.env.SEALCOIN_API_BASE, apiKey: process.env.SEALCOIN_API_KEY! }));
}
if (process.env.ASTROCAST_API_BASE) {
  adapters.push(new AstrocastAdapter({ apiBase: process.env.ASTROCAST_API_BASE, apiKey: process.env.ASTROCAST_API_KEY! }));
}

const honeyKey = process.env.HONEY_SESSION_KEY
  ? Buffer.from(process.env.HONEY_SESSION_KEY, 'hex')
  : randomBytes(32);
const uplinkHoney = new UplinkHoney(honeyKey);

const router = new Router(adapters, { mode: (process.env.ROUTING_MODE as 'cheapest' | 'fastest' | 'round-robin') ?? 'cheapest' });
const billing = new Billing();

// Optional secondary attestor
let secondaryAttestor: SecondaryAttestor | null = null;
if (process.env.SECONDARY_REGISTRY && process.env.SECONDARY_ATTESTOR_KEY && process.env.RPC_URL) {
  secondaryAttestor = new SecondaryAttestor({
    rpcUrl: process.env.RPC_URL,
    registryAddress: process.env.SECONDARY_REGISTRY,
    attestorKey: process.env.SECONDARY_ATTESTOR_KEY,
  });
  log.info('secondary attestor enabled');
}

const app = express();
app.use(express.json({ limit: '1mb' }));
app.use('/api/v1/satellite', makeRouter(router, billing));
app.use('/api/v1/market-honey', marketHoneyRoutes());

app.post('/api/v1/satellite/uplink-honey', async (req, res) => {
  try {
    const { satelliteId, commandBase64, priority = 'normal', secondarySignatureBase64, secondaryPubKeyBase64 } = req.body;
    if (!satelliteId || !commandBase64) return res.status(400).json({ error: 'missing fields' });

    const command = Buffer.from(commandBase64, 'base64');
    const wrapped = uplinkHoney.wrap(new Uint8Array(command));

    // Optional: verify + attest secondary signature
    let commitment: string | null = null;
    if (secondaryAttestor && secondarySignatureBase64 && secondaryPubKeyBase64) {
      const sig = Buffer.from(secondarySignatureBase64, 'base64');
      const pk = Buffer.from(secondaryPubKeyBase64, 'base64');
      const msg = wrapped.payload;
      const ok = await secondaryAttestor.verify(new Uint8Array(pk), msg, new Uint8Array(sig));
      if (ok) {
        commitment = secondaryAttestor.computeCommitment(msg, new Uint8Array(pk), new Uint8Array(sig));
        await secondaryAttestor.attest(commitment).catch((e) => log.warn({ e }, 'attest failed'));
      }
    }

    const { result, via } = await router.uplink({
      satelliteId,
      data: wrapped.payload,
      priority,
    });

    res.json({
      providerRef: result.providerRef,
      keyFingerprint: wrapped.keyFingerprint,
      secondaryCommitment: commitment,
      via,
      acceptedAtMs: result.acceptedAtMs,
    });
  } catch (err) {
    log.error({ err }, 'honey uplink failed');
    res.status(502).json({ error: String((err as Error).message) });
  }
});

const server = app.listen(PORT, () => log.info({ port: PORT, adapters: adapters.map((a) => a.name) }, 'satellite gateway listening'));

for (const sig of ['SIGTERM', 'SIGINT'] as const) {
  process.on(sig, () => {
    log.info({ sig }, 'shutdown');
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 10_000).unref();
  });
}
