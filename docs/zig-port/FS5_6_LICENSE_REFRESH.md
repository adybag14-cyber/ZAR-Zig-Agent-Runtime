# FS5.6 License Refresh

This document tracks the repo-wide licensing refresh for ZAR-Zig-Agent-Runtime.

## Decision

- Project-wide license posture: `GPL-2.0-only`
- Source/script header format: Linux-style SPDX identifier
  - `SPDX-License-Identifier: GPL-2.0-only`

## Scope

- Root `LICENSE`
- Package-local `LICENSE` files for npm and Python client subtrees
- npm/Python package metadata
- release evidence / SBOM license declarations
- repo-owned source and script files
- README and operator-facing docs
- issue `#1` tracking state

## Header policy

- Zig / JavaScript / TypeScript declaration files:
  - `// SPDX-License-Identifier: GPL-2.0-only`
- PowerShell / Python:
  - `# SPDX-License-Identifier: GPL-2.0-only`
- Assembly (`.S`):
  - `/* SPDX-License-Identifier: GPL-2.0-only */`

## Exclusions

- Generated outputs under `release/`, `.zig-cache/`, `node_modules/`, and virtualenv content
- Binary assets and certificate/testdata blobs
- Unrelated local user WIP that is already dirty in the working tree

## Validation gates

- `zig build test --summary all`
- `scripts/check-go-method-parity.ps1`
- `scripts/docs-status-check.ps1 -RefreshParity`
- `scripts/npm-pack-check.ps1`
- `scripts/python-pack-check.ps1`
