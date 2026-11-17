#!/usr/bin/env node
/*
 * Prepare (and optionally broadcast) the three transactions that make the chain-724 wLXON wrapper
 * actually collateralised, with the unbacked-mint path closed first.
 *
 *   node scripts/prepare-724-wrapper-backing.js                     # plan only, no key, no writes
 *   AMOUNT_LXON=50000 node scripts/prepare-724-wrapper-backing.js    # different deposit
 *   DEPLOYER_PRIVATE_KEY=0x… node scripts/prepare-724-wrapper-backing.js --broadcast \
 *     --i-verified-preconditions                                    # real writes
 *
 * Why this order, and why it is three transactions:
 *
 * 1. revokeRole(MINTER_ROLE, deployer) on the wrapper. mint()/burnFrom() are the only paths that
 *    create wLXON WITHOUT custody, and the deployer is today the only holder of MINTER_ROLE among every
 *    address this project tracks (measured 2026-10-21: hasRole true for the deployer, false for the
 *    token, both bridges, both staking contracts, the timelock, the v1 wrapper, the leaked Polygon
 *    account and the wrapper itself). Revoking while totalSupply() is 0 costs nothing and cannot strand
 *    anything. Note the limit: this ABI has no getRoleMember/getRoleMemberCount (OZ v5 AccessControl
 *    without enumerably-access), so "nobody else holds it" is only provable per-address. DEFAULT_ADMIN is
 *    deliberately left with the deployer so a future bridge-custody design can re-grant; if you want the
 *    wrapper frozen forever instead, renounce DEFAULT_ADMIN as well — that is irreversible.
 * 2. approve(wrapper, amount) on LxonTokenEnhanced. wrap() calls safeTransferFrom, so without this it
 *    reverts with ERC20InsufficientAllowance. That revert is the proof that custody is real: the same
 *    call succeeds outright on the Polygon wrapper, which holds no collateral at all.
 * 3. wrap(amount) on the wrapper. Moves LXON in and mints 1:1 wLXON to the caller.
 *
 * Rollback is one call: unwrap(amount) returns the LXON. Nothing here is permanent except step 1's
 * re-grantability question.
 *
 * What this does NOT do: it does not create a price, a pool, or liquidity. Backing and market are
 * different facts and only the first one is ours to supply.
 */
const { ethers } = require("ethers");

const RPC = process.env.LXON_RPC_URL || "https://rpc.lxon.in";
const AMOUNT = ethers.parseUnits(process.env.AMOUNT_LXON || "10000", 18);
const KEY = process.env.DEPLOYER_PRIVATE_KEY;
const BROADCAST = process.argv.includes("--broadcast");
const VERIFIED = process.argv.includes("--i-verified-preconditions");

const TOKEN = "0x99801A78639975D448EEb2f8a807738DC8Df67Dc";          // LxonTokenEnhanced, 18 decimals
const WRAPPER = "0xC0CF6B0E6C5a0705F319BA5c629a6Bc7E82FEf00";        // LXONWrapper v2
const ADMIN = "0x0000000000000000000000000000000000000000000000000000000000000000";
const MINTER = "0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6";

const T = new ethers.Interface([
  "function revokeRole(bytes32,address)", "function grantRole(bytes32,address)",
  "function hasRole(bytes32,address) view returns (bool)",
  "function approve(address,uint256) returns (bool)", "function wrap(uint256)", "function unwrap(uint256)",
]);
const E = new ethers.Interface([
  "function totalSupply() view returns (uint256)", "function originalLXON() view returns (address)",
  "function balanceOf(address) view returns (uint256)", "function allowance(address,address) view returns (uint256)",
]);

if (BROADCAST && (!KEY || !VERIFIED)) {
  console.error("refusing to broadcast: needs DEPLOYER_PRIVATE_KEY in the environment AND --i-verified-preconditions.\nRun without --broadcast for the plan-only output.");
  process.exit(2);
}

