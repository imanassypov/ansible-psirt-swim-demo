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


def md_file_link(path: Path | str | None, label: str | None = None) -> str:
    """Same-folder relative markdown link for files committed alongside REPORT.md."""
    if path is None:
        return "n/a"
    name = path.name if isinstance(path, Path) else str(path)
    text = label if label is not None else name
    return f"[{text}]({name})"


def evidence_stage_label(filename: str) -> str:
    """Short human label derived from SWIM evidence filename suffix."""
    markers = (
        ("-00_compliance_pre_post.json", "Combined pre/post compliance"),
        ("-00_post_activate.json", "Post-activate compliance"),
        ("-00_preflight.json", "Pre-upgrade compliance"),
        ("-10_import_and_tag.json", "Import, family assignment and golden tag"),
        ("-20_distribute.json", "Image distribution"),
        ("-30_activate.json", "Image activation"),
    )
    for suffix, label in markers:
        if filename.endswith(suffix):
            return label
    return filename


def _int_value(value: object, default: int = 0) -> int:
    try:
        return int(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return default


def parse_sites_from_compliance_register(compliance_run: dict) -> list[dict]:
    """Parse ansible compliance register (mirrors build_compliance_site_reports.yml)."""
    sites: list[dict] = []
    for site_result in compliance_run.get("results", []):
        if not isinstance(site_result, dict):
            continue

        site_name = site_result.get("item", "unknown")
        devices: list[dict] = []
        response = site_result.get("response")
        if isinstance(response, dict):
            for device_name, records in response.items():
                rec = records[0] if isinstance(records, list) and records else {}
                if not isinstance(rec, dict):
                    continue
                source_info = rec.get("sourceInfoList") or []
                first_source = source_info[0] if source_info else {}
                diff_list = first_source.get("diffList") if isinstance(first_source, dict) else []
                diff = diff_list[0] if isinstance(diff_list, list) and diff_list else {}
                if not isinstance(diff, dict):
                    diff = {}
                devices.append(
                    {
                        "device": device_name,
                        "status": rec.get("status", "UNKNOWN"),
                        "configured_image": diff.get("configuredValue", "n/a"),
                        "intended_image": diff.get("intendedValue", "n/a"),
                    }
                )

        msg = site_result.get("msg", {})
        success_msg = msg if isinstance(msg, dict) else {}
        summary = success_msg.get("Run Compliance Check Succeeded for following device(s)", {})
        if not isinstance(summary, dict):
            summary = {}
        skipped_msg = success_msg.get("Run Compliance Check Skipped for following device(s)", {})
        skipped_devices = skipped_msg.get("skipped_devices", []) if isinstance(skipped_msg, dict) else []

        sites.append(
            {
                "site": site_name,
                "task_failed": bool(site_result.get("failed", False)),
                "compliant": _int_value(summary.get("Compliant Devices", 0)),
                "non_compliant": _int_value(summary.get("Non-Compliant Devices", 0)),
                "total_checked": _int_value(summary.get("Total Devices Checked", 0)),
                "skipped_devices": skipped_devices if isinstance(skipped_devices, list) else [],
                "devices": devices,
            }
        )
    return sites


def describe_assignment(entry: dict) -> str:
    """Assignment outcome for one (image, product name, site) binding."""
    if entry.get("already_assigned"):
        return "Already assigned"
    if entry.get("changed"):
        return "Assigned this run"
    return "Not assigned"


def render_image_preparation(evidence: dict) -> list[str]:
    """Summarise stage 01.1: repository import, device family binding, golden tag.

    The binding is what lets Catalyst Center tag an image golden and treat a
    device as non-compliant against it, so it belongs in the audit trail
    alongside the compliance results it drives.
    """
    lines = ["## Image preparation", ""]

    for key, label in (("import", "Repository import"), ("tag", "Golden tag")):
        block = evidence.get(key)
        if not isinstance(block, dict):
            continue
        if block.get("skipped"):
            state = "skipped"
        elif block.get("changed"):
            state = "changed"
        else:
            state = "no change (already in place)"
        count = len(block.get("results") or [])
        lines.append(f"- **{label}:** {state} — {count} image(s)")

    assignments = [a for a in evidence.get("assign_product_names") or [] if isinstance(a, dict)]
    if assignments:
        lines.append("")
        lines.append("### Device family assignment")
        lines.append("")
        lines.append("| Image | Device product name | Site | Outcome |")
        lines.append("| --- | --- | --- | --- |")
        for entry in assignments:
            lines.append(
                f"| {entry.get('image_name', 'n/a')} "
                f"| {entry.get('product_name', 'n/a')} "
                f"| {entry.get('site_name', 'n/a')} "
                f"| {describe_assignment(entry)} |"
            )

    lines.append("")
    return lines


def format_totals(label: str, totals: dict) -> str:
    return (
        f"- **{label}:** compliant={_int_value(totals.get('compliant', 0))}, "
        f"non-compliant={_int_value(totals.get('non_compliant', 0))}, "
        f"checked={_int_value(totals.get('total_checked', 0))}"
    )


def humanize_status(status: object) -> str:
    return str(status).replace("_", "-").lower()


def describe_outcome(pre_dev: dict, post_dev: dict) -> str:
    pre_status = pre_dev.get("status", "n/a")
    post_status = post_dev.get("status", "n/a")
    pre_configured = pre_dev.get("configured_image", "n/a")
    post_configured = post_dev.get("configured_image", "n/a")

    if post_status == "COMPLIANT":
        if pre_status != "COMPLIANT":
            return "Now compliant"
        return "Compliant (unchanged)"

    if pre_configured != post_configured and post_configured != "n/a":
        return f"Image updated ({pre_configured} → {post_configured})"

    if pre_status == post_status:
        return f"Still {humanize_status(post_status)}"

    return f"{pre_status} → {post_status}"


def merge_sites_by_name(pre_sites: list[dict], post_sites: list[dict]) -> list[dict]:
    post_by_site = {s.get("site"): s for s in post_sites if isinstance(s, dict)}
    merged: list[dict] = []
    seen: set[str] = set()

    for pre_site in pre_sites:
        if not isinstance(pre_site, dict):
            continue
        site_name = pre_site.get("site", "unknown")
        seen.add(site_name)
        merged.append(
            {
                "site": site_name,
                "pre": pre_site,
                "post": post_by_site.get(site_name, {"devices": []}),
            }
        )

    for post_site in post_sites:
        if not isinstance(post_site, dict):
            continue
        site_name = post_site.get("site", "unknown")
        if site_name not in seen:
            merged.append(
                {
                    "site": site_name,
                    "pre": {"devices": []},
                    "post": post_site,
                }
            )

    return merged


def render_site_summary_table(merged_sites: list[dict]) -> list[str]:
    lines = [
        "## Site summary",
        "",
        "| Site | Pre compliant | Pre non-compliant | Pre checked | "
        "Post compliant | Post non-compliant | Post checked |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for entry in merged_sites:
        pre_site = entry["pre"]
        post_site = entry["post"]
        lines.append(
            f"| {entry.get('site', 'unknown')} "
            f"| {_int_value(pre_site.get('compliant', 0))} "
            f"| {_int_value(pre_site.get('non_compliant', 0))} "
            f"| {_int_value(pre_site.get('total_checked', 0))} "
            f"| {_int_value(post_site.get('compliant', 0))} "
            f"| {_int_value(post_site.get('non_compliant', 0))} "
            f"| {_int_value(post_site.get('total_checked', 0))} |"
        )
    lines.append("")
    return lines


def render_device_pre_post_table(pre_site: dict, post_site: dict) -> list[str]:
    lines = [
        "| Device | Pre status | Pre configured | Pre intended | "
        "Post status | Post configured | Post intended | Outcome |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |",
    ]

    pre_devices = {d["device"]: d for d in pre_site.get("devices", []) if "device" in d}
    post_devices = {d["device"]: d for d in post_site.get("devices", []) if "device" in d}

    for device_name in sorted(set(pre_devices) | set(post_devices)):
        pre_dev = pre_devices.get(device_name, {})
        post_dev = post_devices.get(device_name, {})
        lines.append(
            f"| {device_name} "
            f"| {pre_dev.get('status', 'n/a')} "
            f"| {pre_dev.get('configured_image', 'n/a')} "
            f"| {pre_dev.get('intended_image', 'n/a')} "
            f"| {post_dev.get('status', 'n/a')} "
            f"| {post_dev.get('configured_image', 'n/a')} "
            f"| {post_dev.get('intended_image', 'n/a')} "
            f"| {describe_outcome(pre_dev, post_dev)} |"
        )

    skipped_pre = pre_site.get("skipped_devices") or []
    skipped_post = post_site.get("skipped_devices") or []
    if skipped_pre or skipped_post:
        lines.append("")
        if skipped_pre:
            lines.append(f"**Skipped (pre):** {', '.join(map(str, skipped_pre))}")
        if skipped_post:
            lines.append(f"**Skipped (post):** {', '.join(map(str, skipped_post))}")

    lines.append("")
    return lines


def render_device_pre_only_table(site: dict) -> list[str]:
    lines = [
        "| Device | Status | Configured | Intended |",
        "| --- | --- | --- | --- |",
    ]
    for dev in site.get("devices", []):
        lines.append(
            f"| {dev.get('device', 'n/a')} "
            f"| {dev.get('status', 'n/a')} "
            f"| {dev.get('configured_image', 'n/a')} "
            f"| {dev.get('intended_image', 'n/a')} |"
        )

    skipped = site.get("skipped_devices") or []
    if skipped:
        lines.append("")
        lines.append(f"**Skipped:** {', '.join(map(str, skipped))}")

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
    import_tag_path = newest_matching(report_dir, "*-10_import_and_tag.json")

    lines: list[str] = [
        "# SWIM PSIRT Pipeline Report",
        "",
        f"- **Generated:** {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}",
        f"- **Report directory:** `{report_dir.name}`",
        "",
    ]

    evidence_files = sorted(p.name for p in report_dir.glob("*.json") if p.name != "manifest.json")
    if evidence_files:
        lines.append("## Evidence files")
        lines.append("")
        for name in evidence_files:
            label = evidence_stage_label(name)
            lines.append(f"- {label}: {md_file_link(name)}")
        lines.append("")

    if import_tag_path:
        import_tag = load_json(import_tag_path)
        if isinstance(import_tag, dict):
            lines.extend(render_image_preparation(import_tag))

    pre_post = load_json(pre_post_path) if pre_post_path else None
    if isinstance(pre_post, dict) and pre_post.get("phase") == "pre-post":
        lines.append("## Compliance overview")
        lines.append("")
        lines.append(
            f"- **Pre-upgrade run:** {md_file_link(preflight_path, str(pre_post.get('pre_run_id', 'n/a')))}"
        )
        post_evidence = pre_post_path or post_path
        lines.append(
            f"- **Post-activate run:** {md_file_link(post_evidence, str(pre_post.get('post_run_id', 'n/a')))}"
        )
        lines.append("")
        pre_totals = pre_post.get("pre_upgrade", {}).get("totals", {})
        post_totals = pre_post.get("post_activate", {}).get("totals", {})
        lines.append(format_totals("Pre-upgrade (all sites)", pre_totals))
        lines.append(format_totals("Post-activate (all sites)", post_totals))
        lines.append("")

        pre_sites = pre_post.get("pre_upgrade", {}).get("sites", [])
        post_sites = pre_post.get("post_activate", {}).get("sites", [])
        merged_sites = merge_sites_by_name(pre_sites, post_sites)

        lines.extend(render_site_summary_table(merged_sites))

        lines.append("## Device details by site")
        lines.append("")
        for entry in merged_sites:
            lines.append(f"### {entry.get('site', 'unknown')}")
            lines.append("")
            lines.extend(render_device_pre_post_table(entry["pre"], entry["post"]))
    elif preflight_path:
        preflight = load_json(preflight_path)
        lines.append("## Compliance overview (pre-upgrade only)")
        lines.append("")
        lines.append(
            "> Post-activation compliance was not captured in this run. "
            "Re-run stage 00.2 with `-e post_activate=true` after activation."
        )
        lines.append("")

        if isinstance(preflight, dict) and isinstance(preflight.get("compliance"), dict):
            pre_sites = parse_sites_from_compliance_register(preflight["compliance"])
            if pre_sites:
                lines.append("## Site summary")
                lines.append("")
                lines.append("| Site | Compliant | Non-compliant | Checked |")
                lines.append("| --- | ---: | ---: | ---: |")
                for site in pre_sites:
                    lines.append(
                        f"| {site.get('site', 'unknown')} "
                        f"| {_int_value(site.get('compliant', 0))} "
                        f"| {_int_value(site.get('non_compliant', 0))} "
                        f"| {_int_value(site.get('total_checked', 0))} |"
                    )
                lines.append("")

                lines.append("## Device details by site")
                lines.append("")
                for site in pre_sites:
                    lines.append(f"### {site.get('site', 'unknown')}")
                    lines.append("")
                    lines.extend(render_device_pre_only_table(site))
            else:
                lines.append(
                    f"- Source: {md_file_link(preflight_path)} (no site rows parsed)"
                )
                lines.append("")
        else:
            lines.append(f"- Source: {md_file_link(preflight_path)}")
            lines.append("")
    else:
        lines.append("## Compliance overview")
        lines.append("")
        lines.append("_No compliance evidence files were found in this report directory._")
        lines.append("")

    if post_path and not pre_post_path:
        lines.append(f"- Post-activate evidence: {md_file_link(post_path)}")
        lines.append("")

    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "report_directory": report_dir.name,
        "evidence_files": evidence_files,
        "compliance_pre_post": pre_post_path.name if pre_post_path else None,
        "preflight": preflight_path.name if preflight_path else None,
        "post_activate": post_path.name if post_path else None,
        "import_and_tag": import_tag_path.name if import_tag_path else None,
    }
    (report_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    (report_dir / "REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
