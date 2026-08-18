# SWIM PSIRT Pipeline Report

- **Generated:** 2026-08-18 16:34:32 UTC
- **Report directory:** `18-32160614793`

## Evidence files

- Pre-upgrade compliance: [20260818-123040-00_preflight.json](20260818-123040-00_preflight.json)
- Import, family assignment and golden tag: [20260818-123100-10_import_and_tag.json](20260818-123100-10_import_and_tag.json)
- Image distribution: [20260818-123140-20_distribute.json](20260818-123140-20_distribute.json)
- Image activation: [20260818-123149-30_activate.json](20260818-123149-30_activate.json)
- Post-activate compliance: [20260818-123430-00_post_activate.json](20260818-123430-00_post_activate.json)
- Combined pre/post compliance: [20260818-123431-00_compliance_pre_post.json](20260818-123431-00_compliance_pre_post.json)

## Image preparation

- **Repository import:** no change (already in place) — 2 image(s)
- **Golden tag:** no change (already in place) — 1 image(s)

### Device family assignment

| Image | Device product name | Site | Outcome |
| --- | --- | --- | --- |
| cat9kv-universalk9.BLD_V262_THROTTLE_LATEST_20260529_003538.SSA.bin | Cisco Catalyst 9000 UADP 8 Port Virtual Switch | {site-hierarchy} | Already assigned |
| cat9kv-universalk9.17.15.03.SPA.bin | Cisco Catalyst 9000 UADP 8 Port Virtual Switch | {site-hierarchy} | Already assigned |

## Compliance overview

- **Pre-upgrade run:** [20260818-123040](20260818-123040-00_preflight.json)
- **Post-activate run:** [20260818-123431](20260818-123431-00_compliance_pre_post.json)

- **Pre-upgrade (all sites):** compliant=2, non-compliant=0, checked=2
- **Post-activate (all sites):** compliant=6, non-compliant=0, checked=6

## Site summary

| Site | Pre compliant | Pre non-compliant | Pre checked | Post compliant | Post non-compliant | Post checked |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| {site-hierarchy} | 2 | 0 | 2 | 6 | 0 | 6 |

## Device details by site

### {site-hierarchy}

| Device | Pre status | Pre configured | Pre intended | Post status | Post configured | Post intended | Outcome |
| --- | --- | --- | --- | --- | --- | --- | --- |
| device-01 | n/a | n/a | n/a | COMPLIANT | n/a | n/a | Now compliant |
| device-02 | n/a | n/a | n/a | COMPLIANT | n/a | n/a | Now compliant |
| device-03 | COMPLIANT | n/a | n/a | COMPLIANT | n/a | n/a | Compliant (unchanged) |
| device-04 | COMPLIANT | n/a | n/a | COMPLIANT | n/a | n/a | Compliant (unchanged) |
| device-05 | n/a | n/a | n/a | COMPLIANT | n/a | n/a | Now compliant |
| device-06 | n/a | n/a | n/a | COMPLIANT | n/a | n/a | Now compliant |

**Skipped (pre):** device-05, device-02, device-01, device-06

