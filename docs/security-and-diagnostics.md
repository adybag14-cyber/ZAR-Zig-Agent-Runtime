# Security and Diagnostics

## Security Pipeline

- prompt-risk scoring
- blocked pattern checks
- loop-guard detection for repetitive flows
- policy bundle probing and validation

## Diagnostics Surfaces

- `security.audit`
  - summary and findings
  - optional deep probes
  - optional remediation actions (`fix`)
- `doctor`
  - operational checks
  - embeds audit-derived status
  - includes docker availability check
- `doctor.memory.status`
- gateway posture checks:
  - `gateway.auth_token`
  - `gateway.rate_limit`
- `secrets.store.status`
  - explicit secret-backend support classification
  - requested backend vs active backend
  - fallback reason when Zig is not using the requested native provider directly

## Secret Store Backend Matrix

The secret-store contract is explicit about backend support. Zig does not silently pretend native secret providers are complete when they are not.

| Requested backend | Active backend | Support level | Notes |
| --- | --- | --- | --- |
| `env` | `env` | `implemented` | in-memory only, non-persistent |
| `file` / `encrypted-file` | `encrypted-file` | `implemented` | XChaCha20-Poly1305 persisted store |
| `dpapi` | `encrypted-file` | `fallback-only` | native backend not implemented; encrypted-file fallback is used |
| `keychain` | `encrypted-file` | `fallback-only` | native backend not implemented; encrypted-file fallback is used |
| `keystore` | `encrypted-file` | `fallback-only` | native backend not implemented; encrypted-file fallback is used |
| `auto` | `encrypted-file` | `fallback-only` | resolves to encrypted-file while no native backend is implemented |
| unknown backend | `env` | `unsupported` | request is unrecognized; Zig falls back to `env` and reports the reason |

The `secrets.store.status` receipt now makes these states machine-readable through:

- `requestedRecognized`
- `requestedSupport`
- `fallbackApplied`
- `fallbackReason`

## Gateway Auth and Rate-Limit Posture

The hosted security gate now locks gateway posture under three explicit configurations:

| Posture | Expected audit/doctor outcome |
| --- | --- |
| public bind + configured token + valid rate limit | pass |
| public bind + missing token + disabled rate limit | fail/warn |
| enabled rate limit with zero thresholds | fail |

The local source of truth for this lane is now covered directly in:

- `src/security/audit.zig`
- `src/gateway/dispatcher.zig`

## CLI Entry Points

```powershell
zig build run -- --doctor
zig build run -- --security-audit --deep
zig build run -- --security-audit --deep --fix
```

## Remediation Behavior

The fix path can:

- create required security directories/files
- write default policy bundle where missing
- return structured action results and failures
- report `fix.complete=false` with `fix.unresolved[]` when an operator must still change runtime-state or policy-bundle config
- keep `system.maintenance.run` honest with `completed_with_manual_action` / `counts.partial` when only manual blockers remain

## Performance Notes

- Docker binary availability probe is cached process-locally in doctor/audit paths to avoid repeated process spawn overhead.
