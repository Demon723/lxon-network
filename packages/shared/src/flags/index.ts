export type FlagName =
  | 'pq_hybrid_signing'
  | 'block_stm_parallel'
  | 'narwhal_mempool'
  | 'helios_nfc_payments'
  | 'pbs_enabled'
  | 'honey_lsp_frames'
  | 'honey_telemetry'
  | 'honey_pos_storage'
  | 'honey_orbit_market'
  | 'honey_gateway_uplink'
  // Secondary PQ signature flags
  | 'secondary_sig_enabled'
  | 'secondary_vault_large'
  | 'secondary_satellite_attest'
  | 'secondary_backend_routes';

const defaults: Record<FlagName, boolean> = {
  pq_hybrid_signing: true,
  block_stm_parallel: true,
  narwhal_mempool: true,
  helios_nfc_payments: false,
  pbs_enabled: false,
  honey_lsp_frames: false,
  honey_telemetry: false,
  honey_pos_storage: true,
  honey_orbit_market: false,
  honey_gateway_uplink: false,
  secondary_sig_enabled: false,       // off by default — needs audit
  secondary_vault_large: false,
  secondary_satellite_attest: false,
  secondary_backend_routes: false,
};

const overrides = new Map<FlagName, boolean>();

export function isEnabled(n: FlagName): boolean {
  if (overrides.has(n)) return overrides.get(n)!;
  const e = process.env[`LXON_FLAG_${n.toUpperCase()}`];
  if (e === '1' || e === 'true') return true;
  if (e === '0' || e === 'false') return false;
  return defaults[n];
}

export function setFlag(n: FlagName, v: boolean) { overrides.set(n, v); }
export function resetFlags() { overrides.clear(); }
export function listFlags(): Record<FlagName, boolean> {
  return Object.keys(defaults).reduce((a, k) => {
    a[k as FlagName] = isEnabled(k as FlagName);
    return a;
  }, {} as Record<FlagName, boolean>);
}
