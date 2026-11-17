"""CLI: python -m lxon <command>"""
import sys
import json
from . import LxonClient


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: python -m lxon <rpc_url> [method] [args...]")
        return 1

    rpc_url = sys.argv[1]
    client = LxonClient(rpc_url=rpc_url)

    method = sys.argv[2] if len(sys.argv) > 2 else "eth_blockNumber"
    args = sys.argv[3:] if len(sys.argv) > 3 else []

    try:
        result = client._call(method, args)
        print(json.dumps(result, indent=2, default=str))
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())