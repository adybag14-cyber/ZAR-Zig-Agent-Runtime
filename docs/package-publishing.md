# Package Publishing

This repo ships three package-consumption paths for the Zig RPC client surfaces:

- npm package: `@adybag14-cyber/openclaw-zig-rpc-client`
- Python package: `openclaw-zig-rpc-client`
- `uvx` CLI execution via the Python package

All published package surfaces now carry `GPL-2.0-only` metadata and a package-local `LICENSE` file.

## Current Edge Release

- GitHub edge release target tag: `v0.2.0-zig-edge.31`
- npm package version: `0.2.0-zig-edge.31`
- Python package version: `0.2.0.dev31`

## Install Paths

### npm

Preferred when npmjs is configured:

```bash
npm install @adybag14-cyber/openclaw-zig-rpc-client@0.2.0-zig-edge.31
```

Fallback from the GitHub release tarball:

```bash
npm install "https://github.com/adybag14-cyber/ZAR-Zig-Agent-Runtime/releases/download/v0.2.0-zig-edge.31/adybag14-cyber-openclaw-zig-rpc-client-0.2.0-zig-edge.31.tgz"
```

### pip

Preferred when PyPI is configured:

```bash
pip install openclaw-zig-rpc-client==0.2.0.dev31
```

Fallback from the GitHub release wheel:

```bash
pip install "https://github.com/adybag14-cyber/ZAR-Zig-Agent-Runtime/releases/download/v0.2.0-zig-edge.31/openclaw_zig_rpc_client-0.2.0.dev31-py3-none-any.whl"
```

### uvx

Preferred when PyPI is configured:

```bash
uvx --from openclaw-zig-rpc-client openclaw-zig-rpc health --base-url http://127.0.0.1:8080
```

Git fallback verified locally against the release tag:

```bash
uvx --from "git+https://github.com/adybag14-cyber/ZAR-Zig-Agent-Runtime@v0.2.0-zig-edge.31#subdirectory=python/openclaw-zig-rpc-client" openclaw-zig-rpc health --base-url http://127.0.0.1:8080
```

## Registry Configuration Requirements

### npmjs public publish

The workflow supports two public-publish paths:

- `NPM_TOKEN` secret for classic token-based publish
- npm trusted publishing with GitHub Actions OIDC

If neither public path succeeds, the workflow falls back to GitHub Packages and still attaches the tarball to the GitHub release.

Current state observed during `v0.2.0-zig-edge.31`:

- `npm-release` reaches the real npmjs publish path with `NPM_TOKEN`
- the tarball was attached to the GitHub prerelease
- public npmjs visibility for `@adybag14-cyber/openclaw-zig-rpc-client@0.2.0-zig-edge.31` still returns `404 Not Found`
- the latest publish attempt fails with `EOTP` because npm requires an authenticator one-time password for publish

That means the public npmjs side still needs one of:

1. an npm automation/publish token that is not blocked by account 2FA publish requirements
2. account-side npm configuration that allows this token to publish without interactive OTP

Reference:

- npm docs note that publishing a public organization-scoped package requires the scope organization to exist on npmjs and the publisher to have the right permissions.

### PyPI public publish

The workflow supports two public-publish paths:

- `PYPI_API_TOKEN` secret for classic token-based publish
- PyPI trusted publishing via GitHub Actions OIDC

If neither public path succeeds, the workflow still attaches the wheel and sdist to the GitHub release.

Current state observed during `v0.2.0-zig-edge.31`:

- `python-release` now normalizes `v0.2.0-zig-edge.31` to the PEP 440 Python version `0.2.0.dev31`
- the wheel and sdist were attached to the GitHub prerelease
- public PyPI visibility for `openclaw-zig-rpc-client==0.2.0.dev31` still returns `404 Not Found`
- trusted publishing still fails with `invalid-publisher`

That means PyPI does not yet have a matching trusted publisher entry for:

- repository: `adybag14-cyber/ZAR-Zig-Agent-Runtime`
- workflow: `.github/workflows/python-release.yml`
- ref: `refs/heads/main`
- environment: `pypi`

Exact claims emitted by the latest trusted-publish attempt on `main`:

- `sub`: `repo:adybag14-cyber/ZAR-Zig-Agent-Runtime:environment:pypi`
- `repository`: `adybag14-cyber/ZAR-Zig-Agent-Runtime`
- `repository_owner`: `adybag14-cyber`
- `workflow_ref`: `adybag14-cyber/ZAR-Zig-Agent-Runtime/.github/workflows/python-release.yml@refs/heads/main`
- `job_workflow_ref`: `adybag14-cyber/ZAR-Zig-Agent-Runtime/.github/workflows/python-release.yml@refs/heads/main`
- `ref`: `refs/heads/main`
- `environment`: `pypi`

Fix either by:

1. adding a matching trusted publisher in PyPI for `openclaw-zig-rpc-client`
2. setting `PYPI_API_TOKEN` in repo secrets

The workflow now uses the GitHub Actions environment `pypi`, and the repo-side OIDC claim shape is confirmed in the run above. If PyPI is configured with that exact publisher shape, rerunning the workflow should publish successfully without further repo changes.

## Workflow Outputs

- `npm-release.yml`
  - attaches the built `.tgz` to the GitHub release
  - attempts npmjs publish first
  - falls back to GitHub Packages when public publish is unavailable
  - uploads `package-registry-status-npm.json` preflight evidence for the target version/tag
- `python-release.yml`
  - attaches the built wheel and sdist to the GitHub release
  - attempts PyPI publish when token or trusted publisher is available
  - uploads `package-registry-status-python.json` preflight evidence for the target version/tag
- `release-preview.yml`
  - now generates and attaches `package-registry-status.json` to the edge release itself
  - now also generates and attaches `release-status.json` and `release-status.md` so each edge release carries a frozen workflow + registry snapshot
  - this gives each release a frozen snapshot of GitHub asset presence, npmjs visibility, PyPI visibility, and `uvx` fallback readiness

## Registry Preflight Script

Local/operator check:

```powershell
pwsh ./scripts/package-registry-status.ps1 `
  -ReleaseTag v0.2.0-zig-edge.31 `
  -NpmPackageName @adybag14-cyber/openclaw-zig-rpc-client `
  -NpmVersion 0.2.0-zig-edge.31 `
  -PythonPackageName openclaw-zig-rpc-client `
  -PythonVersion 0.2.0.dev31 `
  -OutputJsonPath ./release/package-registry-status.json
```

This emits a machine-readable report covering:

- release asset presence on GitHub
- npmjs package/version visibility
- PyPI package/version visibility
- whether the GitHub release already contains the Python artifacts needed for the documented `uvx` fallback

## Consolidated Release Status

Local/operator snapshot:

```powershell
pwsh ./scripts/release-status.ps1 `
  -ReleaseTag v0.2.0-zig-edge.31 `
  -OutputJsonPath ./release/release-status.json `
  -OutputMarkdownPath ./release/release-status.md
```

This emits:

- `release-status.json`
  - latest `zig-ci`, `docs-pages`, `release-preview`, `npm-release`, and `python-release` run state
  - current GitHub release publish/asset state
  - current npmjs/PyPI visibility state
  - explicit edge-release blockers vs public-registry blockers
- `release-status.md`
  - the same snapshot in operator-readable markdown

## Operator Rule

For edge releases, GitHub release assets are the source of truth when public registries are not yet configured. Do not block a validated edge cut on registry-side configuration drift.
