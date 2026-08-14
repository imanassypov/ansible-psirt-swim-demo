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
10. [How Each Stage Works](#how-each-stage-works)
11. [Evidence Files](#evidence-files)
12. [Rollback](#rollback)
13. [Debug Mode](#debug-mode)
14. [Troubleshooting](#troubleshooting)
15. [Security Notes](#security-notes)
16. [Documentation Maintenance](#documentation-maintenance)

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
| 01 | `01_swim_deploy_http_image_server.yml` | No | Stands up nginx on an Ubuntu host and stages the `.bin` images so CatC can pull them by URL. |
| 02 | `02_swim_preflight.yml` | No | Resyncs inventory at each target site and captures the **pre-upgrade IMAGE compliance baseline**. |
| 03 | `03_swim_import_and_tag.yml` | No | Imports the upgrade + rollback images into the CatC repository and marks the upgrade image **Golden**. |
| 04 | `04_swim_distribute.yml` | No | Copies the golden image to each device's flash. Run ahead of the window. |
| 05 | `05_swim_activate.yml` | **YES — reloads devices** | Activates the golden image. Maintenance window only. |
| 06 | `06_swim_postcheck.yml` | No | Re-runs IMAGE compliance and proves the fleet is remediated. |
| 07 | `07_swim_rollback.yml` | **YES — reloads devices** | Emergency recovery: re-tags and activates the previous image. Double-gated. |

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
01 exists purely so 03 can import by URL instead of a browser upload.

---

## Prerequisites

| Requirement | Version / detail |
|---|---|
| Python | 3.9+ on the control node |
| `ansible-core` | `>=2.17,<2.18` (see `requirements-ansible.txt`) |
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
├── scripts/
│   ├── check-readme-sync.sh            # validates README matches repo structure
│   └── install-git-hooks.sh            # installs pre-commit README sync hook
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
    │   ├── 01_swim_deploy_http_image_server.yml
    │   ├── 02_swim_preflight.yml
    │   ├── 03_swim_import_and_tag.yml
    │   ├── 04_swim_distribute.yml
    │   ├── 05_swim_activate.yml
    │   ├── 06_swim_postcheck.yml
    │   └── 07_swim_rollback.yml
    │
    ├── roles/
    │   ├── swim/tasks/
    │   │   ├── main.yml                # dispatcher — include_tasks "{{ swim_action }}.yml"
    │   │   ├── load_swim_details.yml   # ★ reads settings.json → synthesises swim_details
    │   │   ├── preflight.yml           # inventory resync + IMAGE compliance baseline
    │   │   ├── import_and_tag.yml      # remote-URL import + golden tag
    │   │   ├── distribute.yml          # push image to device flash
    │   │   ├── activate.yml            # activate + reload
    │   │   ├── postcheck.yml           # IMAGE compliance verification
    │   │   ├── rollback.yml            # re-tag + activate previous image (double-gated)
    │   │   └── write_evidence.yml      # dumps per-stage JSON into logs/
    │   │
    │   └── http_image_server/          # nginx + image staging (stage 01)
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
> as an import failure in 03, not in 01.

---

## The Data Model

`Settings/settings.json` is the only file you edit to change what the demo does.

```jsonc
{
  "project": [
    {
      "HierarchyParent": "Global/PODS",   // ─┐ joined with "/" →
      "HierarchyArea":   "POD 0",         //  │ "Global/PODS/POD 0/
      "HierarchyBldg":   "Building P0",   //  │  Building P0/Floor 1"
      "HierarchyFloor":  "Floor 1",       // ─┘
      "swim": {
        "image_server_base_url":    "http://198.18.134.28/images",
        "device_family_identifier": "Cisco Catalyst 9000 UADP 8 Port Virtual Switch",
        "device_family_name":       "Switches and Hubs",
        "device_series_name":       "Cisco Catalyst 9000 Series Virtual Switches",
        "device_role":              "ALL",
        "upgrade_image":            "cat9kv-universalk9.BLD_V262_....SSA.bin",
        "rollback_image":           "cat9kv-universalk9.17.15.03.SPA.bin",
        "activation": {
          "device_upgrade_mode":  "install",
          "distribute_if_needed": true,
          "schedule_validate":    false
        }
      }
    }
  ]
}
```

Full field reference: [`Settings/readme.md`](Settings/readme.md).

### The PSIRT moment

Responding to an advisory is a **one-line diff**:

```diff
-        "upgrade_image": "cat9kv-universalk9.17.15.03.SPA.bin",
+        "upgrade_image": "cat9kv-universalk9.17.15.04a.SPA.bin",
```

Commit it, run 01 → 06, and the fleet is remediated with evidence attached.

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
ansible-playbook playbooks/01_swim_deploy_http_image_server.yml

# --- Non-disruptive, safe to run live in front of an audience ----------------
ansible-playbook playbooks/02_swim_preflight.yml         # baseline: NON_COMPLIANT
ansible-playbook playbooks/03_swim_import_and_tag.yml    # import + golden tag
ansible-playbook playbooks/04_swim_distribute.yml        # stage to flash

# --- Maintenance window only — RELOADS DEVICES ------------------------------
ansible-playbook playbooks/05_swim_activate.yml

# --- Prove it --------------------------------------------------------------
ansible-playbook playbooks/06_swim_postcheck.yml         # result: COMPLIANT
```

### Useful overrides

```bash
# Override image paths without editing vars.yml
ansible-playbook playbooks/01_swim_deploy_http_image_server.yml \
  -e '{"image_local_paths":["/abs/a.SSA.bin","/abs/b.SPA.bin"]}'

# Point at a different data model
ansible-playbook playbooks/03_swim_import_and_tag.yml \
  -e settings_json_path=/abs/path/alternate-settings.json

# Verbose role output for a live walkthrough
ansible-playbook playbooks/02_swim_preflight.yml -e catc_debug=true
```

### Suggested live-demo flow

| # | Show | Why it lands |
|---|---|---|
| 1 | `Settings/settings.json` side by side with the PSIRT advisory | The advisory maps to one field |
| 2 | `02` output — IMAGE compliance `NON_COMPLIANT` | Establishes the "before" |
| 3 | The one-line `upgrade_image` diff in git | The change *is* the code review |
| 4 | `03` + Catalyst Center UI showing the Golden tag appear | Declared intent → API reality |
| 5 | `04` (non-disruptive) then `05` (the reload) | Separation of staging and risk |
| 6 | `06` — `COMPLIANT`, plus the JSON evidence files in `logs/` | Auditable outcome, not a screenshot |

---

## How Each Stage Works

Every 01–07 playbook targets the `catalyst_center` group with `connection: local`,
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
| `import_images[]` | 03 | Remote-URL import payloads (de-duplicated) |
| `golden_tag_images[]` | 03, 02, 06 | `tagging_details{image_name, device_role, device_image_family_name, site_name}` |
| `distribute_images[]` | 04 | `image_distribution_details{...}` |
| `activate_images[]` | 05 | `image_activation_details{...}` |
| `rollback_images.tag[]` / `.activate[]` | 07 | Previous-image re-tag + activation |

Nothing downstream reads `settings.json` directly — this is the single
translation point from data model to API payload.

### Stage detail

| Stage | Module / action | Notes |
|---|---|---|
| 01 | `apt`, `template`, `command` (rsync), `community.general.ufw`, `uri` | Verifies each image with an HTTP HEAD expecting `200` + `application/octet-stream` |
| 02 | `inventory_workflow_manager`, `network_compliance_workflow_manager` | Resyncs inventory per site, then IMAGE compliance. Read-only. |
| 03 | `swim_workflow_manager` | Import by URL, then golden tag per family/role/site |
| 04 | `swim_workflow_manager` | Long-running — governed by `catalystcenter_api_task_timeout` |
| 05 | `swim_workflow_manager` | Honours `device_upgrade_mode`, `distribute_if_needed`, `schedule_validate` |
| 06 | `network_compliance_workflow_manager` | IMAGE compliance per site; compare against the 02 baseline |
| 07 | `swim_workflow_manager` | Re-tags `rollback_image` golden with `activate_lower_image_version: true` |

---

## Evidence Files

Every stage writes a JSON artifact to `ansible/logs/`, prefixed with the run's
`swim_run_id` (`YYYYmmdd-HHMMSS`) so one upgrade window's artifacts group
together:

| File | Stage |
|---|---|
| `<run_id>-00_preflight.json` | 02 |
| `<run_id>-10_import_and_tag.json` | 03 |
| `<run_id>-20_distribute.json` | 04 |
| `<run_id>-30_activate.json` | 05 |
| `<run_id>-35_rollback.json` | 07 |
| `<run_id>-40_postcheck.json` | 06 |

Diffing `00_preflight` against `40_postcheck` is the change record — this is the
part that usually replaces a manual screenshot in a change ticket.

---

## Rollback

Stage 07 reloads devices a second time, so it is guarded by two explicit
confirmation gates that the role asserts before doing anything:

```bash
ansible-playbook playbooks/07_swim_rollback.yml \
  -e rollback_confirm=YES \
  -e rollback_reload_ack=RELOAD_OK
```

Without both, the play fails immediately — a wildcard playbook glob can never
trigger it by accident.

**Prerequisite:** `rollback_image` must already exist in the Catalyst Center
repository. Stage 03 imports it alongside `upgrade_image` for exactly this
reason — do not skip 03 on the assumption that only the new image matters.

---

## Debug Mode

```bash
ansible-playbook playbooks/02_swim_preflight.yml -e catc_debug=true
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
| 01 HTTP HEAD verification fails | nginx not serving, ufw blocking, or image not staged | `curl -I http://<image_server_ip>/images/<file>.bin` from the control node |
| 03 import fails / times out | Catalyst Center cannot reach the image server | Confirm CatC → image server TCP/80 reachability; the URL must be resolvable *from CatC*, not from your laptop |
| Golden tag applied but 04 finds no devices | Devices not assigned to the site, or `device_role` too narrow | Verify site assignment in CatC inventory; try `device_role: "ALL"` |
| 04 / 05 times out | Large image over a slow link | Raise `catalystcenter_api_task_timeout` (default 3600s) |
| `sshpass: command not found` in 01 | Password SSH auth without sshpass | `brew install sshpass`, or switch the image server to SSH keys and drop `ansible_ssh_pass` |
| `Attempting to decrypt but no vault secrets found` | `.vault_pass` missing or unreadable | Recreate it at the repo root; `ansible.cfg` points at `../.vault_pass` |
| rsync restarts repeatedly in 01 | Low-MTU VPN path | Expected — the role retries with resume. Tune `image_rsync_retries` / `image_rsync_timeout`. |
| 06 still reports `NON_COMPLIANT` | Devices not fully back online after reload | Wait for inventory resync, then re-run 06 |

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
- Stages 05 and 07 reload devices. 07 is double-gated; 05 deliberately
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
