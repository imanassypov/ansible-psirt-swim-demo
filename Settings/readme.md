# Settings — Central Data Model

`settings.json` is the single source of truth for this demo. Every SWIM playbook
(00.1, 00.2, 01.1–01.3, 02.1) reads it (no image name, site path, or device family is
hardcoded in a playbook or role).

## Schema

```json
{
  "project": [
    {
      "HierarchyParent": "Global/PODS",
      "HierarchyArea":   "POD 0",
      "HierarchyBldg":   "Building P0",
      "HierarchyFloor":  "Floor 1",
      "swim": { ... }
    }
  ]
}
```

### `project[].swim`

| Field | Type | Description |
|---|---|---|
| `image_server_base_url` | string | Base URL Catalyst Center pulls images from. Must exactly match what stage 00.1 serves (`http://<image_server_ip>/<image_url_subdir>`). |
| `device_image_family_name` | string | CatC *image* family name used for golden tagging — the "Family Name" column on the SWIM Image Families page (e.g. `Cisco Catalyst 9000 UADP 8 Port Virtual Switch`). Must match a product name the image itself declares support for. |
| `device_family_name` | string | CatC *device* family (inventory `family` attribute) used for distribute/activate targeting (e.g. `Switches and Hubs`). A different taxonomy from `device_image_family_name` — the two are expected to differ. |
| `device_series_name` | string | CatC device series (inventory `series` attribute) used for distribute/activate targeting (e.g. `Cisco Catalyst 9000 Series Virtual Switches`). Matched as a substring, not exactly. |
| `device_role` | string | `ALL` \| `CORE` \| `DISTRIBUTION` \| `ACCESS` \| `BORDER ROUTER`. Narrows the blast radius. |
| `upgrade_image` | string | `.bin` filename to import, tag Golden, distribute and activate. Set to the PSIRT-remediating image when responding to an advisory (default in repo: `cat9kv-universalk9.17.15.03.SPA.bin`; example fix build: `cat9kv-universalk9.BLD_V262_THROTTLE_LATEST_20260529_003538.SSA.bin`). |
| `rollback_image` | string | Known-good `.bin` to return to in stage 02.1. Imported alongside `upgrade_image` in 01.1. Set to `""` to disable rollback. |
| `activation.device_upgrade_mode` | string | `install` (recommended), `bundle`, or `currentlyExists`. Applied to upgrade (01.3) and rollback (02.1) activation. |
| `activation.distribute_if_needed` | bool | Auto-distribute during activation when flash lacks the image. Applied to upgrade (01.3) and rollback (02.1). |
| `activation.schedule_validate` | bool | Run CatC pre-activation validation before reload. Applied to upgrade (01.3) and rollback (02.1). |
| `activation.image_activation_timeout` | int | Seconds to wait for activation/reload to complete (default 3600). Applied to upgrade (01.3) and rollback (02.1). |
| `activation.image_distribution_timeout` | int | Seconds to wait for image distribution to complete (default 3600). Applied to distribute (01.2). |
| `activation.wait_for_reachability` | bool | Post-activate only (`00.2 -e post_activate=true`): poll CatC until site devices are Reachable + Managed/In Progress before compliance (default true). |
| `activation.reachability_poll_interval` | int | Seconds between reachability polls (default 60). |
| `activation.reachability_poll_timeout` | int | Max seconds to wait for reachability before failing post-activate (default 600). |

## Derived site path

`HierarchyParent / HierarchyArea / HierarchyBldg / HierarchyFloor` are joined
with `/`, skipping empty segments:

```
Global/PODS/POD 0/Building P0/Floor 1
```

This is the `site_name` used for golden tagging, distribution, activation and
the IMAGE compliance checks in 00.2 (use `-e post_activate=true` after activation).

## Multiple sites

Add more `project[]` entries. Images are de-duplicated across entries, so the
same `.bin` referenced by several sites is imported into CatC only once.

## Path resolution

Playbooks find this file through `settings_json_path` in
`ansible/inventory/group_vars/catalyst_center/connection.yml`, relative to
`ansible/playbooks/`:

```yaml
settings_json_path: "../../Settings/settings.json"
```

Override at runtime with `-e settings_json_path=/abs/path/settings.json`.

## Safety note

This file is intentionally free of credentials. Catalyst Center and image-server
secrets live in ansible-vault files under
`ansible/inventory/group_vars/*/vault.yml` and are never committed.
