# Demo — PSIRT Remediation as Code with Ansible + Cisco Catalyst Center

**Repository:** https://github.com/imanassypov/ansible-psirt-swim-demo

A self-contained Infrastructure-as-Code demo that shows how a PSIRT advisory is
remediated across a fleet of Cisco Catalyst 9000 switches **without anyone
touching a device CLI**.

Everything — which image, which site, which device role, which upgrade mode — is
declared once in a JSON data model. Ansible playbooks translate that declaration
into Catalyst Center SWIM (Software Image Management) API calls, and write a JSON
evidence file for every stage so the change is auditable after the fact.

> Extracted from a larger Campus BGP EVPN VXLAN CI/CD pipeline. Only the SWIM
> stages and the data model they consume were carried over. No credentials,
> vault files, or lab-specific device inventories came with it.

---

## Table of Contents

1. [The Story This Demo Tells](#the-story-this-demo-tells)
2. [What It Does](#what-it-does)
3. [Architecture](#architecture)
4. [Prerequisites](#prerequisites)
5. [Directory Structure](#directory-structure)
6. [Installation](#installation)
7. [Configuration](#configuration)
8. [The Data Model](#the-data-model)
9. [Running the Demo](#running-the-demo)
10. [GitHub Actions (settings.json trigger)](#github-actions-settingsjson-trigger)
11. [How Each Stage Works](#how-each-stage-works)
12. [Evidence Files](#evidence-files)
13. [Rollback](#rollback)
14. [Debug Mode](#debug-mode)
15. [Troubleshooting](#troubleshooting)
16. [Security Notes](#security-notes)
17. [Documentation Maintenance](#documentation-maintenance)

---

## The Story This Demo Tells

| Manual PSIRT response | This demo |
|---|---|
| Read advisory, hand-build a device list | Device family + role + site declared in `settings.json` |
| Upload image through the CatC GUI, per image | Image pulled by URL from an nginx server stood up by Ansible |
| Click "Golden Tag" per family/site | Declarative — tagging is derived from the data model |
| Distribute and activate device-by-device | One playbook per phase, scoped by site and role |
| Screenshot the result for the audit trail | Machine-readable JSON evidence file per stage, timestamped |
| Rollback is a scramble | A guarded, pre-declared rollback image and playbook |

The point of the demo: **the advisory response becomes a code change**
(one line in `settings.json`), reviewable and repeatable.

---

## What It Does

| Stage | Playbook | Disruptive? | Purpose |
|---|---|---|---|
| 00.1 | `00.1_swim_deploy_image_server.yml` | No | Stands up nginx on an Ubuntu host and stages the `.bin` images so CatC can pull them by URL. |
| 00.2 | `00.2_swim_validate_compliance.yml` | No | Pre-upgrade IMAGE compliance baseline (default). With `-e post_activate=true`, polls CatC reachability then runs post-activation check and prints a combined pre/post report. |
| 01.1 | `01.1_swim_import_and_tag.yml` | No | Imports the upgrade + rollback images into the CatC repository and marks the upgrade image **Golden**. |
| 01.2 | `01.2_swim_distribute.yml` | No | Copies the golden image to each device's flash. Run ahead of the window. |
| 01.3 | `01.3_swim_activate.yml` | **YES — reloads devices** | Activates the golden image. Maintenance window only. |
| 02.1 | `02.1_swim_rollback.yml` | **YES — reloads devices** | Emergency recovery: re-tags and activates the previous image. Double-gated. |

---

## Architecture

```
                     Settings/settings.json
                    (single source of truth)
                              │
                              │ read by every stage
                              ▼
   ┌──────────────────────────────────────────────────────┐
   │  Ansible control node (your laptop)                  │
   │                                                      │
   │  roles/http_image_server ──rsync──►  Ubuntu host      │
   │                                      nginx :80        │
   │                                      /var/www/html/   │
   │                                        images/*.bin   │
   │                                                      │
   │  roles/swim ──cisco.catalystcenter──►  Catalyst Center│
   └──────────────────────────────────────────────────────┘
                                                │
                                    HTTP GET the .bin
                                                ▼
                                        Catalyst Center
                                     SWIM image repository
                                                │
                                  distribute / activate
                                                ▼
                                   Catalyst 9000 switches
                                    (scoped by site + role)
```

Note the image transfer direction: **Catalyst Center pulls from nginx.** Stage
00.1 exists purely so 01.1 can import by URL instead of a browser upload.

---

## Prerequisites

| Requirement | Version / detail |
|---|---|
| Python | 3.9+ on the control node |
| `ansible-core` | `>=2.17,<2.18` (see `requirements-ansible.txt`) |
| `catalystcentersdk` | Python SDK required by the `cisco.catalystcenter` collection (installed via `requirements-ansible.txt`) |
| `cisco.catalystcenter` collection | `2.9.0` |
| `community.general` collection | `>=8.0.0,<11.0.0` (provides `ufw`) |
| Cisco Catalyst Center | 2.3.7.9 (API version pinned in `connection.yml`) |
| Image server | Ubuntu host reachable from **both** the control node (SSH) and Catalyst Center (HTTP/80) |
| `sshpass` | Only if using SSH **password** auth to the image server (`brew install sshpass`) |
| `rsync` | On control node and image server |
| Target devices | Discovered in CatC and **assigned to the site** named in `settings.json` |

> The device-to-site assignment is a hard prerequisite. SWIM targets devices by
> site + family + role, not by IP address. If a device is not assigned to the
> site, it is silently out of scope.

---

## Directory Structure

```
ansible-psirt-swim-demo/
├── .envrc                              # direnv — auto-start Actions runner (non-blocking)
├── .github/workflows/
│   └── swim-settings-trigger.yml       # CI: settings.json → SWIM pipeline → reports/
├── scripts/
│   ├── check-readme-sync.sh            # validates README matches repo structure
│   ├── collect-swim-reports.sh         # copies evidence JSON into reports/
│   ├── sanitize-report-artifacts.py    # redacts paths/IPs/site names before commit
│   ├── verify-report-artifacts.sh      # fails if forbidden patterns remain in reports/
│   ├── install-git-hooks.sh            # installs pre-commit README sync hook
│   ├── render-swim-report.py           # builds REPORT.md from compliance evidence
│   ├── setup-actions-runner.sh         # installs .github/actions-runner/ (gitignored)
│   ├── fix-runner-workdir.sh           # move _work out of paths with spaces
│   ├── ensure-actions-runner.sh        # start runner if not already running
│   └── ci/                             # workflow scripts (prepare, run, commit)
│       ├── commit-reports.sh           # verify + commit sanitized reports/<run>/
│       ├── prepare-job.sh
│       ├── run-swim-pipeline.sh
│       └── lib/log.sh                  # redacts local paths from CI log output
├── .cursor/
│   ├── rules/readme-sync.mdc           # agent policy — keep README current
│   └── hooks.json                      # stop hook prompts README updates
├── .githooks/pre-commit                # blocks commits when README is stale
├── .gitignore                          # blocks vault files, logs, .vault_pass
├── .vault_pass                         # ansible-vault password (NOT committed)
├── requirements-ansible.txt            # pip requirements for the control node
├── README.md                           # this file
│
├── Settings/
│   ├── settings.json                   # ★ THE DATA MODEL — the only file you edit for a demo
│   └── readme.md                       # field-by-field schema reference
│
├── reports/                            # CI-generated, sanitized evidence + REPORT.md (auto-committed)
│   └── README.md
│
└── ansible/
    ├── ansible.cfg                     # inventory path, roles path, vault password file
    ├── collections/
    │   └── requirements.yml            # ansible-galaxy collection pins
    │
    ├── inventory/
    │   ├── static_inventory.yml        # groups: catalyst_center, image_servers
    │   └── group_vars/
    │       ├── catalyst_center/
    │       │   ├── connection.yml      # CatC host/port/version, timeouts, settings_json_path
    │       │   ├── vault.yml.example   # → copy to vault.yml, then ansible-vault encrypt
    │       │   └── vault.yml           # (you create — CatC username/password, gitignored)
    │       └── image_servers/
    │           ├── connection.yml      # SSH/become vars sourced from vault.yml
    │           ├── vars.yml.example    # → copy to vars.yml (image_server_ip, image paths)
    │           ├── vars.yml            # (you create — gitignored)
    │           ├── vault.yml.example   # → copy to vault.yml, then ansible-vault encrypt
    │           └── vault.yml           # (you create — SSH/become creds, gitignored)
    │
    ├── playbooks/
    │   ├── 00.1_swim_deploy_image_server.yml
    │   ├── 00.2_swim_validate_compliance.yml
    │   ├── 01.1_swim_import_and_tag.yml
    │   ├── 01.2_swim_distribute.yml
    │   ├── 01.3_swim_activate.yml
    │   └── 02.1_swim_rollback.yml
    │
    ├── roles/
    │   ├── swim/tasks/
    │   │   ├── main.yml                # dispatcher — include_tasks "{{ swim_action }}.yml"
    │   │   ├── load_swim_details.yml   # ★ reads settings.json → synthesises swim_details
    │   │   ├── validate_compliance.yml   # pre-upgrade + post-activate compliance modes
    │   │   ├── wait_for_site_reachability.yml  # post-activate: poll until devices Reachable
    │   │   ├── poll_site_reachability_once.yml
    │   │   ├── assess_site_reachability.yml    # per-site device reachability (dedicated loop_var)
    │   │   ├── build_compliance_site_reports.yml
    │   │   ├── preflight.yml           # alias → validate_compliance.yml
    │   │   ├── import_and_tag.yml      # remote-URL import + golden tag
    │   │   ├── distribute.yml          # push image to device flash
    │   │   ├── activate.yml            # activate + reload
    │   │   ├── rollback.yml            # re-tag + activate previous image (double-gated)
    │   │   └── write_evidence.yml      # dumps per-stage JSON into logs/
    │   │
    │   └── http_image_server/          # nginx + image staging (stage 00.1)
    │       ├── defaults/main.yml       # web root, url subdir, rsync retry tuning, manage_ufw
    │       ├── tasks/{preflight,install_nginx,stage_images,configure_nginx,configure_firewall,verify}.yml
    │       ├── templates/swim-images.conf.j2
    │       ├── handlers/main.yml
    │       └── meta/main.yml
    │
    ├── docs/swim/                      # sequence diagrams + module coverage graphics
    └── logs/                           # evidence files land here (gitignored)
```

---

## Installation

```bash
cd ansible-psirt-swim-demo

# 1. Python venv + ansible-core
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-ansible.txt

# 2. Ansible collections
cd ansible
ansible-galaxy collection install -r collections/requirements.yml

# 3. Vault password file (used by ansible.cfg → vault_password_file = ../.vault_pass)
cd ..
printf 'choose-a-strong-passphrase' > .vault_pass
chmod 600 .vault_pass
```

### Create the secret files

```bash
cd ansible/inventory/group_vars/catalyst_center
cp vault.yml.example vault.yml
$EDITOR vault.yml                # set catc_username / catc_password
ansible-vault encrypt vault.yml

cd ../image_servers
cp vars.yml.example vars.yml
$EDITOR vars.yml                 # set image_server_ip + image_local_paths
cp vault.yml.example vault.yml
$EDITOR vault.yml                # set SSH user / password / become password
ansible-vault encrypt vault.yml
```

All four created files are gitignored.

### Enable README sync checks (recommended)

After cloning, install the git pre-commit hook once so commits fail when
playbooks, roles, settings, or inventory change without a matching `README.md`
update:

```bash
./scripts/install-git-hooks.sh
./scripts/check-readme-sync.sh
```

Cursor agents in this repo also load `.cursor/rules/readme-sync.mdc` and a
`stop` hook that prompts for README updates before finishing a task.

---

## Configuration

### `inventory/group_vars/catalyst_center/connection.yml`

| Variable | Default | Description |
|---|---|---|
| `catalystcenter_host` | `198.18.129.100` | Catalyst Center address |
| `catalystcenter_port` | `443` | HTTPS port |
| `catalystcenter_version` | `2.3.7.9` | API version the collection targets |
| `catalystcenter_verify` | `false` | TLS verification (self-signed lab certs) |
| `catalystcenter_log_file_path` | `../logs/catc-swim.log` | Collection-level API log |
| `catalystcenter_api_task_timeout` | `3600` | Max wait for distribute/activate tasks (seconds) |
| `catalystcenter_task_poll_interval` | `30` | Poll interval while a CatC task runs (seconds) |
| `catc_debug` | `false` | Verbose task output from the `swim` role |
| `settings_json_path` | `../../Settings/settings.json` | Path to the data model, relative to `playbooks/` |

### `inventory/group_vars/image_servers/vars.yml`

| Variable | Description |
|---|---|
| `image_server_ip` | Address Catalyst Center will fetch images from. Must match the host portion of `swim.image_server_base_url`. |
| `image_local_paths[]` | Absolute paths to the `.bin` files **on the control node**. rsync'd to the image server. |

### `roles/http_image_server/defaults/main.yml`

| Variable | Default | Description |
|---|---|---|
| `image_web_root` | `/var/www/html` | nginx document root |
| `image_url_subdir` | `images` | URL path segment → `http://<ip>/images/<file>.bin` |
| `image_rsync_retries` | `30` | Resume attempts — important over low-MTU VPN links |
| `image_rsync_delay` | `5` | Seconds between retries |
| `image_rsync_timeout` | `60` | Per-attempt rsync I/O timeout |
| `manage_ufw` | `true` | Open TCP/80 when ufw is installed and active |

> **The URL must line up exactly.**
> `http://{{ image_server_ip }}/{{ image_url_subdir }}/<image>` must equal
> `swim.image_server_base_url + "/" + swim.upgrade_image`. A mismatch surfaces
> as an import failure in 01.1, not in 00.1.

---

## The Data Model

`Settings/settings.json` is the only file you edit to change what the demo does.

```json
{
  "project": [
    {
      "HierarchyParent": "Global/PODS",
      "HierarchyArea":   "POD 0",
      "HierarchyBldg":   "Building P0",
      "HierarchyFloor":  "Floor 1",
      "swim": {
        "image_server_base_url":    "http://198.18.134.28/images",
        "device_family_identifier": "Cisco Catalyst 9000 UADP 8 Port Virtual Switch",
        "device_family_name":       "Switches and Hubs",
        "device_series_name":       "Cisco Catalyst 9000 Series Virtual Switches",
        "device_role":              "ALL",
        "upgrade_image":            "cat9kv-universalk9.BLD_V262_THROTTLE_LATEST_20260529_003538.SSA.bin",
        "rollback_image":           "cat9kv-universalk9.17.15.03.SPA.bin",
        "activation": {
          "device_upgrade_mode":  "install",
          "distribute_if_needed": true,
          "schedule_validate":    false,
          "image_activation_timeout":   3600,
          "image_distribution_timeout": 3600,
          "wait_for_reachability":      true,
          "reachability_poll_interval": 60,
          "reachability_poll_timeout":  600
        }
      }
    }
  ]
}
```

Full field reference: [`Settings/readme.md`](Settings/readme.md).

### The PSIRT moment

Responding to an advisory is a **one-line diff** (swap `upgrade_image` to the PSIRT-remediating build, for example `cat9kv-universalk9.BLD_V262_THROTTLE_LATEST_20260529_003538.SSA.bin`):

```diff
-        "upgrade_image": "cat9kv-universalk9.17.15.03.SPA.bin",
+        "upgrade_image": "cat9kv-universalk9.BLD_V262_THROTTLE_LATEST_20260529_003538.SSA.bin",
```

Commit it, run 00.1 → 01.3, then `00.2 -e post_activate=true`, and the fleet is remediated with evidence attached.

### Narrowing the blast radius

`device_role` scopes the change. Start with a pilot, then widen:

```jsonc
"device_role": "ACCESS"    // ALL | CORE | DISTRIBUTION | ACCESS | BORDER ROUTER
```

Multiple sites? Add more `project[]` entries. Images are de-duplicated across
entries, so a shared `.bin` is imported into CatC only once.

---

## Running the Demo

```bash
cd ansible
source ../.venv/bin/activate

# --- Prep (run once, or whenever the image changes) --------------------------
ansible-playbook playbooks/00.1_swim_deploy_image_server.yml

# --- Non-disruptive, safe to run live in front of an audience ----------------
ansible-playbook playbooks/00.2_swim_validate_compliance.yml         # baseline: NON_COMPLIANT
ansible-playbook playbooks/01.1_swim_import_and_tag.yml    # import + golden tag
ansible-playbook playbooks/01.2_swim_distribute.yml        # stage to flash

# --- Maintenance window only — RELOADS DEVICES ------------------------------
ansible-playbook playbooks/01.3_swim_activate.yml

# --- Prove it (post-activation; auto-loads pre-upgrade baseline from logs/) ---
ansible-playbook playbooks/00.2_swim_validate_compliance.yml -e post_activate=true
```

### Useful overrides

```bash
# Override image paths without editing vars.yml
ansible-playbook playbooks/00.1_swim_deploy_image_server.yml \
  -e '{"image_local_paths":["../images/a.SSA.bin","../images/b.SPA.bin"]}'

# Point at a different data model
ansible-playbook playbooks/01.1_swim_import_and_tag.yml \
  -e settings_json_path=../../Settings/alternate-settings.json

# Pin a specific pre-upgrade baseline when several exist in logs/
ansible-playbook playbooks/00.2_swim_validate_compliance.yml \
  -e post_activate=true -e preflight_run_id=20260814-140000

# Verbose role output for a live walkthrough
ansible-playbook playbooks/00.2_swim_validate_compliance.yml -e catc_debug=true
```

### Suggested live-demo flow

| # | Show | Why it lands |
|---|---|---|
| 1 | `Settings/settings.json` side by side with the PSIRT advisory | The advisory maps to one field |
| 2 | `00.2` output — IMAGE compliance `NON_COMPLIANT` | Establishes the "before" |
| 3 | The one-line `upgrade_image` diff in git | The change *is* the code review |
| 4 | `01.1` + Catalyst Center UI showing the Golden tag appear | Declared intent → API reality |
| 5 | `01.2` (non-disruptive) then `01.3` (the reload) | Separation of staging and risk |
| 6 | `00.2 -e post_activate=true` — combined pre/post report + evidence in `logs/` | Auditable outcome, not a screenshot |

---

## GitHub Actions (settings.json trigger)

When `Settings/settings.json` changes on `main` or `master`, the
[SWIM PSIRT Pipeline](.github/workflows/swim-settings-trigger.yml) workflow runs
automatically (or on demand via **Actions → SWIM PSIRT Pipeline → Run workflow**).

### Pipeline sequence

| Step | Playbook | Purpose |
|---|---|---|
| 1 | `00.2_swim_validate_compliance.yml` | Pre-upgrade IMAGE compliance baseline |
| 2 | `01.1_swim_import_and_tag.yml` | Import images + golden tag |
| 3 | `01.2_swim_distribute.yml` | Stage image to device flash |
| 4 | `01.3_swim_activate.yml` | Activate (reloads devices) |
| 5 | `00.2_swim_validate_compliance.yml -e post_activate=true` | Post-activation check + pre/post report |

Evidence JSON from `ansible/logs/` is copied into `reports/<run-number>-<run-id>/`,
sanitized (local paths, lab IPs, site names, device UUIDs), verified, and
auto-committed by CI. See [`reports/README.md`](reports/README.md).

### Self-hosted runner setup

The workflow uses `runs-on: self-hosted` because Catalyst Center and the lab
network are private (`198.18.x`). The runner must live on a host that can reach
CatC over HTTPS and run Ansible.

#### 1. Install and register the runner

From the repository root:

```bash
./scripts/setup-actions-runner.sh --start-service
```

This downloads the GitHub Actions runner into `.github/actions-runner/` (gitignored)
and registers it with the repository. Verify it under **Settings → Actions →
Runners** in GitHub.

Manual start (when not using direnv):

```bash
cd .github/actions-runner && ./run.sh
```

Or as a background process:

```bash
cd .github/actions-runner && nohup ./run.sh >> runner-console.log 2>&1 &
```

> **macOS note:** If the repository is under macOS `Documents`, launchd
> (`./svc.sh`) is often blocked by privacy controls. The setup script falls back
> to `./run.sh` in the background. For an always-on service, keep the repo outside
> `Documents` or grant Full Disk Access to the runner binary.

#### 2. Auto-start with direnv

The runner process exits on logout or reboot. This repo ships a `.envrc` that
starts it automatically when you enter the directory — without blocking your
shell (direnv waits for `.envrc` to finish, so the runner is launched in a
detached background subshell).

**Prerequisites**

| Requirement | Notes |
|---|---|
| [direnv](https://direnv.net/) | `brew install direnv` |
| direnv shell hook | Add `eval "$(direnv hook zsh)"` to your shell rc file (once, per [direnv docs](https://direnv.net/docs/hook.html)) |
| Runner installed | `./scripts/setup-actions-runner.sh` (step 1) |

**One-time allow** (from the repository root, after cloning or whenever
`.envrc` changes):

```bash
direnv allow
```

On every `cd` into the repo, direnv loads `.envrc`, which calls
`scripts/ensure-actions-runner.sh --quiet`. That script is a no-op when
`Runner.Listener` is already running.

Re-allow after editing `.envrc`:

```bash
direnv allow
```

**What `.envrc` does**

```bash
# Non-blocking — direnv must not wait on the runner process.
if [[ -x scripts/ensure-actions-runner.sh ]]; then
  ( scripts/ensure-actions-runner.sh --quiet </dev/null >/dev/null 2>&1 & )
fi
```

**Verify**

```bash
pgrep -fl Runner.Listener
tail -f .github/actions-runner/runner-console.log
```

#### 3. Paths with spaces (required for this demo layout)

If the repository path contains spaces, GitHub Actions `run:` steps fail with:

```
bash: .../Speaking: No such file or directory
```

The runner invokes temp scripts as `bash -e {0}`; an unquoted `{0}` under a
spaced path breaks every step. Fix once from the repository root:

```bash
./scripts/fix-runner-workdir.sh --restart
```

This moves job checkouts to `~/gh-actions-work/` (no spaces) and writes
`SWIM_LAB_ROOT` to `.github/actions-runner/.env` so CI can still link your
local `.venv` and `vault.yml`.

#### 4. How the job workspace relates to your lab files

CI runs **directly in your lab repository** (`SWIM_LAB_ROOT` from
`.github/actions-runner/.env`). It does **not** use `actions/checkout`, so job
logs never print your local workspace path. The prepare step runs
`git fetch` + `git checkout` of the triggering commit in place.

Gitignored lab files (`.venv/`, `.vault_pass`, `vault.yml`) are already on disk —
no linking step is required.

**Log redaction:** all CI scripts source `scripts/ci/lib/log.sh`, which replaces
local paths with placeholders (`<lab-root>`, `<home>`, `<workspace>`) before
writing to stdout/stderr. Ansible playbook output is piped through the same
filter. Evidence JSON redacts paths via the swim role's `write_evidence.yml`.
Before reports are committed, `sanitize-report-artifacts.py` replaces lab IPs,
site hierarchy names, and UUIDs with generic placeholders; `verify-report-artifacts.sh`
blocks the commit if forbidden patterns remain.

If the prepare step fails, complete [Installation](#installation) and run
`./scripts/fix-runner-workdir.sh --restart`.

#### 5. GitHub secrets

GitHub secrets are **not required** when the workflow reuses your local
`.vault_pass` and encrypted `vault.yml`. They were only needed by the earlier
workflow design that rebuilt vault from secrets on every run.

Optional: keep secrets if you later move to a runner machine that does not
share the parent repo's lab files.

| Secret | When needed |
|---|---|
| `ANSIBLE_VAULT_PASSWORD` | Only if vault is rebuilt from secrets (not used with lab link) |
| `CATC_USERNAME` | Same |
| `CATC_PASSWORD` | Same |

> **Note:** Stage 01.3 reloads devices. Treat every `settings.json` push to the
> default branch as a production change unless you disable or gate the workflow.

---

## How Each Stage Works

Playbooks 00.2, 01.1–01.3, and 02.1 target the `catalyst_center` group with `connection: local`,
loads `vault.yml`, sets a per-run `swim_run_id` timestamp, and imports the `swim`
role with a specific `tasks_from`.

### `load_swim_details.yml` — the translation layer

Imported at the top of every stage. It:

1. Resolves `settings_json_path` to an absolute path.
2. Loads and validates `settings.json` (asserts a non-empty `project` list, and
   that every entry has `swim.image_server_base_url` and `swim.upgrade_image`).
3. Builds `site_name` by joining the four `Hierarchy*` fields with `/`, skipping
   empty segments — identical to how the site-hierarchy stage builds it.
4. Flattens each project entry into a `_swim_records` item.
5. Synthesises `swim_details`, the structure the stages loop over:

| Key | Consumed by | Contents |
|---|---|---|
| `import_images[]` | 01.1 | Remote-URL import payloads (de-duplicated) |
| `golden_tag_images[]` | 01.1, 00.2 | `tagging_details{image_name, device_role, device_image_family_name, site_name}` |
| `distribute_images[]` | 01.2 | `image_distribution_details{...}` |
| `activate_images[]` | 01.3 | `image_activation_details{...}` |
| `rollback_images.tag[]` / `.activate[]` | 02.1 | Previous-image re-tag + activation |

Nothing downstream reads `settings.json` directly — this is the single
translation point from data model to API payload.

### Stage detail

| Stage | Module / action | Notes |
|---|---|---|
| 00.1 | `apt`, `template`, `command` (rsync), `community.general.ufw`, `uri` | Verifies each image with an HTTP HEAD expecting `200` + `application/octet-stream` |
| 00.2 | `network_compliance_workflow_manager` | Default: pre-upgrade baseline → `00_preflight.json`. `-e post_activate=true`: reachability poll, post check + combined pre/post report. |
| 01.1 | `swim_workflow_manager` | Import by URL, then golden tag per family/role/site |
| 01.2 | `swim_workflow_manager` | Long-running — honours `image_distribution_timeout` from settings (default 3600s) |
| 01.3 | `swim_workflow_manager` | Honours `device_upgrade_mode`, `distribute_if_needed`, `schedule_validate`, `image_activation_timeout` |
| 02.1 | `swim_workflow_manager` | Re-tags `rollback_image` golden with `activate_lower_image_version: true`; honours `activation.*` like stage 01.3 |

---

## Evidence Files

Every stage writes a JSON artifact to `ansible/logs/`, prefixed with the run's
`swim_run_id` (`YYYYmmdd-HHMMSS`) so one upgrade window's artifacts group
together:

| File | Stage |
|---|---|
| `<run_id>-00_preflight.json` | 00.2 (default) |
| `<run_id>-00_post_activate.json` | 00.2 (`-e post_activate=true`) |
| `<run_id>-00_compliance_pre_post.json` | 00.2 (`-e post_activate=true`) |
| `<run_id>-10_import_and_tag.json` | 01.1 |
| `<run_id>-20_distribute.json` | 01.2 |
| `<run_id>-30_activate.json` | 01.3 |
| `<run_id>-35_rollback.json` | 02.1 |

The `00_compliance_pre_post.json` summary and the combined console report are the
change record — this is the part that usually replaces a manual screenshot in a
change ticket.

---

## Rollback

Stage 02.1 reloads devices a second time, so it is guarded by two explicit
confirmation gates that the role asserts before doing anything:

```bash
ansible-playbook playbooks/02.1_swim_rollback.yml \
  -e rollback_confirm=YES \
  -e rollback_reload_ack=RELOAD_OK
```

Without both, the play fails immediately — a wildcard playbook glob can never
trigger it by accident.

**Prerequisite:** `rollback_image` must already exist in the Catalyst Center
repository. Stage 01.1 imports it alongside `upgrade_image` for exactly this
reason — do not skip 01.1 on the assumption that only the new image matters.

---

## Debug Mode

```bash
ansible-playbook playbooks/00.2_swim_validate_compliance.yml -e catc_debug=true
```

| Setting | Effect |
|---|---|
| `catc_debug: true` | Prints `_resolved_json_path` and the full synthesised `swim_details` |
| `catalystcenter_debug: true` | Verbose output from the collection modules |
| `catalystcenter_log_level: DEBUG` | Full API request/response trace to `logs/catc-swim.log` |
| `-vvv` | Ansible task-level verbosity |

---

## Troubleshooting

| Symptom | Likely cause | Resolution |
|---|---|---|
| `settings.json must contain a non-empty 'project' list` | Wrong `settings_json_path`, or malformed JSON | Run with `-e catc_debug=true` and check `_resolved_json_path`; validate with `python3 -m json.tool Settings/settings.json` |
| Each project entry must define a `swim` block | Missing `image_server_base_url` or `upgrade_image` | Add both to every `project[]` entry — SWIM validates all entries, not just the first |
| 00.1 HTTP HEAD verification fails | nginx not serving, ufw blocking, or image not staged | `curl -I http://<image_server_ip>/images/<file>.bin` from the control node |
| 01.1 import fails / times out | Catalyst Center cannot reach the image server | Confirm CatC → image server TCP/80 reachability; the URL must be resolvable *from CatC*, not from your laptop |
| Golden tag applied but 01.2 finds no devices | Devices not assigned to the site, or `device_role` too narrow | Verify site assignment in CatC inventory; try `device_role: "ALL"` |
| 01.2 / 01.3 times out | Large image, slow link, or slow device reload | Raise `activation.image_distribution_timeout` / `activation.image_activation_timeout` in `settings.json` (default 3600s each). On CatC ≤ 2.3.7.9, also raise `catalystcenter_api_task_timeout` in `connection.yml`. |
| `sshpass: command not found` in 00.1 | Password SSH auth without sshpass | `brew install sshpass`, or switch the image server to SSH keys and drop `ansible_ssh_pass` |
| `Attempting to decrypt but no vault secrets found` | `.vault_pass` missing or unreadable | Recreate it at the repo root; `ansible.cfg` points at `../.vault_pass` |
| rsync restarts repeatedly in 00.1 | Low-MTU VPN path | Expected — the role retries with resume. Tune `image_rsync_retries` / `image_rsync_timeout`. |
| Post-activation 00.2 still reports `NON_COMPLIANT` or skips devices | Devices not fully back online after reload | Post-activate mode polls reachability first (`activation.wait_for_reachability`, default true). Raise `reachability_poll_timeout` (default 600s) or `reachability_poll_interval` (default 60s), or re-run with `-e post_activate=true` after inventory settles. |
| Post-activate reachability poll keeps waiting but UI shows green | Poll previously required `collectionStatus` Managed/In Progress; API often reports `Partial Collection Failure` while Reachable | Poll gates on `reachabilityStatus=Reachable` only. Compliance may still skip devices until collection completes. |
| Reachability poll fails on `sites_info` unsupported params | CatC info modules do not accept `catalystcenter_log*` kwargs | Fixed in reachability tasks — info modules use connection params only. |
| Post-activate reachability poll timed out | Devices still reloading or API reports Unreachable | Check Catalyst Center inventory; increase `activation.reachability_poll_timeout`. Poll attempt count is timeout ÷ interval. |
| `No pre-upgrade baseline found in logs/` | post_activate run before a default 00.2 | Run 00.2 without extra-vars first, or pass `-e preflight_run_id=<run_id>` |

---

## Security Notes

- **No secrets are committed.** `vault.yml`, `vars.yml`, `.vault_pass` and
  `.env` are all gitignored. Only `*.example` templates are tracked.
- `settings.json` here is deliberately trimmed to the hierarchy and `swim`
  blocks. The upstream pipeline's `network_settings` and `device_credentials`
  sections — which carry a RADIUS shared secret and CLI passwords — were **not**
  copied.
- `catalystcenter_verify: false` is appropriate for a self-signed lab
  controller. Set it to `true` and trust the CA before using this against
  anything production.
- Stages 01.3 and 02.1 reload devices. 02.1 is double-gated; 01.3 deliberately
  is not, because it is the intended outcome of the pipeline — schedule it.

---

## Documentation Maintenance

`README.md` must stay aligned with the repo. When you change playbooks, roles,
`Settings/`, inventory, or collection pins, update the relevant README sections
in the same change:

| Change type | README sections to review |
|---|---|
| Playbook add/rename/remove | What It Does, Directory Structure, Running the Demo, How Each Stage Works, Evidence Files, Troubleshooting |
| Role or stage behavior | How Each Stage Works, Evidence Files, Troubleshooting |
| `settings.json` schema | The Data Model, Configuration, link to `Settings/readme.md` |
| Inventory or prerequisites | Prerequisites, Configuration, Installation |

Validation:

```bash
./scripts/check-readme-sync.sh          # working tree
./scripts/check-readme-sync.sh --staged # staged files only (pre-commit)
```

The pre-commit hook (via `./scripts/install-git-hooks.sh`) enforces this on
commit. Cursor uses `.cursor/rules/readme-sync.mdc` plus a `stop` hook for the
same policy during agent sessions.
