# SWIM Pipeline Reports

This directory holds evidence and summaries produced when
[`Settings/settings.json`](../Settings/settings.json) changes and the GitHub Actions
**SWIM PSIRT Pipeline** workflow runs.

Each workflow run creates a subdirectory named `<run-number>-<run-id>/` containing:

| File | Description |
|---|---|
| `REPORT.md` | Human-readable compliance summary: site rollup plus pre/post device tables (status, configured, intended, outcome) |
| `manifest.json` | Index of evidence files in the run |
| `*-00_preflight.json` | Pre-upgrade IMAGE compliance baseline |
| `*-00_post_activate.json` | Post-activation compliance check |
| `*-00_compliance_pre_post.json` | Combined pre/post compliance summary |
| `*-10_import_and_tag.json` | Import + golden tag evidence |
| `*-20_distribute.json` | Distribution evidence |
| `*-30_activate.json` | Activation evidence |

Run output is written here by the workflow (`collect-swim-reports.sh`) after
each pipeline run. Before commit, artifacts are **sanitized** (local paths,
lab IPs, site hierarchy names, device UUIDs) and verified by
`verify-report-artifacts.sh`.

Successful runs are **auto-committed** to this repo (`commit-reports.sh`) as
`reports/<run-number>-<run-id>/`. Source evidence JSON is written first to
`ansible/logs/` (gitignored), then copied here for audit-friendly summaries.
