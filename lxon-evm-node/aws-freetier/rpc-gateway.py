#!/usr/bin/env python3
"""
rpc.lxon.in read-only JSON-RPC gateway.

Besu exposes the whole `eth` namespace, which includes eth_sendRawTransaction; the security
group has never carried a rule for 8545, so that has never been reachable. Making the chain
publicly readable is the goal here; making it publicly *writable* is not, and a validator box
that accepts anyone's signed transaction is a spam and log-size hazard as well as a surprise.
So filtering happens here, on the parsed method name, rather than by namespace.

ALLOW-LIST, not deny-list: a new Besu method is unavailable until it is added deliberately.

Design notes that are load-bearing:
  * ThreadingHTTPServer with a real backlog. backlog=5 (the default on some paths) turns
    concurrent clients into TCP resets before any limit answers, and every connection is a
    thread, so shared state is guarded by a lock.
  * Batch JSON-RPC is filtered per element: a batch containing one blocked method is refused
    whole, so a blocked call cannot ride along inside a permitted batch.
  * Bodies are capped. An unbounded body on a 1 GiB box is a free denial of service.
  * The upstream is 127.0.0.1, where Besu listens; nothing binds a public interface.
"""
import json, os, socket, threading, time, http.client, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Overridable so the filter can be exercised against a tunneled real node before it is deployed.
UPSTREAM_HOST = os.environ.get("GWAY_UPSTREAM_HOST", "127.0.0.1")
UPSTREAM_PORT = int(os.environ.get("GWAY_UPSTREAM_PORT", "8545"))
LISTEN_HOST = os.environ.get("GWAY_LISTEN_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("GWAY_LISTEN_PORT", "9545"))
MAX_BODY = 1_000_000           # 1 MB; eth_getLogs requests are small
MAX_BATCH = 10

# Per-client budget, applied only to requests that would actually reach Besu. Concurrency alone
# is not a limit: a single client can hold all 16 slots indefinitely, and on a 1 GiB box whose one
# job is producing blocks for the whole chain that is a free stall. A token bucket with a burst
# ceiling lets a normal wallet or indexer burst without noticing, then flattens a flood.
RATE_BURST = float(os.environ.get("GWAY_RATE_BURST", "60"))      # allowed instant burst
RATE_REFILL = float(os.environ.get("GWAY_RATE_PER_SEC", "8"))    # tokens per second per client
RATE_TABLE_MAX = int(os.environ.get("GWAY_RATE_TABLE_MAX", "5000"))
RATE_IDLE_TTL = float(os.environ.get("GWAY_RATE_IDLE_TTL", "600"))

# eth_getLogs is the one allow-listed method whose cost is chosen by the *caller*: a range over the
# whole chain grows forever. Bounded by block span, resolved against the real head rather than
# assumed, so "latest" cannot be used to smuggle an unbounded read.
MAX_LOG_RANGE = int(os.environ.get("GWAY_MAX_LOG_RANGE", "5000"))
HEAD_TTL = float(os.environ.get("GWAY_HEAD_TTL", "5"))

ALLOWED = {
    "eth_chainId", "eth_blockNumber", "eth_getBalance", "eth_getBlockByNumber",
    "eth_getBlockByHash", "eth_getBlockTransactionCountByHash",
    "eth_getBlockTransactionCountByNumber", "eth_getTransactionByHash",
    "eth_getTransactionByBlockHashAndIndex", "eth_getTransactionByBlockNumberAndIndex",
    "eth_getTransactionReceipt", "eth_getTransactionCount", "eth_call", "eth_estimateGas",
    "eth_gasPrice", "eth_maxPriorityFeePerGas", "eth_feeHistory", "eth_getCode",
    "eth_getStorageAt", "eth_getLogs", "eth_syncing", "eth_mining", "eth_hashrate",
    "eth_accounts", "eth_getWork", "net_version", "net_listening", "net_peerCount",
    "web3_clientVersion", "rpc_modules",
}
# Named explicitly so the intent survives reading: these are reachable nowhere, ever.
NEVER = {
    "eth_sendRawTransaction", "eth_sign", "eth_signTransaction", "personal_sign",
    "eth_subscribe", "admin_addPeer", "admin_generateLog", "debug_traceBlock",
    "debug_traceTransaction", "txpool_content", "txpool_inspect", "qbft_proposeValidatorVote",
    "miner_start", "miner_setEtherbase",
}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "lxon-rpc-gateway/1"
    hits = 0
    blocked = 0
    rejected_busy = 0
    lock = threading.Lock()
    # A public front on a 1 GiB solo validator needs a ceiling on simultaneous upstream calls:
    # Besu's own JSON-RPC worker pool is finite, and eth_getLogs across a wide range is expensive.
    # Queuing behind a semaphore sheds load with a 429 instead of OOM-killing the sealer, which
    # would stop block production for the whole chain.
    permits = threading.Semaphore(int(os.environ.get("GWAY_MAX_CONCURRENT", "16")))

    # ip -> [tokens, last_seen_monotonic]. Guarded by the same lock as the counters: every
    # connection is its own thread, so an unlocked dict that is read, mutated and pruned from
    # several threads crashes on "dictionary changed size during iteration" at exactly the moment
    # a flood is happening.
    buckets = {}
    head_cache = [None, 0.0]   # [block number as int, monotonic time it was read]
    throttled = 0
    range_refused = 0

    def _client_ip(self):
        """Caddy proxies from loopback, so the socket peer is always 127.0.0.1 and useless for
        per-client accounting. Take the address Caddy appended in X-Forwarded-For -- the RIGHTMOST
        entry, because that is the one our own proxy wrote and a client cannot overwrite it.
        (A client controls the left-hand entries, so those are never trusted.)"""
        xff = self.headers.get("X-Forwarded-For", "")
        if xff:
            last = xff.split(",")[-1].strip()
            if last:
                return last
        return self.client_address[0]

    def _take(self, ip):
        """Consume one token for this client. Returns (allowed, retry_after_seconds)."""
        now = time.monotonic()
        with Handler.lock:
            b = Handler.buckets.get(ip)
            if b is None:
                if len(Handler.buckets) >= RATE_TABLE_MAX:
                    # Prune-by-age, under the lock: an unbounded table is its own DoS.
                    stale = [k for k, (_, t) in Handler.buckets.items() if now - t > RATE_IDLE_TTL]
                    for k in stale:
                        del Handler.buckets[k]
                    if len(Handler.buckets) >= RATE_TABLE_MAX:
                        Handler.buckets.clear()      # last resort; a fresh table is fail-open
                b = [RATE_BURST, now]
            tokens, last = b
            tokens = min(RATE_BURST, tokens + (now - last) * RATE_REFILL)
            if tokens >= 1.0:
                b[0], b[1] = tokens - 1.0, now
                Handler.buckets[ip] = b
                return True, 0.0
            b[0], b[1] = tokens, now
            Handler.buckets[ip] = b
            need = 1.0 - tokens
            return False, max(0.1, need / RATE_REFILL)

    def _too_busy(self):
        with Handler.lock:
            Handler.throttled += 1
        return self._send(429, {"jsonrpc": "2.0", "id": None, "error": {
            "code": -32005, "message": "read-only endpoint rate limit reached, retry shortly"}},
            retry_after=1)

    def log_message(self, fmt, *args):
        sys.stderr.write("  %s - %s\n" % (self.address_string(), fmt % args))

    def do_OPTIONS(self):
        """Answer the CORS preflight a browser sends BEFORE the real POST.

        Without this, BaseHTTPRequestHandler replies 501 and the browser never issues the request it
        was asked about -- so the landing page at https://www.lxon.in, reading https://rpc.lxon.in,
        would show "not read" for every figure while every curl probe said 200. Found on
        2026-11-03 by asking about the browser path instead of the command-line one.

        A preflight is not a read, so it costs no token and is never forwarded upstream.
        204 carries no body, so Content-Length is deliberately not sent."""
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Max-Age", "600")
        self.end_headers()

    def _send(self, status, payload, ctype="application/json", retry_after=None):
        body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        # Origin * because this endpoint is read-only by construction; there is no credential that
        # would make a wildcard meaningful, and the site that embeds it is a different hostname.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Max-Age", "600")
        if retry_after is not None:
            self.send_header("Retry-After", str(retry_after))
        self.end_headers()
        self.wfile.write(body)

    def _deny(self, method):
        with Handler.lock:
            Handler.blocked += 1
        return self._send(403, {"jsonrpc": "2.0", "id": None,
                                "error": {"code": -32601,
                                          "message": f"method {method} is not available on the public read-only endpoint"}})

    def _upstream_number(self, method):
        """One cheap upstream read, used only to bound a caller-chosen range. Returns int or None."""
        conn = http.client.HTTPConnection(UPSTREAM_HOST, UPSTREAM_PORT, timeout=5)
        try:
            body = json.dumps({"jsonrpc": "2.0", "id": 0, "method": method, "params": []}).encode()
            conn.request("POST", "/", body=body, headers={"Content-Type": "application/json"})
            j = json.loads(conn.getresponse().read())
            return int(j["result"], 16) if isinstance(j.get("result"), str) else None
        except Exception:
            return None
        finally:
            conn.close()

    def _head(self):
        """Head block number, cached for HEAD_TTL so a getLogs flood cannot turn the bound into a
        second query per request. None means Besu did not answer, and then the range cannot be
        proven small, so the caller is refused rather than handed an unbounded read."""
        now = time.monotonic()
        with Handler.lock:
            num, t = Handler.head_cache
            if num is not None and now - t < HEAD_TTL:
                return num
        n = self._upstream_number("eth_blockNumber")
        if n is not None:
            with Handler.lock:
                Handler.head_cache = [n, now]
        return n

    @staticmethod
    def _block_ref(v, head):
        """Resolve a JSON-RPC block tag/number to an int, or None if it cannot be resolved."""
        if v is None or v in ("latest", "pending", "safe", "finalized"):
            return head
        if v == "earliest":
            return 0
        try:
            if isinstance(v, int):
                return v
            s = str(v)
            return int(s, 16) if s.lower().startswith("0x") else int(s)
        except (ValueError, TypeError):
            return None

    def _range_too_wide(self, elem):
        """True when this is an eth_getLogs whose span provably exceeds MAX_LOG_RANGE.

        Note on absent tags: the spec defaults BOTH fromBlock and toBlock to `latest`, so
        params:[] is a one-block read and is correctly allowed. The dangerous shape is ONE tag
        present -- {"fromBlock":"0x0"} with no toBlock resolves to 0..head, which is the whole
        chain, and that is what this catches. Do not "tighten" the both-absent case; it is not
        a scan."""
        if elem.get("method") != "eth_getLogs":
            return False
        params = elem.get("params") or []
        crit = params[0] if params and isinstance(params[0], dict) else {}
        head = self._head()
        if head is None:
            return True          # cannot bound it -> refuse rather than ship the read open
        frm = self._block_ref(crit.get("fromBlock"), head)
        to = self._block_ref(crit.get("toBlock"), head)
        if frm is None or to is None:
            return True
        return (to - frm) > MAX_LOG_RANGE

    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
        except ValueError:
            return self._send(400, {"error": "bad Content-Length"})
        if length <= 0:
            return self._send(400, {"error": "empty body"})
        if length > MAX_BODY:
            return self._send(413, {"error": f"body over {MAX_BODY} bytes"})

        raw = self.rfile.read(length)

        # Parse BEFORE forwarding: the filter has to be on the actual method name, not a string
        # search of the body (which a padded or re-encoded request would defeat).
        try:
            req = json.loads(raw)
        except Exception:
            return self._send(400, {"error": "body is not JSON"})

        elems = req if isinstance(req, list) else [req]
        if isinstance(req, list) and (len(elems) == 0 or len(elems) > MAX_BATCH):
            return self._send(400, {"error": f"batch size must be 1..{MAX_BATCH}"})
        for e in elems:
            if not isinstance(e, dict):
                return self._send(400, {"error": "batch element is not an object"})
            m = e.get("method")
            if not isinstance(m, str) or m not in ALLOWED:
                return self._deny(str(m))

        # Past the allow-list, so this would now reach Besu. Bound the one method whose cost the
        # caller chooses, before the budget check, so a huge range cannot also consume tokens.
        for e in elems:
            if self._range_too_wide(e):
                with Handler.lock:
                    Handler.range_refused += 1
                return self._send(400, {"jsonrpc": "2.0", "id": e.get("id"), "error": {
                    "code": -32602,
                    "message": f"eth_getLogs range over {MAX_LOG_RANGE} blocks is not served by the "
                               f"public endpoint; narrow fromBlock/toBlock"}})

        # Per-client budget, charged only on the forwarded path. Blocked and malformed requests cost
        # no upstream work, so flooding those is not what this protects against.
        allowed, _retry_after = self._take(self._client_ip())
        if not allowed:
            return self._too_busy()

        with Handler.lock:
            Handler.hits += 1

        if not Handler.permits.acquire(blocking=False):
            with Handler.lock:
                Handler.rejected_busy += 1
            return self._send(429, {"jsonrpc": "2.0", "id": None,
                                    "error": {"code": -32005, "message": "read-only endpoint busy, retry"}})
        try:
            self._forward(raw)
        finally:
            Handler.permits.release()

    def _forward(self, raw):
        conn = http.client.HTTPConnection(UPSTREAM_HOST, UPSTREAM_PORT, timeout=30)
        # Do NOT copy the caller's Host header upstream. Besu enforces --host-allowlist (default
        # localhost) as an anti-DNS-rebinding guard on direct access, so forwarding Host:
        # rpc.lxon.in made Besu answer 403 {"message":"Host not authorized."} on the public path
        # while every loopback test still passed -- the tests used a localhost Host. Letting
        # http.client send its own Host (127.0.0.1:8545) is what the upstream expects; the caller's
        # Host is preserved for logging by Caddy's X-Forwarded-Host, not by this header.
        try:
            conn.request("POST", "/", body=raw,
                         headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            data = resp.read()
        except Exception as e:
            return self._send(502, {"error": f"upstream unavailable: {e}"})
        finally:
            conn.close()
        self._send(resp.status, data)

    def do_GET(self):
        # A plain GET is how a human checks liveness. Answering with the chain id costs nothing
        # and makes "is it up" answerable from a browser.
        conn = http.client.HTTPConnection(UPSTREAM_HOST, UPSTREAM_PORT, timeout=10)
        try:
            body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "eth_chainId", "params": []}).encode()
            conn.request("POST", "/", body=body, headers={"Content-Type": "application/json"})
            data = conn.getresponse().read()
        except Exception as e:
            return self._send(502, {"error": str(e)})
        finally:
            conn.close()
        self._send(200, data)


class Server(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 128
    allow_reuse_address = True


def stats():
    return {"served": Handler.hits, "blocked": Handler.blocked}


if __name__ == "__main__":
    srv = Server((LISTEN_HOST, LISTEN_PORT), Handler)
    print(f"lxon rpc gateway on http://{LISTEN_HOST}:{LISTEN_PORT} -> {UPSTREAM_HOST}:{UPSTREAM_PORT}",
          flush=True)
    print(f"allow-listed methods: {len(ALLOWED)}   never-allowed named: {len(NEVER)}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
