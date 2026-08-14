#!/usr/bin/env python3
"""Render a markdown summary from SWIM compliance evidence in a report directory."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def load_json(path: Path) -> dict | list | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def newest_matching(directory: Path, pattern: str) -> Path | None:
    matches = sorted(directory.glob(pattern))
    return matches[-1] if matches else None


def format_totals(label: str, totals: dict) -> str:
    return (
        f"- **{label}:** compliant={totals.get('compliant', 0)}, "
        f"non-compliant={totals.get('non_compliant', 0)}, "
        f"checked={totals.get('total_checked', 0)}"
    )


def render_device_table(sites: list[dict], *, pre_post: bool = False) -> list[str]:
    lines: list[str] = []
    for site in sites:
        lines.append(f"### Site: {site.get('site', 'unknown')}")
        lines.append("")
        if pre_post:
            lines.append("| Device | Pre Status | Post Status | Pre Configured | Post Configured |")
            lines.append("| --- | --- | --- | --- | --- |")
            pre_site = site if isinstance(site, dict) else {}
            post_site = site
            pre_devices = {d["device"]: d for d in pre_site.get("devices", []) if "device" in d}
            post_devices = {d["device"]: d for d in post_site.get("devices", []) if "device" in d}
            for device_name in sorted(set(pre_devices) | set(post_devices)):
                pre_dev = pre_devices.get(device_name, {})
                post_dev = post_devices.get(device_name, {})
                lines.append(
                    f"| {device_name} "
                    f"| {pre_dev.get('status', 'n/a')} "
                    f"| {post_dev.get('status', 'n/a')} "
                    f"| {pre_dev.get('configured_image', 'n/a')} "
                    f"| {post_dev.get('configured_image', 'n/a')} |"
                )
        else:
            lines.append("| Device | Status | Configured | Intended |")
            lines.append("| --- | --- | --- | --- |")
            for dev in site.get("devices", []):
                lines.append(
                    f"| {dev.get('device', 'n/a')} "
                    f"| {dev.get('status', 'n/a')} "
                    f"| {dev.get('configured_image', 'n/a')} "
                    f"| {dev.get('intended_image', 'n/a')} |"
                )
        lines.append("")
    return lines


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <report-directory>", file=sys.stderr)
        return 2

    report_dir = Path(sys.argv[1]).resolve()
    if not report_dir.is_dir():
        print(f"ERROR: report directory not found: {report_dir}", file=sys.stderr)
        return 1

    pre_post_path = newest_matching(report_dir, "*-00_compliance_pre_post.json")
    preflight_path = newest_matching(report_dir, "*-00_preflight.json")
    post_path = newest_matching(report_dir, "*-00_post_activate.json")

    lines: list[str] = [
        "# SWIM PSIRT Pipeline Report",
        "",
        f"- **Generated:** {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}",
        f"- **Report directory:** `{report_dir.name}`",
        "",
    ]

    evidence_files = sorted(p.name for p in report_dir.glob("*.json"))
    if evidence_files:
        lines.append("## Evidence files")
        lines.append("")
        for name in evidence_files:
            lines.append(f"- `{name}`")
        lines.append("")

    pre_post = load_json(pre_post_path) if pre_post_path else None
    if isinstance(pre_post, dict) and pre_post.get("phase") == "pre-post":
        lines.append("## Compliance summary (pre vs post activation)")
        lines.append("")
        lines.append(f"- **Pre-upgrade run:** `{pre_post.get('pre_run_id', 'n/a')}`")
        lines.append(f"- **Post-activate run:** `{pre_post.get('post_run_id', 'n/a')}`")
        lines.append("")
        pre_totals = pre_post.get("pre_upgrade", {}).get("totals", {})
        post_totals = pre_post.get("post_activate", {}).get("totals", {})
        lines.append(format_totals("Pre-upgrade", pre_totals))
        lines.append(format_totals("Post-activate", post_totals))
        lines.append("")

        pre_sites = pre_post.get("pre_upgrade", {}).get("sites", [])
        post_sites = pre_post.get("post_activate", {}).get("sites", [])
        post_by_site = {s.get("site"): s for s in post_sites if isinstance(s, dict)}
        merged_sites = []
        for pre_site in pre_sites:
            site_name = pre_site.get("site")
            merged_sites.append(
                {
                    "site": site_name,
                    "devices": [],
                    "_pre": pre_site,
                    "_post": post_by_site.get(site_name, {"devices": []}),
                }
            )
        for post_site in post_sites:
            site_name = post_site.get("site")
            if site_name not in {s.get("site") for s in pre_sites}:
                merged_sites.append(
                    {
                        "site": site_name,
                        "devices": [],
                        "_pre": {"devices": []},
                        "_post": post_site,
                    }
                )

        lines.append("## Per-site device status")
        lines.append("")
        for entry in merged_sites:
            pre_site = entry["_pre"]
            post_site = entry["_post"]
            lines.append(f"### Site: {entry.get('site', 'unknown')}")
            lines.append("")
            lines.append("| Device | Pre Status | Post Status | Pre Configured | Post Configured |")
            lines.append("| --- | --- | --- | --- | --- |")
            pre_devices = {d["device"]: d for d in pre_site.get("devices", []) if "device" in d}
            post_devices = {d["device"]: d for d in post_site.get("devices", []) if "device" in d}
            for device_name in sorted(set(pre_devices) | set(post_devices)):
                pre_dev = pre_devices.get(device_name, {})
                post_dev = post_devices.get(device_name, {})
                lines.append(
                    f"| {device_name} "
                    f"| {pre_dev.get('status', 'n/a')} "
                    f"| {post_dev.get('status', 'n/a')} "
                    f"| {pre_dev.get('configured_image', 'n/a')} "
                    f"| {post_dev.get('configured_image', 'n/a')} |"
                )
            lines.append("")
    elif preflight_path:
        preflight = load_json(preflight_path)
        lines.append("## Compliance summary (pre-upgrade only)")
        lines.append("")
        lines.append(
            "> Post-activation compliance was not captured in this run. "
            "Check pipeline logs or re-run stage 00.2 with `-e post_activate=true`."
        )
        lines.append("")
        if isinstance(preflight, dict) and "compliance" in preflight:
            lines.append("- Evidence captured from pre-upgrade baseline.")
            lines.append(f"- Source: `{preflight_path.name}`")
        lines.append("")
    else:
        lines.append("## Compliance summary")
        lines.append("")
        lines.append("_No compliance evidence files were found in this report directory._")
        lines.append("")

    if post_path and not pre_post_path:
        lines.append(f"- Post-activate evidence: `{post_path.name}`")
        lines.append("")

    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "report_directory": report_dir.name,
        "evidence_files": evidence_files,
        "compliance_pre_post": pre_post_path.name if pre_post_path else None,
        "preflight": preflight_path.name if preflight_path else None,
        "post_activate": post_path.name if post_path else None,
    }
    (report_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    (report_dir / "REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
