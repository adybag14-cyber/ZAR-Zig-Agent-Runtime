# ZAR vs ZigOS Bounded Shell Control Slice

## Classification

- provenance: `reference-inspired`
- source influence: `Cameron-Lyons/zigos/src/kernel/shell/*`
- implementation posture: ZAR-owned bounded control layer over the existing builtin and framed tool-service surfaces

## Scope

Deliver the first shell/control slice without forcing a GP-OS jump.

This slice is intentionally limited to:

- bounded command batching over existing builtins
- bounded glob expansion over the current filesystem surface
- bounded stdin/stdout/stderr redirection over the current filesystem surface
- bounded shell metacharacter escaping for separators and redirection, including escaped `<`
- typed framed reuse over the existing TCP tool-service path
- live proof over an existing real NIC lane

This slice explicitly does not claim:

- interactive shell
- job control
- pipelines
- userspace programs
- editor/TTY parity
- a syscall-visible shell ABI

## Delivered Implementation

- `src/baremetal/tool_exec.zig`
  - `shell-run <command[;command...]>`
  - `shell-expand <pattern>`
  - shared bounded script execution through `executeScriptContents(...)`
  - bounded glob matching across multiple path segments with `*` and `?`
  - bounded shell escaping for `\;`, `\<`, `\>`, `\\`, and quoted separators on the parser path
  - bounded stdin redirection through `<`
  - bounded stdout redirection through `>` and `>>`
  - bounded stderr redirection through `2>` and `2>>`
  - hard `64`-command cap via `max_shell_command_count`
- `src/baremetal/tool_service/codec.zig`
  - typed `SHELLRUN`
  - typed `SHELLEXPAND`
- `src/baremetal/tool_service.zig`
  - framed request handling for bounded shell batching and glob expansion
- `src/baremetal_main.zig`
  - live `E1000` tool-service proof widened to validate shell help, bounded batch execution, escaped metacharacters, file-fed stdin flows, multi-segment glob expansion, redirected stdin/stdout/stderr behavior, and persisted filesystem readback
- `build.zig`
  - bare-metal artifact now explicitly includes `scripts/baremetal/pvh_boot.S` and `scripts/baremetal/pvh_lld.ld` so the Multiboot2 header remains within the required first `32768` bytes on current Zig `master`

## Validation Gates

- `scripts/baremetal-smoke-check.ps1`
- `zig test src/baremetal_main.zig --test-filter e1000`
- `zig build test --summary all`
- `scripts/baremetal-qemu-e1000-tool-service-probe-check.ps1`
- `scripts/check-go-method-parity.ps1`
- `scripts/docs-status-check.ps1 -RefreshParity`

## Follow-Up

Allowed later if ZAR chooses to widen the shell path deliberately:

- parser depth beyond separator-aware batching
- richer quoting and escaping beyond the current bounded metacharacter rules
- pipelines and broader process/input plumbing
- interactive TTY/session model
- job control
- editor/httpd utilities
- eventual userspace shell only if ZAR explicitly adopts a GP-OS direction
