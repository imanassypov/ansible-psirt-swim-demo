#!/usr/bin/env python3
"""Redact local paths and lab/customer identifiers from SWIM report artifacts."""

from __future__ import annotations

import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

IPV4_RE = re.compile(
    r"\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d?\d)\.){3}"
    r"(?:25[0-5]|2[0-4]\d|[01]?\d?\d)\b"
)
UUID_RE = re.compile(
    r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b",
    re.IGNORECASE,
)
MAC_RE = re.compile(r"\b(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b")
SITE_HIERARCHY_RE = re.compile(r"\bGlobal/[A-Za-z0-9 ./_-]+\b")
URL_WITH_IP_RE = re.compile(r"https?://(?:(?:25[0-5]|2[0-4]\d|[01]?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d?\d)([^\s\"']*)")
ABS_UNIX_PATH_RE = re.compile(r"(?<![A-Za-z0-9_./-])(/(?:Users|home|var|tmp|opt|private)(?:/[^\s\"'`,\]})]+)?)")

DROP_KEY_RE = re.compile(
    r"(password|secret|token|api[_-]?key|private[_-]?key|credential|vault)",
    re.IGNORECASE,
)
ALWAYS_DROP_KEYS = {
    "invocation",
    "module_args",
    "catalystcenter_password",
    "catalystcenter_username",
    "ansible_password",
    "ansible_become_pass",
    "ansible_ssh_pass",
}

LAB_IP_PREFIXES = (
    "10.",
    "172.16.",
    "172.17.",
    "172.18.",
    "172.19.",
    "172.20.",
    "172.21.",
    "172.22.",
    "172.23.",
    "172.24.",
    "172.25.",
    "172.26.",
    "172.27.",
    "172.28.",
    "172.29.",
    "172.30.",
    "172.31.",
    "192.168.",
    "198.18.",
    "198.19.",
)


@dataclass
class SanitizeContext:
    repo_root: str = ""
    home_root: str = ""
    lab_root: str = ""
    ip_map: dict[str, str] = field(default_factory=dict)
    next_device_idx: int = 1

    def device_alias(self, ip: str) -> str:
        if ip not in self.ip_map:
            self.ip_map[ip] = f"device-{self.next_device_idx:02d}"
            self.next_device_idx += 1
        return self.ip_map[ip]

    def is_lab_ip(self, ip: str) -> bool:
        return ip.startswith(LAB_IP_PREFIXES)


def collect_strings(value: Any, bucket: list[str]) -> None:
    if isinstance(value, dict):
        for key, item in value.items():
            bucket.append(str(key))
            collect_strings(item, bucket)
    elif isinstance(value, list):
        for item in value:
            collect_strings(item, bucket)
    elif isinstance(value, str):
        bucket.append(value)


def build_ip_map(payloads: list[Any], ctx: SanitizeContext) -> None:
    strings: list[str] = []
    for payload in payloads:
        collect_strings(payload, strings)

    ips = set()
    for text in strings:
        ips.update(IPV4_RE.findall(text))

    for ip in sorted(ips, key=lambda addr: [int(octet) for octet in addr.split(".")]):
        # Device management addresses only — image-server IPs become <image-server>.
        if ip.startswith("198.19."):
            ctx.device_alias(ip)


def replace_paths(text: str, ctx: SanitizeContext) -> str:
    for literal in (ctx.lab_root, ctx.repo_root, ctx.home_root):
        if literal:
            text = text.replace(literal, "<lab-root>" if literal == ctx.lab_root else "<repo>" if literal == ctx.repo_root else "<home>")
    text = ABS_UNIX_PATH_RE.sub("<path>", text)
    text = re.sub(r"/Users/[^\s\"'`,\]})]+", "<home>", text)
    text = re.sub(r"/home/[^\s\"'`,\]})]+", "<home>", text)
    return text


def sanitize_string(text: str, ctx: SanitizeContext) -> str:
    if not isinstance(text, str):
        return text

    text = replace_paths(text, ctx)
    text = re.sub(r"\b198\.18\.\d+\.\d+\b", "<image-server>", text)
    text = URL_WITH_IP_RE.sub(r"http://<image-server>\1", text)
    text = SITE_HIERARCHY_RE.sub("<site-hierarchy>", text)
    text = UUID_RE.sub("<device-id>", text)
    text = MAC_RE.sub("<mac>", text)

    for ip, alias in sorted(ctx.ip_map.items(), key=lambda item: len(item[0]), reverse=True):
        text = text.replace(ip, alias)

    return text


def sanitize_value(value: Any, ctx: SanitizeContext) -> Any:
    if isinstance(value, dict):
        sanitized: dict[Any, Any] = {}
        for key, item in value.items():
            key_str = str(key)
            if key_str in ALWAYS_DROP_KEYS or DROP_KEY_RE.search(key_str):
                continue
            new_key = sanitize_string(key_str, ctx)
            sanitized[new_key] = sanitize_value(item, ctx)
        return sanitized
    if isinstance(value, list):
        return [sanitize_value(item, ctx) for item in value]
    if isinstance(value, str):
        return sanitize_string(value, ctx)
    return value


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def sanitize_report_dir(report_dir: Path) -> None:
    lab_root = os.environ.get("SWIM_LAB_ROOT", str(Path(__file__).resolve().parents[1]))
    repo_root = lab_root
    home_root = str(Path.home())

    ctx = SanitizeContext(repo_root=repo_root, home_root=home_root, lab_root=lab_root)

    json_paths = sorted(p for p in report_dir.glob("*.json") if p.name != "manifest.json")
    payloads = []
    for path in json_paths:
        try:
            payloads.append(load_json(path))
        except json.JSONDecodeError:
            continue

    build_ip_map(payloads, ctx)

    for path in json_paths:
        try:
            sanitized = sanitize_value(load_json(path), ctx)
            path.write_text(json.dumps(sanitized, indent=4) + "\n", encoding="utf-8")
        except json.JSONDecodeError:
            continue

    report_md = report_dir / "REPORT.md"
    if report_md.exists():
        report_md.write_text(
            sanitize_string(report_md.read_text(encoding="utf-8"), ctx),
            encoding="utf-8",
        )

    manifest_path = report_dir / "manifest.json"
    if manifest_path.exists():
        try:
            manifest = sanitize_value(load_json(manifest_path), ctx)
        except json.JSONDecodeError:
            manifest = {
                "report_directory": report_dir.name,
                "sanitized": True,
            }
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <report-directory>", file=sys.stderr)
        return 2

    report_dir = Path(sys.argv[1]).resolve()
    if not report_dir.is_dir():
        print(f"ERROR: report directory not found: {report_dir}", file=sys.stderr)
        return 1

    sanitize_report_dir(report_dir)
    print(f"Sanitized report artifacts in {report_dir.name}/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
