#!/usr/bin/env python3
"""
Control tests for the two load gates added to rpc-gateway.py on 2026-11-03:
a per-client token bucket, and a bound on the one allow-listed method whose cost the caller picks.

Every gate is tested three ways, because a limiter that cannot fail is not a limiter:
  * the case that must PASS does pass,
  * the OPPOSITE case still fails (so the pass is not an accident of a permissive stub),
  * and a real success still succeeds afterwards (so the failure did not wedge the endpoint).

Run: python3 test-rpc-gateway-limits.py     (no AWS, no chain, no docker -- a stub upstream)
"""
import http.client, importlib.util, json, os, socket, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
GW = os.path.join(HERE, "rpc-gateway.py")

# ---- limits chosen small so the test is fast; the gateway reads them from the environment ----
BURST = "12"
REFILL = "4"
LOG_RANGE = "100"

free = []
for _ in range(3):
    s = socket.socket(); s.bind(("127.0.0.1", 0)); free.append(s.getsockname()[1]); s.close()
UP_PORT, GW_PORT, CTRL_PORT = free

upstream_log = []                      # every method that actually reached the stub
HEAD = {"n": 0x2710, "broken": False}  # 10000


class Stub(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(n)
        try:
            req = json.loads(raw)
        except Exception:
            return self._send(400, {"error": "bad json"})
        elems = req if isinstance(req, list) else [req]
        for e in elems:
            upstream_log.append(e.get("method"))
        if HEAD["broken"]:
            # A head that cannot be read must make the range gate refuse, not wave the request through
            return self._send(200, {"jsonrpc": "2.0", "id": 1, "error": {"code": -32000, "message": "no"}})
        if elems[0].get("method") == "eth_blockNumber":
            return self._send(200, {"jsonrpc": "2.0", "id": 1, "result": hex(HEAD["n"])})
        if elems[0].get("method") == "eth_getLogs":
            return self._send(200, {"jsonrpc": "2.0", "id": 1, "result": []})
        return self._send(200, {"jsonrpc": "2.0", "id": 1, "result": "0x2d4"})

    def _send(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)


def load_gateway():
    """Import the gateway with the test limits and its upstream pointed at the stub."""
    os.environ.update(GWAY_LISTEN_HOST="127.0.0.1", GWAY_LISTEN_PORT=str(GW_PORT),
                      GWAY_UPSTREAM_HOST="127.0.0.1", GWAY_UPSTREAM_PORT=str(UP_PORT),
                      GWAY_MAX_CONCURRENT="4", GWAY_RATE_BURST=BURST, GWAY_RATE_PER_SEC=REFILL,
                      GWAY_MAX_LOG_RANGE=LOG_RANGE, GWAY_HEAD_TTL="0")
    spec = importlib.util.spec_from_file_location("lxon_rpc_gateway_under_test", GW)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


FAILS = []


def check(label, cond, detail=""):
    print(("  PASS  " if cond else "  FAIL  ") + label + (f"   [{detail}]" if detail and not cond else ""))
    if not cond:
        FAILS.append(label)


def post(payload, xff=None, timeout=10):
    body = payload if isinstance(payload, str) else json.dumps(payload)
    conn = http.client.HTTPConnection("127.0.0.1", GW_PORT, timeout=timeout)
    h = {"Content-Type": "application/json"}
    if xff:
        h["X-Forwarded-For"] = xff
    try:
        conn.request("POST", "/", body=body, headers=h)
        r = conn.getresponse()
        return r.status, r.read().decode()
    except Exception as e:
        return 0, str(e)
    finally:
        conn.close()


def rpc(method, params=None, id=1):
    return {"jsonrpc": "2.0", "id": id, "method": method, "params": params or []}


def main():
    stub = ThreadingHTTPServer(("127.0.0.1", UP_PORT), Stub)
    stub.daemon_threads = True
    threading.Thread(target=stub.serve_forever, daemon=True).start()

    mod = load_gateway()
    srv = mod.Server(("127.0.0.1", GW_PORT), mod.Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    for _ in range(50):
        try:
            if post(rpc("eth_chainId"))[0] == 200:
                break
        except Exception:
            pass
        time.sleep(0.1)

    H = mod.Handler

    print("=== A. the forwarded path still works (positive control for everything below) ===")
    code, body = post(rpc("eth_chainId"))
    check("a plain read is served", code == 200 and "0x2d4" in body, f"{code} {body[:80]}")
    check("and it reached the upstream", "eth_chainId" in upstream_log)

    print("=== B. eth_getLogs range bound ===")
    upstream_log.clear()
    # head is 0x2710 = 10000; fromBlock 0 spans 10000 blocks, limit is 100
    code, body = post(rpc("eth_getLogs", [{"fromBlock": "0x0", "toBlock": "latest"}]))
    check("whole-chain getLogs refused", code == 400 and "not served" in body, f"{code} {body[:100]}")
    check("REFUSED getLogs never reached the upstream", "eth_getLogs" not in upstream_log,
          str(upstream_log))

    code, body = post(rpc("eth_getLogs", [{"fromBlock": "0x0", "toBlock": "0x64"}]))  # 100 blocks
    check("getLogs at exactly the limit served", code == 200, f"{code} {body[:100]}")
    check("the served getLogs DID reach the upstream", "eth_getLogs" in upstream_log)

    upstream_log.clear()
    code, body = post(rpc("eth_getLogs", [{"fromBlock": "0x0", "toBlock": "0x65"}]))  # 101 blocks
    check("getLogs one block over the limit refused", code == 400, f"{code} {body[:100]}")
    check("over-limit getLogs did not reach the upstream", "eth_getLogs" not in upstream_log)

    code, body = post(rpc("eth_getLogs", [{"fromBlock": "0x0"}]))   # toBlock absent => latest
    check("fromBlock=0 with no toBlock refused (the real bypass)", code == 400, f"{code} {body[:100]}")

    code, body = post(rpc("eth_getLogs", []))                       # both tags absent
    # Per the JSON-RPC spec an absent fromBlock AND absent toBlock both default to `latest`, so
    # this is a one-block read, not a whole-chain scan -- serving it is correct, refusing it would
    # be a bug. The dangerous half (one tag absent) is the case asserted above.
    check("criteria-less getLogs served (both tags default to latest = 1 block)", code == 200,
          f"{code} {body[:100]}")

    print("=== C. the bound is resolved against the real head, not assumed ===")
    HEAD["n"] = 10 ** 9                                    # a huge chain
    H.head_cache = [None, 0.0]                             # force a re-read
    code, body = post(rpc("eth_getLogs", [{"fromBlock": "0x3B9ACA00", "toBlock": "latest"}]))
    # from == head => span 0 => allowed even on a billion-block chain
    check("zero-span getLogs allowed on a 1e9-block chain", code == 200, f"{code} {body[:100]}")
    HEAD["n"] = 0x2710
    H.head_cache = [None, 0.0]

    print("=== D. an unreadable head fails CLOSED ===")
    HEAD["broken"] = True
    H.head_cache = [None, 0.0]
    code, body = post(rpc("eth_getLogs", [{"fromBlock": "0x0", "toBlock": "latest"}]))
    check("getLogs refused when the head cannot be proven", code == 400, f"{code} {body[:120]}")
    HEAD["broken"] = False
    H.head_cache = [None, 0.0]
    code, _ = post(rpc("eth_getLogs", [{"fromBlock": "0x0", "toBlock": "0x10"}]))
    check("getLogs works again once the head is readable", code == 200, f"{code}")

    print("=== E. token bucket: burst, flatten, refill ===")
    H.buckets.clear()
    codes = [post(rpc("eth_blockNumber"))[0] for _ in range(int(BURST))]
    check(f"the burst ({BURST} requests) is served", all(c == 200 for c in codes), str(codes))
    codes2 = [post(rpc("eth_blockNumber"))[0] for _ in range(6)]
    check("continuing past the burst is throttled", 429 in codes2, str(codes2))
    check("throttling is 429 not 200", codes2.count(200) <= 3, str(codes2))

    # the opposite case: a throttled request must NOT have reached the upstream
    upstream_log.clear()
    post(rpc("eth_blockNumber"))
    check("a throttled read did not reach the upstream", len(upstream_log) == 0, str(upstream_log))

    time.sleep(2.5)                                        # 4/s * 2.5s = 10 tokens back
    code, body = post(rpc("eth_blockNumber"))
    check("the same client recovers after refill (slow clients unaffected)", code == 200, f"{code}")

    print("=== F. a second client is not punished for the first one's flood ===")
    H.buckets.clear()
    for _ in range(int(BURST) + 8):
        post(rpc("eth_blockNumber"), xff="203.0.113.7")
    victim = post(rpc("eth_blockNumber"), xff="198.51.100.4")
    check("an innocent client still gets 200 while another is limited", victim[0] == 200, str(victim[0]))

    print("=== G. client identity is the address Caddy appended, not the one the caller typed ===")
    # Our proxy writes the real peer LAST. The left-hand entries are attacker-controlled.
    spoofed = post(rpc("eth_blockNumber"), xff="8.8.8.8, 203.0.113.99")
    check("a request with a forged left-hand XFF entry is served", spoofed[0] == 200)

    class Fake:
        def __init__(self, hdrs, peer):
            self.headers = hdrs
            self.client_address = (peer, 1)

        def _client(self):
            return H.__mro__  # unused

    h = H.__new__(H)
    h.headers = {"X-Forwarded-For": "1.1.1.1, 2.2.2.2, 3.3.3.3"}
    h.client_address = ("127.0.0.1", 5)
    got = mod.Handler._client_ip(h)
    check("rightmost XFF entry is used (client cannot prepend itself past the limit)",
          got == "3.3.3.3", got)
    h2 = H.__new__(H)
    h2.headers = {}
    h2.client_address = ("127.0.0.1", 5)
    check("with no proxy header the socket peer is used", mod.Handler._client_ip(h2) == "127.0.0.1")

    print("=== H. the budget is charged only on the forwarded path ===")
    H.buckets.clear()
    upstream_log.clear()
    for _ in range(int(BURST) + 5):
        post(rpc("eth_sendRawTransaction", ["0xdead"]))    # refused at the allow-list
    check("no refused request reached the upstream", len(upstream_log) == 0, str(upstream_log))
    probe = post(rpc("eth_chainId"))[0]
    check("flooding a refused method cannot exhaust a bucket", probe == 200, str(probe))
    # exactly one upstream entry: the probe itself. Asserting 0 here would be a test bug, because
    # the probe that proves the bucket is intact is itself a forwarded read.
    check("and only the probe reached it", upstream_log == ["eth_chainId"], str(upstream_log))

    print("=== I. the browser path: CORS preflight (found by asking, not by curl) ===")
    H.buckets.clear()
    upstream_log.clear()

    def options(xff=None):
        conn = http.client.HTTPConnection("127.0.0.1", GW_PORT, timeout=10)
        h = {"Origin": "https://www.lxon.in", "Access-Control-Request-Method": "POST",
             "Access-Control-Request-Headers": "content-type"}
        if xff:
            h["X-Forwarded-For"] = xff
        conn.request("OPTIONS", "/", headers=h)
        r = conn.getresponse(); r.read(); conn.close()
        return r

    pre = options()
    check("OPTIONS preflight is answered (was 501 -> browser never sends the POST)",
          pre.status == 204, f"got {pre.status}")
    check("preflight allows the site origin (any origin is what * means)", pre.getheader("Access-Control-Allow-Origin") == "*",
          str(pre.getheader("Access-Control-Allow-Origin")))
    check("preflight names POST/GET/OPTIONS", "POST" in (pre.getheader("Access-Control-Allow-Methods") or ""),
          str(pre.getheader("Access-Control-Allow-Methods")))
    check("preflight permits the content-type header the real request uses",
          "content-type" in (pre.getheader("Access-Control-Allow-Headers") or "").lower(),
          str(pre.getheader("Access-Control-Allow-Headers")))
    check("the preflight was NOT forwarded upstream", len(upstream_log) == 0, str(upstream_log))

    # 204 must not carry a body or a Content-Length, or some clients hang waiting for it.
    cl = pre.getheader("Content-Length")
    check("204 sends no Content-Length", cl in (None, "0"), f"Content-Length={cl}")

    # and a preflight must not spend the client's budget -- a page that refreshes every 5 s preflights
    # too, and charging for it would throttle the very client the limit is meant to protect.
    for _ in range(30):
        options()
    check("preflights consume no token", post(rpc("eth_chainId"))[0] == 200)

    # the opposite case: the forwarded POST path still IS charged, so the exemption above is not
    # just a broken limiter.
    H.buckets.clear()
    n = int(BURST) + 6
    codes3 = [post(rpc("eth_blockNumber"))[0] for _ in range(n)]
    check("real reads are still charged (429 appears past the burst)", 429 in codes3, str(codes3))

    print("=== J. malformed input is still refused as before (no regression) ===")
    for label, payload, want in [
        ("non-JSON body", "not json at all", 400),
        ("empty body", "", 400),
        ("unlisted method", rpc("personal_importRawKey"), 403),
        ("blocked method inside a valid batch",
         json.dumps([rpc("eth_chainId", id=1), rpc("eth_sendRawTransaction", ["0x0"], id=2)]), 403),
        ("11-element batch", json.dumps([rpc("eth_chainId", id=i) for i in range(11)]), 400),
    ]:
        code, _ = post(payload)
        check(f"{label} -> {want}", code == want, f"got {code}")

    print()
    print(f"  throttled={H.throttled}  range_refused={H.range_refused}  blocked={H.blocked}")
    if FAILS:
        print(f"  {len(FAILS)} FAILURE(S):")
        for f in FAILS:
            print("    -", f)
        sys.exit(1)
    print("  all limit checks passed")


if __name__ == "__main__":
    main()
