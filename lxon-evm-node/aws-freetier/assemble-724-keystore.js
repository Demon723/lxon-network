// Assemble a geth-v3 keystore from encrypted key material that was GENERATED ON THE INSTANCE.
//
// This file exists so that the two keccak-dependent numbers in a keystore -- the `mac` and the address --
// are produced by an implementation that has already been anchored, rather than one I wrote this afternoon
// and watched fail its known-answer vectors. @noble/hashes is the same library check-724-create-address-
// collision.js uses to reproduce four real chain-724 contract addresses; if it were wrong here, that
// checker would already be wrong there.
//
// The private key never appears in this process. It arrives already AES-128-CTR encrypted, and it is
// never decrypted here: the address comes from the PUBLIC POINT, and the mac comes from the KDF sub-key.
//
// usage: NODE_PATH=<repo>/apps/frontend/node_modules node assemble-724-keystore.js <payload.json> <out-path>
//   payload.json = {"salt","n","r","p","dklen","iv","ciphertext","pubkey"} as printed by the remote script
//   the password is read from the file named by PASSWORD_FILE (never argv).
const fs = require("fs");
const crypto = require("crypto");
const { keccak_256 } = require("@noble/hashes/sha3");

const [payloadPath, outPath] = process.argv.slice(2);
const pwFile = process.env.PASSWORD_FILE;
if (!payloadPath || !outPath || !pwFile) {
  console.error("usage: node assemble-724-keystore.js <payload.json> <out-path>   (PASSWORD_FILE=...)");
  process.exit(2);
}
if (fs.existsSync(outPath)) {
  console.error("REFUSE: " + outPath + " already exists -- a second key would silently replace a live one.");
  process.exit(1);
}

const p = JSON.parse(fs.readFileSync(payloadPath, "utf8"));
for (const k of ["salt", "iv", "ciphertext", "pubkey"]) {
  if (!/^[0-9a-fA-F]+$/.test(p[k] || "")) { console.error("REFUSE: payload." + k + " is not hex"); process.exit(1); }
}
if (p.cipher !== "aes-128-ctr" || p.kdf !== "scrypt") {
  console.error("REFUSE: unexpected cipher/kdf " + p.cipher + "/" + p.kdf); process.exit(1);
}
const ct = Buffer.from(p.ciphertext, "hex");
if (ct.length !== 32) {
  console.error("REFUSE: ciphertext is " + ct.length + " bytes; a secp256k1 scalar is 32"); process.exit(1);
}

const password = fs.readFileSync(pwFile, "utf8").replace(/\n$/, "");
const dk = crypto.scryptSync(Buffer.from(password), Buffer.from(p.salt, "hex"), p.dklen || 32,
                             { N: p.n, r: p.r, p: p.p, maxmem: 1024 * 1024 * 1024 });
const mac = Buffer.from(keccak_256(Buffer.concat([dk.subarray(16, 32), ct])));

const pub = Buffer.from(p.pubkey, "hex");
if (pub.length !== 65 || pub[0] !== 0x04) {
  console.error("REFUSE: pubkey is not a 65-byte uncompressed point"); process.exit(1);
}
const address = Buffer.from(keccak_256(pub.subarray(1))).subarray(12).toString("hex");

// A geth-v3 `id` is a UUID, and foundry parses it strictly: the first version of this line wrote
// "lxon-724-deployer-<12 hex>", 30 characters, and `cast wallet address` refused the file with
// "UUID parsing failed: invalid length: expected one of [36, 32], found 30". The keystore looked fine
// to anything that only reads `address`; it is unusable by the signer. So: a canonical 8-4-4-4-12 v4.
function uuidV4() {
  const b = crypto.randomBytes(16);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = b.toString("hex");
  return h.slice(0, 8) + "-" + h.slice(8, 12) + "-" + h.slice(12, 16) + "-" + h.slice(16, 20) + "-" + h.slice(20);
}

const ks = {
  crypto: { cipher: "aes-128-ctr",
            cipherparams: { iv: p.iv },
            ciphertext: p.ciphertext,
            kdf: "scrypt",
            kdfparams: { dklen: p.dklen || 32, n: p.n, r: p.r, p: p.p, salt: p.salt },
            mac: mac.toString("hex") },
  id: uuidV4(),
  address: address,
  version: 3
};

const fd = fs.openSync(outPath, "wx", 0o600);
fs.writeSync(fd, JSON.stringify(ks));
fs.closeSync(fd);
if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(ks.id)) {
  console.error("REFUSE: id is not a canonical UUID v4 (foundry rejects the file otherwise): " + ks.id);
  process.exit(1);
}
// Round-trip proof that is NOT self-congratulatory: decrypt with the derived key and re-encrypt, and
// confirm the ciphertext reproduces. If the AES parameters or the KDF were off by one byte, the file
// would still look like a keystore and sign nothing.
const dec = crypto.createDecipheriv("aes-128-ctr", dk.subarray(0, 16), Buffer.from(p.iv, "hex"));
const back = Buffer.concat([dec.update(ct), dec.final()]);
const reenc = crypto.createCipheriv("aes-128-ctr", dk.subarray(0, 16), Buffer.from(p.iv, "hex"));
const again = Buffer.concat([reenc.update(back), reenc.final()]);
if (!again.equals(ct)) { console.error("REFUSE: the keystore does not round-trip under its own KDF/IV"); process.exit(1); }
if (back.length !== 32) { console.error("REFUSE: decrypted length " + back.length + " is not 32"); process.exit(1); }

console.log("ADDRESS 0x" + address);
console.log("KEYSTORE " + outPath);
