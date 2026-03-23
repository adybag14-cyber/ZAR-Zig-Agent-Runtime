## ZAR vs ZigOS Bounded TTY Control Slice

### Classification

- provenance: `reference-inspired`
- source influence: `Cameron-Lyons/zigos/src/kernel/fs/tty.zig`
- implementation posture: ZAR-owned bounded session/control layer over the existing builtin, virtual-fs, and framed tool-service seams

### Scope

Deliver the first TTY/session slice without forcing a GP-OS jump.

This slice is intentionally limited to:

- bounded persisted TTY session receipts
- bounded command submission through the existing builtin runtime
- bounded stdout/stderr/transcript readback
- bounded `/dev/tty` and `/sys/tty` export over persisted session state
- typed framed reuse over the existing TCP tool-service path
- live proof over the existing clean-room `E1000` lane

This slice explicitly does not claim:

- terminal emulation
- interactive line editing
- pipes or job control
- PTY/TTY master-slave semantics
- userspace-visible TTY/syscall ABI
- editor parity

### Delivered Implementation

- `src/baremetal/tty_runtime.zig`
  - persisted bounded TTY sessions under `/runtime/tty/<name>/`
  - `state.txt`
  - `input.log`
  - `stdout.log`
  - `stderr.log`
  - `transcript.log`
  - bounded helpers:
    - `listSessionsAlloc(...)`
    - `renderStateAlloc(...)`
    - `openSession(...)`
    - `closeSession(...)`
    - `recordCommand(...)`
    - `infoAlloc(...)`
    - `inputAlloc(...)`
    - `stdoutAlloc(...)`
    - `stderrAlloc(...)`
    - `transcriptAlloc(...)`
- `src/baremetal/tool_exec.zig`
  - `tty-list`
  - `tty-open <name>`
  - `tty-info <name>`
  - `tty-read <name>`
  - `tty-stdout <name>`
  - `tty-stderr <name>`
  - `tty-send <name> <command>`
  - `tty-close <name>`
- `src/baremetal/tool_service/codec.zig`
  - typed:
    - `TTYLIST`
    - `TTYOPEN`
    - `TTYINFO`
    - `TTYREAD`
    - `TTYSTDOUT`
    - `TTYSTDERR`
    - `TTYSEND`
    - `TTYCLOSE`
- `src/baremetal/tool_service.zig`
  - framed request handling for bounded TTY/session control
- `src/baremetal/virtual_fs.zig`
  - `/dev/tty/state`
  - `/dev/tty/sessions/<name>/{info,input,stdout,stderr,transcript}`
  - `/sys/tty/state`
  - `/sys/tty/sessions/<name>/{info,input,stdout,stderr,transcript}`
- `src/baremetal_main.zig`
  - live `E1000` tool-service proof widened to validate:
    - help exposure of `tty-send`
    - `TTYOPEN`
    - `TTYSEND` success and failure
    - `TTYREAD`
    - `TTYSTDOUT`
    - `TTYSTDERR`
    - `/dev/tty/state`
    - `/dev/tty/sessions`
    - `/dev/tty/sessions/<name>/info`
    - `TTYCLOSE`
    - `/sys/tty/state`

### Validation Gates

- `zig build test --summary all`
- `scripts/baremetal-qemu-e1000-tool-service-probe-check.ps1`
- `scripts/check-go-method-parity.ps1`
- `scripts/docs-status-check.ps1 -RefreshParity`

### Follow-Up

Allowed later if ZAR chooses to widen the TTY path deliberately:

- interactive console semantics
- bounded line editing/history
- PTY-style session split
- shell job control integration
- pipe and redirection semantics beyond the current command/session layer
- evented TTY input stream
- userspace-visible TTY ABI
