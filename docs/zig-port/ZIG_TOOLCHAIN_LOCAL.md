# Local Zig Toolchain Setup

This workspace is configured to use a local Zig master toolchain.

## Installed toolchain

- Toolchain root: `C:\users\ady\documents\toolchains\zig-master`
- Active junction: `C:\users\ady\documents\toolchains\zig-master\current`
- Zig binary: `C:\users\ady\documents\toolchains\zig-master\current\zig.exe`
- Zig version: `0.16.0-dev.2682+02142a54d`

## Zig source (latest master commit from Codeberg)

- Source checkout: `C:\users\ady\documents\zig-master-src`
- Remote: `https://codeberg.org/ziglang/zig.git`
- Commit: `74f361a5ce5212ce321fd0ebfa4c158468a161bb`
- Commit subject: `std.math.big.int: address log2/log10 reviews`

## Syntax and build check command

From `openclaw-zig-port`:

```powershell
./scripts/zig-syntax-check.ps1
```

This runs:

1. `zig fmt --check`
2. `zig build`
3. `zig build test`
4. `zig build run`
