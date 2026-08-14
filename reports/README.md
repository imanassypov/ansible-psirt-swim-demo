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

Run output is written here by the workflow (`collect-swim-reports.sh`) but is
**gitignored** — only this README is tracked. Raw runtime logs remain in
`ansible/logs/` (also gitignored).
