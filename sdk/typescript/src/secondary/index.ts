/**
 * Secondary PQ signature helpers for the SDK.
 */
export interface SecondaryCommitment {
  commitment: string;
  scheme: 'MAYO-1' | 'MAYO-2' | 'MAYO-3' | 'MAYO-5';
}

export async function computeCommitment(
  message: Uint8Array,
  publicKey: Uint8Array,
  signature: Uint8Array,
): Promise<string> {
  const { createHash } = await import('crypto');
  const h = createHash('sha256');
  h.update(Buffer.from(message));
  h.update(Buffer.from(publicKey));
  h.update(Buffer.from(signature));
  return '0x' + h.digest('hex');
}
