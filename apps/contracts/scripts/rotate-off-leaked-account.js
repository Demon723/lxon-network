#!/usr/bin/env node
/**
 * Hand control of the four Polygon-mainnet contracts off the leaked account, then sweep its POL.
 *
 *   LEAKED_PRIVATE_KEY=0x… NEW_ADMIN=0x… node scripts/rotate-off-leaked-account.js            # dry run
 *   LEAKED_PRIVATE_KEY=0x… NEW_ADMIN=0x… node scripts/rotate-off-leaked-account.js --broadcast
 *
 * Read this before running it.
 *
 * WHO SIGNS. This script signs with the key that is already in your git remote. That is unavoidable —
 * only that key can hand over what it controls — and it means every step below is a race against
 * anyone else who has those bytes. Do it in one sitting, keep the terminal out of scrollback where you
 * can reread it, and do NOT put the key in your shell history: read it from a file descriptor or paste
 * it into a `read -s` prompt rather than typing it as a command argument.
 *
 * ORDER. Roles and ownership first, POL last, because the POL is the gas for everything above it. If
 * you sweep first you cannot finish the handover and the contracts stay controllable by a leaked key.
 *
 * WHAT CANNOT BE FIXED THIS WAY. If someone else has already used this key, every transaction below can
 * land after theirs and simply be irrelevant — so check polygonscan for unfamiliar transactions from the
 * account BEFORE you start, and if you find any, drain the POL first and treat the contracts as lost.
 * This script cannot tell you that; only an indexer can, and none was reachable from the session that
 * wrote it (Blockscout's Polygon API serves a Cloudflare challenge, Etherscan v2 needs a key).
 *
 * MEASURED, not assumed (2026-10-22, against https://polygon-bor-rpc.publicnode.com):
 *   0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6  "LXON Wrapped"/wLXON, 18 decimals, totalSupply 4.01e24.
 *       AccessControl. DEFAULT_ADMIN_ROLE is 0x00..00 and the leaked account HAS it. MINTER_ROLE is
 *       0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6 and it does NOT hold that one.
 *       So this needs grantRole + renounceRole, not transferOwnership.
 *   0x8E7BE3BC21F8eDa71d192ECa502705c10274a813  "LXON Test", 6 decimals, 1e12 supply. Ownable.
 *   0xf6B053bE2849B057FC182aC6De62867662d2A206  "LXON Settlement Asset", 6 decimals, 1e11 supply. Ownable.
 *   0x2e622d394CFFFA328FFad982c4BcE9d355B16143  a bridge. Exposes a bare admin() = the leaked account, no
 *       owner() and no ADMIN_ROLE. eth_call FROM the current admin proved that updateAdmin, setAdmin and
 *       changeAdmin ALL revert, so this contract may have no admin setter at all — in which case its admin
 *       is permanent and the only honest move is to abandon the contract, which the steps below do for you.
 *
 * Two of these are 6-decimal tokens; chain 724 settled on 18. Nothing here changes that, and none of the
 * four is backed by anything: wLXON's originalLXON() returns 0x0a26E5CC…, which has no code on Polygon and
 * was destroyed on 724 by the 2026-10-19 genesis reset. Handing over control is a hygiene act, not a
 * rescue of a functioning system.
 */

const { ethers } = require("ethers");

const RPC = process.env.POLYGON_RPC_URL || "https://polygon-bor-rpc.publicnode.com";
const KEY = process.env.LEAKED_PRIVATE_KEY || process.env.DEPLOYER_PRIVATE_KEY;
const NEW = process.env.NEW_ADMIN;
const BROADCAST = process.argv.includes("--broadcast");

const ADMIN_OF = "0x43410E73d2Ef4B2638BE10265e8BE3D2FDfFDc27"; // measured from chain, not assumed
const W_LXON = "0xB2CfeCb2aa1c53e8c4406146368222b6b3BbBbb6";
const TOKEN_TEST = "0x8E7BE3BC21F8eDa71d192ECa502705c10274a813";
const TOKEN_SETTLE = "0xf6B053bE2849B057FC182aC6De62867662d2A206";
const BRIDGE = "0x2e622d394CFFFA328FFad982c4BcE9d355B16143";
const DEFAULT_ADMIN_ROLE = "0x".padEnd(66, "0");
const MINTER_ROLE = "0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6";

