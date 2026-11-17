// CREATE-address derivation for the Phase 2 gate review, and its own validation.
//
// address = keccak256(rlp([sender, nonce]))[12:]
//   rlp(sender) = 0x94 ++ 20 bytes      <-- a first attempt dropped this 0x94 and produced 802 wrong hashes
//   rlp(nonce)  = 0x80 for 0, else (0x80+len) ++ minimal big-endian bytes
//   rlp(list)   = (0xc0 + length-of-payload-in-bytes) ++ payload
//
// VALIDATION, not self-reporting: the old chain 724's token / bridge / wLXON / XON / timelock were
// created by the sealer EOA, so at least four of these 12 dead addresses MUST be reproduced by some
// nonce. If nothing reproduces, the code below is broken and the collision answer is meaningless --
// that is printed loudly rather than quietly.
const { keccak_256 } = require("@noble/hashes/sha3");

const SENDER = "fae699d2848957c7c3be67d8c90f0e456419cada";
const DEAD = [
  ["LXON token",        "99801a78639975d448eeb2f8a807738dc8df67dc"],
  ["v4.1 bridge",       "9b15fee95995a15da2d64d8e2958f9792d5d6a25"],
  ["wLXON (724)",       "c0cf6b0e6c5a0705f319ba5c629a6bc7e82fef00"],
  ["XON native token",  "e801e058b4c9f77dd60980a80f7607a50afe1799"],
  ["724 timelock",      "2f2671b38c0291873a6fc5f9bf013a36137332d9"],
  ["role multisig",     "692d0047323034514686ef57edfc26dbba53f87b"],
  ["attester multisig", "8e5d97d117cada19c695cd529b79d8229637dfbd"],
  ["WETH9",             "cb742c31f0815648e13ff24d8131b89075ff32e2"],
  ["LXON/WETH pair",    "272a3ed4b91112005ade5b4161af1adc856ab3f4"],
  ["router",            "d969211d7efb154e86d41a80ff0fd3cc0eb70468"],
  ["wLXON/LXON pair",   "8e90675e054826f61745c0016b895cdc4f220ebc"],
  ["router #2",         "aa0e4bb075f108b34dc0e279a7747980c76b8d75"],
];
const deadSet = new Map(DEAD.map(([n, a]) => [a, n]));

function rlpBytes(hexStr) {
  const len = hexStr.length / 2;
  // A single byte whose VALUE is < 0x80 is its own encoding. Compare the byte value, not the ASCII
  // code of the hex character -- charCodeAt("8") === 56 wrongly made nonce 128 (0x80) look like a bare
  // byte, so 128 encoded as "80" instead of "8180" and collided with nonce 0's result.
  if (len === 1 && parseInt(hexStr, 16) < 0x80) return hexStr;
  const prefix = len < 56 ? (0x80 + len).toString(16).padStart(2, "0") : "b7" + len.toString(16).padStart(2, "0");
  return prefix + hexStr;
}
function rlpInt(n) {
  if (n === 0) return "80";
  let h = n.toString(16);
  if (h.length % 2) h = "0" + h;
  return rlpBytes(h);
}
function createAddress(sender, nonce) {
  const s = sender.toLowerCase().replace(/^0x/, "");
  const payload = rlpBytes(s) + rlpInt(nonce);          // 0x94++20B  then  rlp(nonce)
  const plen = payload.length / 2;
  const body = (0xc0 + plen).toString(16) + payload;
  const h = keccak_256(Uint8Array.from(Buffer.from(body, "hex")));
  return Buffer.from(h.slice(12)).toString("hex");
}

// --- sanity of the encoder before anything else ---
const probe = createAddress(SENDER, 0);
console.log("encoder shape check: create(sealer, 0) = 0x" + probe, probe.length === 40 ? "(40 hex, ok)" : "(BAD LENGTH)");

const found = [];
for (let nonce = 0; nonce <= 300; nonce++) {
  const a = createAddress(SENDER, nonce);
  if (deadSet.has(a)) found.push({ nonce, a, name: deadSet.get(a) });
}

