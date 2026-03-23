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
  - direct wrapper-command bypass of the outer shell-line parser for `shell-run`, `tty-send`, and `tty-shell` so embedded shell text keeps its own redirection semantics
  - bounded glob matching across multiple path segments with `*` and `?`
  - bounded shell escaping for `\;`, `\<`, `\>`, `\\`, escaped whitespace on redirection paths, escaped-whitespace direct path arguments for path-consuming builtins, and quoted separators on the parser path
  - malformed quoted arguments now fail early when a closing quote is not followed by whitespace or end-of-command
  - bounded stdin redirection through `<`
  - bounded stdout redirection through `>` and `>>`
  - bounded stderr redirection through `2>` and `2>>`
  - escaped quotes are supported on the redirection-path side of the bounded shell parser and on the direct quoted-path argument path for path-consuming builtins; malformed quoted direct-command paths reject early with builtin-specific usage output; the parser remains intentionally bounded and is not a full shell tokenizer
  - hard `64`-command cap via `max_shell_command_count`
- `src/baremetal/tool_service/codec.zig`
  - typed `SHELLRUN`
  - typed `SHELLEXPAND`
- `src/baremetal/tool_service.zig`
  - framed request handling for bounded shell batching and glob expansion
- `src/baremetal_main.zig`
  - live `E1000` tool-service proof widened to validate shell help, bounded batch execution, escaped metacharacters, file-fed stdin flows, escaped-whitespace redirection paths, escaped-whitespace direct path arguments for path-consuming builtins, multi-segment glob expansion, direct quoted-path read/write behavior for path-consuming builtins, redirected stdin/stdout/stderr behavior, and persisted filesystem readback
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
