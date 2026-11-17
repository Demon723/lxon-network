/**
 * Secondary attestor for satellite anchors.
 *
 * After verifying a honey-encrypted payload and its ML-DSA-65 signature,
 * the gateway also produces a MAYO signature over the honey commitment
 * and submits it to the SecondarySignature registry on-chain.
 *
 * Note: MAYO verifiers fail closed until WASM/Rust bindings are built.
 */
import { createHash } from 'crypto';

export interface SecondaryAttestation {
  commitment: string;   // hex
  scheme: 'MAYO-1';
  attestedAt: number;
}

export class SecondaryAttestor {
  private readonly rpcUrl: string;
  private readonly registryAddress: string;
  private readonly attestorKey: string;
  private readonly mayoAvailable: boolean;

  constructor(opts: { rpcUrl: string; registryAddress: string; attestorKey: string }) {
    this.rpcUrl = opts.rpcUrl;
    this.registryAddress = opts.registryAddress;
    this.attestorKey = opts.attestorKey;
    this.mayoAvailable = false; // Disabled until WASM/Rust bindings are built
  }

  /**
   * Compute the commitment for a honey-wrapped payload.
   * Mirrors SecondarySignature.computeCommitment.
   */
  computeCommitment(message: Uint8Array, publicKey: Uint8Array, signature: Uint8Array): string {
    const h = createHash('sha256');
    h.update(message);
    h.update(publicKey);
    h.update(signature);
    return '0x' + h.digest('hex');
  }

  /**
   * Verify a MAYO signature (used when the satellite sends one).
   * Currently fails closed until WASM/Rust bindings are built.
   */
  async verify(publicKey: Uint8Array, message: Uint8Array, signature: Uint8Array): Promise<boolean> {
    if (!this.mayoAvailable) {
      console.warn('MAYO verification not available - WASM/Rust bindings required');
      return false;
    }
    // TODO: Implement when MAYO verifiers are available
    return false;
  }

  /**
   * Submit an attestation to the on-chain registry.
   */
  async attest(commitment: string, scheme: 'MAYO-1' = 'MAYO-1'): Promise<string> {
    // In production: sign with attestorKey and send to SecondarySignature.attest
    const body = {
      jsonrpc: '2.0', id: 1,
      method: 'eth_sendTransaction',
      params: [{
        from: this.attestorKey,
        to: this.registryAddress,
        data: encodeAttestCalldata(commitment, scheme),
      }],
    };
    const r = await fetch(this.rpcUrl, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });
    const j = await r.json() as { result?: string; error?: { message: string } };
    if (j.error) throw new Error(`attest failed: ${j.error.message}`);
    return j.result!;
  }
}

function encodeAttestCalldata(commitment: string, scheme: 'MAYO-1'): string {
  // selector for attest(bytes32,uint8) — computed from SecondarySignature contract
  // attest(bytes32,uint8) selector: need to compute after contract compilation
  // For now using a placeholder; will be updated with actual selector
  const sel = '00000000'; // placeholder - update with actual attest(bytes32,uint8) selector
  const schemeId = scheme === 'MAYO-1' ? 1 : 0; // MAYO_1 = 1 in SecondarySignature.Scheme enum
  const c = commitment.replace(/^0x/, '').padStart(64, '0');
  const s = schemeId.toString(16).padStart(64, '0');
  return '0x' + sel + c + s;
}
