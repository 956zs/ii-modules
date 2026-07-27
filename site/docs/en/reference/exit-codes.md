---
description: The iimod CLI's stable exit code contract, suitable for scripting and issue reports.
---

# Exit codes

`iimod`'s exit codes are a **stable contract** (stable API), suitable for scripting and issue reports.

| Exit code | Meaning |
| --- | --- |
| `0` | Success |
| `3` | Validation failure (manifest, layout, capabilities lint) |
| `4` | Probe failure (compatibility mismatch, **absolute block**) |
| `5` | Dependency or conflict |
| `6` | Integrity (sha256 mismatch, file never written) |
| `7` | State error |
| `8` | Anchor failure (Tier B patch location not found) |
| `9` | Tier B requires `--allow-patches` |
| `10` | Protocol version unsupported (`protocolVersion` out of the tool's range) |

## Common scenarios

- **exit 4**: dots-hyprland changed the API surface a module depends on. Wait for the module author to ship a compatible new version, or file an issue.
- **exit 6**: the downloaded content doesn't match the sha256 declared in index.json — could be a tampered source or a publishing mistake. **Do not** bypass this.
- **exit 9**: this is a Tier B module — once you understand it will modify stock files, add `--allow-patches` and re-run.
