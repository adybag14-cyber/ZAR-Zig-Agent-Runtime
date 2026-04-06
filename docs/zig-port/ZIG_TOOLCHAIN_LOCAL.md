# Local Zig Toolchain Setup

This workspace uses a local Zig `master` toolchain with an explicit mirror-aware refresh policy.

## Canonical Source vs Distribution Mirror

- Canonical upstream source of truth: `https://codeberg.org/ziglang/zig.git`
- Windows release/distribution mirror: `https://github.com/adybag14-cyber/zig`
- Mirror release modes:
  - `latest-master`: rolling Windows refresh lane
  - `upstream-<sha>`: immutable reproducible lane for CI, bisects, and release recreation

The Zig OpenClaw port uses Codeberg `master` for freshness decisions, but the GitHub mirror helps by publishing a Windows asset URL, SHA256 digest, and target commitish that can be compared directly against the local toolchain.

## Installed Toolchain Layout

- Toolchain root: `C:\users\ady\documents\toolchains\zig-master`
- Active junction: `C:\users\ady\documents\toolchains\zig-master\current`
- Default Zig binary: `C:\users\ady\documents\toolchains\zig-master\current\zig.exe`

## Current Snapshot

- Local Zig version string: `0.16.0`
- Local installed mirror target (from `current\mirror-release.json`): `47d2e5de90faec1221f61255c36e2be81c9e3db3`
- Current Codeberg `master`: `f8997aca8f62eef4968e4abf817ece4eb4e91c38`
- Current GitHub mirror `latest-master` target: `47d2e5de90faec1221f61255c36e2be81c9e3db3`
- Current GitHub mirror Windows asset digest: `b54c6772a0cfa410ff880f914def1fd2c6c3f2c178e9d378257d04861344a4e0`
- Current status: local install matches the published GitHub mirror target, but both trail current Codeberg `master`
- Current validation note:
  - hosted master-Zig matrix is green on the local Windows lane: `706/707` passed (`1 skipped`)
  - live `RTL8139 TCP` and `RTL8139 HTTPS` QEMU probes pass on the current stable `ReleaseSafe` local probe lane
  - the broad `RTL8139 TCP` `Debug` QEMU probe still times out on this local master-Zig toolchain and remains an upstream/local-toolchain investigation item

## Required Checks

From the `ZAR-Zig-Agent-Runtime` working tree:

```powershell
./scripts/zig-codeberg-master-check.ps1
./scripts/zig-github-mirror-release-check.ps1
./scripts/zig-bootstrap-from-github-mirror.ps1 -DryRun
```

`zig-codeberg-master-check.ps1` reports:

- latest Codeberg `master` commit hash
- local Zig toolchain version/hash
- local hash source (`version` or installed mirror metadata)
- whether the local toolchain matches Codeberg `master`
- GitHub mirror release target commitish
- whether the mirror release matches Codeberg `master`
- Windows asset digest and download URL from the mirror

`zig-github-mirror-release-check.ps1` reports:

- GitHub mirror release tag
- target commitish
- Windows asset name, digest, and URL
- whether the release is rolling or immutable

`zig-bootstrap-from-github-mirror.ps1` supports:

- `-DryRun` to plan a refresh without changing the workstation
- default `latest-master` refresh for fast Windows catch-up
- `-UpstreamSha <sha>` to install from the immutable `upstream-<sha>` release

## Local Validation Command

```powershell
./scripts/zig-syntax-check.ps1
```

This runs:

1. `zig fmt --check`
2. `zig build`
3. `zig build test`
4. `zig build run`