const ERC = [
  "function hasRole(bytes32,address) view returns (bool)",
  "function grantRole(bytes32,address)",
  "function renounceRole(bytes32,address)",
  "function owner() view returns (address)",
  "function transferOwnership(address)",
  "function admin() view returns (address)",
  "function updateAdmin(address)",
  "function setAdmin(address)",
  "function changeAdmin(address)",
];

if (!KEY) { console.error("LEAKED_PRIVATE_KEY is not set. Pass it via the environment, not argv."); process.exit(1); }
if (!ethers.isAddress(NEW)) { console.error("NEW_ADMIN must be a valid address. Generate a fresh account first (e.g. `cast wallet new`)."); process.exit(1); }

(async () => {
  const provider = new ethers.JsonRpcProvider(RPC, 137);
  const wallet = new ethers.Wallet(KEY, provider);
  const abi = new ethers.Interface(ERC);
  const c = (addr, sig, args = []) => provider.call({ to: addr, data: abi.encodeFunctionData(sig, args) });

  console.log(`signer   : ${wallet.address}`);
  if (wallet.address.toLowerCase() !== ADMIN_OF.toLowerCase()) {
    console.log(`  NOTE: expected ${ADMIN_OF}. This is NOT the account that owns the four contracts,`);
    console.log("  so either the key you passed is a different one, or ownership already moved.");
    console.log("  Continuing would burn gas on reverts. Re-check the key and abort with Ctrl-C.");
  }
  console.log(`target   : ${NEW}`);
  console.log(`mode     : ${BROADCAST ? "*** BROADCASTING REAL TRANSACTIONS ON POLYGON MAINNET ***" : "dry run (callStatic only, nothing sent)"}`);
  const bal = await provider.getBalance(wallet.address);
  console.log(`gas funds: ${ethers.formatEther(bal)} POL\n`);
  if (bal < ethers.parseEther("0.01")) console.log("  WARNING: under 0.01 POL; the sweep at the end must leave gas for the earlier steps.\n");

  let nonce = await provider.getTransactionCount(wallet.address, "latest");
  const read = async (label, to, sig, args = []) => {
    // Decode, or the log prints a raw 32-byte word where a human expects an address or a bool.
    try {
      const raw = await provider.call({ to, data: abi.encodeFunctionData(sig, args) });
      const d = abi.decodeFunctionResult(sig, raw);
      return `${label}: ${d.length === 1 ? d[0] : JSON.stringify(d)}`;
    } catch (e) {
      return `${label}: unreadable (${(e.shortMessage || e.message).slice(0, 50)})`;
    }
  };
  const isTransport = (e) => /ETIMEDOUT|ECONNRESET|EAI_AGAIN|fetch (failed|window)|socket hang up|TIMED OUT|network/.test(
    `${e?.shortMessage || ""} ${e?.message || ""} ${e?.code || ""}`);
  const results = {};
  const send = async (id, label, to, sig, args) => {
    const data = abi.encodeFunctionData(sig, args);
    if (!BROADCAST) {
      try { await provider.call({ to, from: wallet.address, data }); console.log(`  ok     ${label}`); results[id] = true; }
      catch (e) {
        if (isTransport(e)) {
          // An RPC hiccup must never be reported as "the contract said no". Retrying is the honest move.
          console.log(`  RETRY  ${label} — transport error, not a revert: ${(e.shortMessage || e.message).slice(0, 60)}`);
          results[id] = undefined;
        } else { console.log(`  SKIP   ${label} — would revert (${(e.shortMessage || e.message).slice(0, 60)})`); results[id] = false; }
      }
      return;
    }
    try {
      const tx = await wallet.sendTransaction({ to, data, nonce: nonce++ });
      const r = await tx.wait();
      console.log(`  sent   ${label}  tx ${tx.hash}  gasUsed ${r.gasUsed}`);
      results[id] = true;
    } catch (e) { console.log(`  FAILED ${label}: ${(e.shortMessage || e.message).slice(0, 80)}`); results[id] = false; }
  };

  console.log("1) wLXON — AccessControl handover");
  console.log("    ", await read("admin role held by signer", W_LXON, "hasRole", [DEFAULT_ADMIN_ROLE, wallet.address]));
  await send("grantAdmin", "wLXON grantRole(DEFAULT_ADMIN_ROLE, NEW)", W_LXON, "grantRole", [DEFAULT_ADMIN_ROLE, NEW]);
  await send("grantMint", "wLXON grantRole(MINTER_ROLE, NEW)", W_LXON, "grantRole", [MINTER_ROLE, NEW]);
  // renounceRole does NOT require holding the role, so it succeeds even when the grant above reverted —
  // and running it then would strip the leaked key's admin without ever giving it to NEW, leaving wLXON
  // with no admin and no path to mint again. Only renounce on a confirmed grant. (For this particular
  // unbacked token a permanently ownerless mint is arguably the right end state; that is a decision, so
  // it is made here in the open rather than by an accident of ordering.)
  if (results.grantAdmin === true) {
    await send("renounce", "wLXON renounceRole(DEFAULT_ADMIN_ROLE, signer)", W_LXON, "renounceRole", [DEFAULT_ADMIN_ROLE, wallet.address]);
  } else {
    console.log(`  SKIP   renounce — the grant did not succeed. Renouncing anyway would orphan the role`);
    console.log("         (no admin left anywhere, no future mint). If that is what you want, do it on");
    console.log("         purpose: first find out WHY the grant failed, then renounce deliberately.");
  }

  console.log("\n2) the two Ownable tokens");
  for (const [name, addr] of [["LXON Test", TOKEN_TEST], ["LXON Settlement Asset", TOKEN_SETTLE]]) {
    console.log("    ", await read("owner today", addr, "owner"));
    await send(`own-${addr.slice(0, 6)}`, `${name} transferOwnership(NEW)`, addr, "transferOwnership", [NEW]);
  }

  console.log("\n3) the bridge — no known setter; try each candidate and report");
  console.log("    ", await read("admin today", BRIDGE, "admin"));
  for (const sig of ["updateAdmin(address)", "setAdmin(address)", "changeAdmin(address)"]) {
    await send(`bridge-${sig.split("(")[0]}`, `bridge ${sig}`, BRIDGE, sig.split("(")[0], [NEW]);
  }
  console.log("     If all three skipped, this contract's admin is permanent: abandon it and never wire");
  console.log("     anything real to 0x2e622d39….");

  console.log("\n4) sweep the POL (do this last — it is the gas for everything above)");
  const gasPrice = await provider.getFeeData().then((f) => f.gasPrice ?? f.maxFeePerGas);
  const est = gasPrice * 21000n;
  const value = bal - est - ethers.parseEther("0.0005");
  if (value > 0n) {
    if (!BROADCAST) console.log(`  ok     sweep ${ethers.formatEther(value)} POL to ${NEW} (dry run)`);
    else {
      const tx = await wallet.sendTransaction({ to: NEW, value, gasLimit: 21000n, gasPrice, nonce: nonce++ });
      console.log(`  sent   sweep ${ethers.formatEther(value)} POL  tx ${tx.hash}`);
      await tx.wait();
    }
  } else console.log("  SKIP   sweep — balance too small after gas");

  console.log("\nDone. Then: confirm on polygonscan that the NEW key owns what you expected, set the new key");
  console.log("wherever the app reads DEPLOYER_PRIVATE_KEY, and treat the old bytes as public. Anything");
  console.log("that ever used the old key is still in the repo's git history.");
})().catch((e) => { console.error("FAILED:", e.shortMessage || e.message); process.exit(1); });
