## ZAR vs ZigOS Bounded TTY Control Slice

### Classification

- provenance: `reference-inspired`
- source influence: `Cameron-Lyons/zigos/src/kernel/fs/tty.zig`
- implementation posture: ZAR-owned bounded session/control layer over the existing builtin, virtual-fs, and framed tool-service seams

### Scope

Deliver the first TTY/session control plus shell-execution slice without forcing a GP-OS jump.

This slice is intentionally limited to:

- bounded persisted TTY session receipts
- bounded queued TTY input and event receipts
- bounded command submission through the existing builtin runtime
- bounded shell batch submission through the existing builtin runtime
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
  - `pending.log`
  - `stdout.log`
  - `stderr.log`
  - `events.log`
  - `transcript.log`
  - bounded helpers:
    - `listSessionsAlloc(...)`
    - `renderStateAlloc(...)`
    - `openSession(...)`
    - `closeSession(...)`
    - `recordCommand(...)`
    - `recordShell(...)`
    - `writePendingInput(...)`
    - `clearPendingInput(...)`
    - `takePendingInputAlloc(...)`
    - `pendingAlloc(...)`
    - `eventsAlloc(...)`
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
  - `tty-pending <name>`
  - `tty-events <name>`
  - `tty-stdout <name>`
  - `tty-stderr <name>`
  - `tty-write <name> <content>`
  - `tty-send <name> <command>`
  - `tty-shell <name> <script>`
  - `tty-clear <name>`
  - `tty-close <name>`
- `src/baremetal/tool_service/codec.zig`
  - typed:
    - `TTYLIST`
    - `TTYOPEN`
    - `TTYINFO`
    - `TTYREAD`
    - `TTYPENDING`
    - `TTYEVENTS`
    - `TTYSTDOUT`
    - `TTYSTDERR`
    - `TTYWRITE`
    - `TTYSEND`
    - `TTYSHELL`
    - `TTYCLEAR`
    - `TTYCLOSE`
- `src/baremetal/tool_service.zig`
  - framed request handling for bounded TTY/session control
- `src/baremetal/virtual_fs.zig`
  - `/dev/tty/state`
  - `/dev/tty/sessions/<name>/{info,input,pending,stdout,stderr,events,transcript}`
  - `/sys/tty/state`
  - `/sys/tty/sessions/<name>/{info,input,pending,stdout,stderr,events,transcript}`
- `src/baremetal_main.zig`
  - live `E1000` tool-service proof widened to validate:
    - help exposure of `tty-send` plus `tty-shell`
    - `TTYOPEN`
    - `TTYWRITE`
    - `TTYPENDING`
    - `TTYSEND` success and failure with queued stdin drain
    - `TTYSHELL` with queued stdin drain into the bounded shell batch
    - per-command `< file` override inside `TTYSHELL` while later commands in the same batch still see the drained session stdin if they do not override it
    - bounded quoted-path shell receipts through the same direct path-consuming builtin rules used by `SHELLRUN`
    - `TTYCLEAR`
    - `TTYEVENTS`
    - `TTYREAD`
    - `TTYSTDOUT`
    - `TTYSTDERR`
    - `/dev/tty/state`
    - `/dev/tty/sessions`
    - `/dev/tty/sessions/<name>/info`
    - `/dev/tty/sessions/<name>/pending`
    - `/dev/tty/sessions/<name>/events`
    - persisted shell output readback
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
- full terminal emulation
- userspace-visible TTY ABI
