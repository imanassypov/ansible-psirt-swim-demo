# SWIM Pipeline Reports

Evidence and summaries from the **SWIM PSIRT Pipeline** GitHub Actions workflow
(triggered when `Settings/settings.json` at the repo root changes).

Each successful run adds one subdirectory named `{run-number}-{run-id}/`. Only the
latest run is kept on `master`; older run folders are removed on the next commit.

## Run folder contents

- REPORT.md — compliance summary with links to evidence JSON in the same folder
- manifest.json — index of evidence files
- preflight, import, distribute, activate, post-activate, and pre/post compliance JSON evidence files

## Pipeline flow

1. Playbooks write evidence to `ansible/logs/` (gitignored).
2. collect-swim-reports.sh copies artifacts into the run subdirectory under reports/.
3. sanitize-report-artifacts.py redacts local paths, lab IPs, site names, and UUIDs.
4. verify-report-artifacts.sh blocks forbidden patterns before commit.
5. commit-reports.sh commits the current run and removes older run folders.