(async () => {
  const p = new ethers.JsonRpcProvider(RPC, undefined, { staticNetwork: true });
  const net = await p.getNetwork();
  if (BigInt(net.chainId) !== 724n) throw new Error(`expected chain 724, RPC says ${net.chainId} — wrong endpoint, nothing runs`);
  const head = await p.getBlockNumber();
  const who = KEY ? new ethers.Wallet(KEY, p).address : (process.env.DEPLOYER || "0xFaE699d2848957c7c3bE67D8c90f0E456419cAdA");

  // The target is an explicit argument, never inferred from the interface: totalSupply and balanceOf exist
  // on BOTH contracts, so dispatching on which ABI was passed in would silently read the wrong one.
  const read = async (target, iface, sig, args = []) =>
    iface.decodeFunctionResult(sig, await p.call({ to: target, data: iface.encodeFunctionData(sig, args) }))[0];
  const code = (await p.getCode(WRAPPER)).length / 2 - 1;

  console.log(`head ${head}   chain ${net.chainId}   wrapper code ${code} bytes   signer ${who}`);
  console.log(`deposit      : ${ethers.formatUnits(AMOUNT, 18)} LXON  (raw ${AMOUNT})\npreconditions:`);

  let fails = 0;
  const want = (label, ok, detail) => { if (!ok) fails++; console.log(`  ${ok ? "ok  " : "FAIL"} ${label.padEnd(40)} ${detail}`); };
  want("wrapper has code", code > 0, `${code} bytes`);
  const underlying = await read(WRAPPER, E, "originalLXON()");
  want("originalLXON() is the live token", underlying.toLowerCase() === TOKEN.toLowerCase(), underlying);
  const supply = await read(WRAPPER, E, "totalSupply()");
  want("wrapper wLXON totalSupply() is 0", supply === 0n, `${ethers.formatUnits(supply, 18)} wLXON`);
  const custody = await read(WRAPPER, E, "balanceOf", [WRAPPER]);
  want("wrapper holds 0 LXON today", custody === 0n, `${ethers.formatUnits(custody, 18)} LXON`);
  const hasMint = await read(WRAPPER, T, "hasRole", [MINTER, who]);
  want("signer holds MINTER_ROLE", hasMint === true, `${hasMint} — if false, step 1 is a no-op and can be skipped`);
  const bal = await read(TOKEN, E, "balanceOf", [who]);
  want("signer covers the deposit", bal >= AMOUNT, `${ethers.formatUnits(bal, 18)} LXON held`);
  const nonce = await p.getTransactionCount(who, "latest");
  console.log(`  ---- signer nonce ${nonce}, gasPrice ${(await p.getFeeData()).gasPrice} wei, ${fails} precondition failure(s)`);

  const txs = [
    { why: "close the unbacked-mint path while supply is 0", to: WRAPPER, data: T.encodeFunctionData("revokeRole", [MINTER, who]) },
    { why: "wrap() pulls the underlying with transferFrom", to: TOKEN, data: T.encodeFunctionData("approve", [WRAPPER, AMOUNT]) },
    { why: "mint 1:1 wLXON against that custody", to: WRAPPER, data: T.encodeFunctionData("wrap", [AMOUNT]) },
  ];

  console.log(`\ntransactions, strictly in this order (nonces ${nonce}, ${nonce + 1}, ${nonce + 2}):`);
  for (let i = 0; i < txs.length; i++) {
    const t = txs[i];
    let est;
    try { est = (await p.estimateGas({ from: who, to: t.to, data: t.data })).toString(); }
    catch (e) {
      // tx 3 cannot be estimated against `latest` because its precondition (the approve) has not landed
      // yet. Reporting the revert is honest; reporting a number guessed from a different call is not.
      est = `not estimable yet: ${(e.shortMessage || e.message).slice(0, 58)}`;
    }
    console.log(`  ${i + 1}. ${t.why}`);
    console.log(`     to   ${t.to}`);
    console.log(`     data ${t.data}`);
    console.log(`     gas  ${est}`);
  }

  console.log("\nsigning commands — run one at a time and check the receipt before the next:");
  txs.forEach((t, i) => {
    console.log(`  # ${i + 1}`);
    console.log(`  cast send --rpc-url ${RPC} --private-key "$DEPLOYER_PRIVATE_KEY" ${t.to} ${t.data}`);
  });
  console.log(`\nrollback (no admin needed; the wLXON holder calls it):`);
  console.log(`  cast send --rpc-url ${RPC} --private-key "$DEPLOYER_PRIVATE_KEY" ${WRAPPER} ${T.encodeFunctionData("unwrap", [AMOUNT])}`);

  console.log("\nafter each lands, the assertions that matter:");
  console.log(`  1  hasRole(MINTER_ROLE, signer) raw ${await p.call({ to: WRAPPER, data: T.encodeFunctionData("hasRole", [MINTER, who]) })}  -> want …00`);
  console.log(`  2  wrapper wLXON totalSupply()      -> want ${ethers.formatUnits(AMOUNT, 18)}`);
  console.log(`  3  wrapper LXON balanceOf(wrapper)  -> want ${ethers.formatUnits(AMOUNT, 18)}, EQUAL to supply — equality is the whole point`);
  console.log(`     and allowance(signer, wrapper) back to 0, consumed by wrap()`);

  if (!BROADCAST) {
    console.log("\nmode: PLAN ONLY. Nothing was signed, nothing was sent.");
    if (fails) { console.log(`${fails} precondition(s) failed — resolve before signing.`); process.exitCode = 2; }
    return;
  }

  console.log("\n*** BROADCASTING ***");
  const w = new ethers.Wallet(KEY, p);
  let n = await p.getTransactionCount(w.address, "latest");
  for (let i = 0; i < txs.length; i++) {
    const r = await w.sendTransaction({ to: txs[i].to, data: txs[i].data, nonce: n++ });
    const rc = await r.wait();
    console.log(`  ${i + 1}. ${r.hash}  status ${rc.status}  gasUsed ${rc.gasUsed}  block ${rc.blockNumber}`);
    if (rc.status !== 1) throw new Error(`tx ${i + 1} reverted; stopping so the sequence is not left half-applied`);
  }
  const finalSupply = await read(WRAPPER, E, "totalSupply()");
  const finalCustody = await read(WRAPPER, E, "balanceOf", [WRAPPER]);
  const stillMinter = await read(WRAPPER, T, "hasRole", [MINTER, who]);
  console.log(`\nfinal: ${ethers.formatUnits(finalSupply, 18)} wLXON against ${ethers.formatUnits(finalCustody, 18)} LXON custody, MINTER_ROLE held by signer = ${stillMinter}`);
  console.log(finalSupply === finalCustody
    ? "BACKED: custody equals supply."
    : "MISMATCH: supply and custody differ — do not list or price this until that is understood.");
})().catch((e) => { console.error("FAILED:", e.shortMessage || e.message); process.exit(1); });
