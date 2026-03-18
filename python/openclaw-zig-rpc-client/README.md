# openclaw-zig-rpc-client

Python JSON-RPC client and CLI for ZAR-Zig-Agent-Runtime gateway endpoints.

## Install

```bash
pip install openclaw-zig-rpc-client
```

Release-wheel fallback:

```bash
pip install "https://github.com/adybag14-cyber/ZAR-Zig-Agent-Runtime/releases/download/v0.2.0-zig-edge.30/openclaw_zig_rpc_client-0.2.0.dev30-py3-none-any.whl"
```

Run directly with `uvx` after publishing:

```bash
uvx --from openclaw-zig-rpc-client openclaw-zig-rpc health --base-url http://127.0.0.1:8080
```

Verified `uvx` Git fallback for the current edge tag:

```bash
uvx --from "git+https://github.com/adybag14-cyber/ZAR-Zig-Agent-Runtime@v0.2.0-zig-edge.30#subdirectory=python/openclaw-zig-rpc-client" openclaw-zig-rpc health --base-url http://127.0.0.1:8080
```

## Python Usage

```python
from openclaw_zig_rpc_client import OpenClawClient

client = OpenClawClient(base_url="http://127.0.0.1:8080", timeout_seconds=30)
health = client.health()
print(health)
```

## CLI Usage

```bash
openclaw-zig-rpc health --base-url http://127.0.0.1:8080
openclaw-zig-rpc rpc update.plan --params-json '{"channel":"edge"}'
openclaw-zig-rpc rpc update.run --params-json '{"targetVersion":"edge","dryRun":true}'
```

## License

This package is distributed under `GPL-2.0-only`.
