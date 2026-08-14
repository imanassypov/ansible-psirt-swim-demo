# Settings — Central Data Model

`settings.json` is the single source of truth for this demo. Every 01–07 playbook
reads it (no image name, site path, or device family is hardcoded in a playbook
or role).

## Schema

```jsonc
{
  "project": [                       // one entry per target site
    {
      "HierarchyParent": "Global/PODS",   // ─┐
      "HierarchyArea":   "POD 0",         //  │ concatenated with "/" into
      "HierarchyBldg":   "Building P0",   //  │ swim site_name
      "HierarchyFloor":  "Floor 1",       // ─┘
      "swim": { ... }
    }
  ]
}
```

### `project[].swim`

| Field | Type | Description |
|---|---|---|
| `image_server_base_url` | string | Base URL Catalyst Center pulls images from. Must exactly match what stage 01 serves (`http://<image_server_ip>/<image_url_subdir>`). |
| `device_family_identifier` | string | CatC *image* family name used for golden tagging (e.g. `Cisco Catalyst 9000 UADP 8 Port Virtual Switch`). |
| `device_family_name` | string | CatC *device* family used for distribute/activate targeting (e.g. `Switches and Hubs`). |
| `device_series_name` | string | CatC device series used for distribute/activate targeting. |
| `device_role` | string | `ALL` \| `CORE` \| `DISTRIBUTION` \| `ACCESS` \| `BORDER ROUTER`. Narrows the blast radius. |
| `upgrade_image` | string | `.bin` filename to import, tag Golden, distribute and activate. This is the PSIRT-remediating image. |
| `rollback_image` | string | Known-good `.bin` to return to in stage 07. Imported alongside `upgrade_image` in 03. Set to `""` to disable rollback. |
| `activation.device_upgrade_mode` | string | `install` (recommended) or `bundle`. |
| `activation.distribute_if_needed` | bool | Auto-distribute during activation when flash lacks the image. |
| `activation.schedule_validate` | bool | Run CatC pre-activation validation before reload. |

## Derived site path

`HierarchyParent / HierarchyArea / HierarchyBldg / HierarchyFloor` are joined
with `/`, skipping empty segments:

```
Global/PODS/POD 0/Building P0/Floor 1
```

This is the `site_name` used for golden tagging, distribution, activation and
the IMAGE compliance checks in 02 / 06.

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