// --- and the question option B is actually built on: does the PROPOSED new sender collide? ---
// This used to be prose ("a different sender cannot reproduce any (sender,nonce) pair of the old key"),
// which is true only as arithmetic about the old key. The real claim needs checking against the sender
// that will actually deploy, whose address is not known until it exists -- and if it ever reproduced a
// dead address, this script would print the reassuring sentence and exit 0 while saying so.
const CANDIDATE = (process.env.CANDIDATE || "").toLowerCase().replace(/^0x/, "");
const CANDIDATE_SLOTS = parseInt(process.env.CANDIDATE_SLOTS || "12", 10);
let candidateHits = [];
let candidateBad = false;
if (CANDIDATE) {
  if (!/^[0-9a-f]{40}$/.test(CANDIDATE)) {
    candidateBad = true;
    console.log("CANDIDATE= is not 40 hex -- refusing to answer the collision question with a typo");
  } else {
    for (let nonce = 0; nonce <= 300; nonce++) {
      const a = createAddress(CANDIDATE, nonce);
      if (deadSet.has(a)) candidateHits.push({ nonce, a, name: deadSet.get(a) });
    }
  }
}

console.log("\nreproduced by some nonce of the 724 sealer (this is the validation):");
if (found.length === 0) {
  console.log("  NONE -- the derivation is NOT validated; treat every answer below as unsupported");
} else {
  for (const f of found) console.log(`  nonce ${String(f.nonce).padStart(3)} -> 0x${f.a}   ${f.name}`);
}

const hitNonces = new Set(found.map(f => f.nonce));
console.log("\nwhat a redeploy from THIS key would produce next (its nonce is 0 today):");
for (let nonce = 0; nonce <= 11; nonce++) {
  const a = createAddress(SENDER, nonce);
  const flag = hitNonces.has(nonce) ? "  <== WOULD RE-CREATE A DEAD ADDRESS" : "";
  console.log(`  nonce ${String(nonce).padStart(2)} -> 0x${a}${flag}`);
}

if (CANDIDATE && !candidateBad) {
  console.log("\nthe candidate sender's first " + CANDIDATE_SLOTS + " creation slots (0x = predicted address):");
  for (let nonce = 0; nonce < CANDIDATE_SLOTS; nonce++) {
    const a = createAddress(CANDIDATE, nonce);
    const flag = deadSet.has(a) ? "  <== COLLIDES WITH A DEAD ADDRESS: " + deadSet.get(a) : "";
    // Column 0 on purpose: this line is parsed by machine (RehearsePhase2PreDeploys726.sh compares it against the
    // mined receipts). Pretty indentation turned a passing check into "no prediction found".
    console.log(`PREDICT ${String(nonce).padStart(3)} 0x${a}${flag}`);
  }
  console.log("CANDIDATE_COLLISIONS=" + candidateHits.length + " (of 301 nonces probed)");
  if (candidateHits.length) {
    console.log("  REFUSE: this sender would re-create addresses the repo has publicly retired --");
    console.log("  the withdrawn token lists and the 66 annotated docs would become false statements.");
    for (const h of candidateHits) console.log(`    nonce ${h.nonce} -> 0x${h.a}  ${h.name}`);
  }
} else if (!CANDIDATE) {
  console.log("\nno CANDIDATE= given, so the fresh-sender collision question is UNANSWERED here, not answered yes.");
}

// 0 = derivation validated and the candidate (if any) is clear; 2 = the encoder itself is untrustworthy;
// 3 = the candidate collides or was malformed. Callers must not read 3 as "fine".
if (found.length === 0) process.exit(2);
if (candidateBad) process.exit(3);
if (candidateHits.length) process.exit(3);
process.exit(0);

// Run it from anywhere with:
//   NODE_PATH=<repo>/apps/frontend/node_modules node <this file>
// (that is the only node_modules root here carrying @noble/hashes.)
// Exit 0 = the derivation reproduced known 724 addresses and is therefore trustworthy; exit 2 = it
// reproduced none, which means the encoder is broken and its collision answer must be ignored.
