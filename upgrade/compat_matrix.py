"""Compatibility matrix for porting the training stack across Ubuntu LTS releases.

Baseline: Ubuntu 20.04 (Focal) — current Blade host.
Target path: 20.04 → 22.04 → 24.04 → 26.04.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

# Codename / version / default system Python for each LTS hop.
LTS_RELEASES = (
    {"version": "20.04", "codename": "focal", "python": "3.8", "status": "baseline"},
    {"version": "22.04", "codename": "jammy", "python": "3.10", "status": "next"},
    {"version": "24.04", "codename": "noble", "python": "3.12", "status": "planned"},
    {"version": "26.04", "codename": "resolute", "python": "3.13", "status": "target"},
)


@dataclass(frozen=True)
class CompatibilityIssue:
    """A known breakage that must be fixed before/during an LTS upgrade."""

    id: str
    severity: str  # blocker | high | medium | low
    first_broken_on: str  # Ubuntu version where the issue starts
    pattern: str  # regex matched against docs/scripts
    summary: str
    fix: str


# Patterns scanned against README.md, commands_cheatsheet.txt, and *.sh
KNOWN_ISSUES: tuple[CompatibilityIssue, ...] = (
    CompatibilityIssue(
        id="libncurses5",
        severity="blocker",
        first_broken_on="22.04",
        pattern=r"\blibncurses5(-dev)?\b",
        summary="libncurses5 packages were dropped after 20.04",
        fix="Replace with libncurses6 / libncurses-dev (or libncursesw6)",
    ),
    CompatibilityIssue(
        id="python39-pin",
        severity="blocker",
        first_broken_on="22.04",
        pattern=r"\bpython3\.9\b",
        summary="Hard-coded python3.9 is not the system interpreter on later LTS",
        fix="Use python3 (system) or a venv; avoid pinning 3.9 in install docs",
    ),
    CompatibilityIssue(
        id="docker-compose-v1",
        severity="high",
        first_broken_on="22.04",
        # Match CLI usage only — not directory names like .../docker-compose/
        pattern=r"(?<!/)docker-compose\s",
        summary="Standalone docker-compose v1 is deprecated; Compose V2 is a plugin",
        fix="Install docker-compose-plugin and use `docker compose` (space)",
    ),
    CompatibilityIssue(
        id="docker-compose-v1-binary-url",
        severity="high",
        first_broken_on="22.04",
        pattern=r"github\.com/docker/compose/releases/download/1\.",
        summary="Docs install Compose 1.29.2 binary which is EOL",
        fix="Use apt package docker-compose-plugin instead of curling v1 binaries",
    ),
    CompatibilityIssue(
        id="var-log-syslog",
        severity="high",
        first_broken_on="24.04",
        # Old hazardous form only; guarded grep + journalctl fallback is OK
        pattern=r"cat\s+/var/log/syslog",
        summary="quecController greps /var/log/syslog; journald-only hosts may lack it",
        fix="Prefer journalctl -u ... or fall back if syslog file is absent",
    ),
    CompatibilityIssue(
        id="uhd-python38-site",
        severity="blocker",
        first_broken_on="22.04",
        pattern=r"python3\.8/site-packages/uhd",
        summary="UHD was built against Python 3.8 site-packages on 20.04",
        fix="Rebuild UHD on each LTS so bindings match the new system Python",
    ),
    CompatibilityIssue(
        id="git-core-transitional",
        severity="low",
        first_broken_on="22.04",
        pattern=r"\bgit-core\b",
        summary="git-core is a transitional package name",
        fix="Install `git` instead of `git-core`",
    ),
    CompatibilityIssue(
        id="libgnutls28-dev",
        severity="medium",
        first_broken_on="24.04",
        pattern=r"\blibgnutls28-dev\b",
        summary="Package naming for GnuTLS -dev may differ across releases",
        fix="On 20.04/22.04 libgnutls28-dev is fine; on newer LTS verify with apt-cache search libgnutls",
    ),
    CompatibilityIssue(
        id="speedtest-cli",
        severity="low",
        first_broken_on="24.04",
        pattern=r"\bspeedtest-cli\b",
        summary="speedtest-cli packaging / CLI name varies by release",
        fix="Prefer `speedtest` from Ookla or keep speedtest-cli if still packaged",
    ),
    CompatibilityIssue(
        id="ubuntu-20-only-docs",
        severity="medium",
        first_broken_on="22.04",
        pattern=r"Ubuntu 20\.04 LTS on bare metal",
        summary="Docs hard-require Ubuntu 20.04 only",
        fix="Update README supported-OS matrix to include 22.04/24.04/26.04 as validated",
    ),
)


def issues_for_target(target_version: str) -> list[CompatibilityIssue]:
    """Return issues that apply when upgrading TO target_version (inclusive of earlier breaks)."""
    order = [r["version"] for r in LTS_RELEASES]
    if target_version not in order:
        raise ValueError(f"Unknown LTS version: {target_version}")
    target_idx = order.index(target_version)
    return [
        issue
        for issue in KNOWN_ISSUES
        if order.index(issue.first_broken_on) <= target_idx
        and issue.first_broken_on != "20.04"
    ]


def scan_text(text: str, issues: Iterable[CompatibilityIssue] | None = None) -> list[CompatibilityIssue]:
    """Return known issues whose patterns appear in text."""
    found: list[CompatibilityIssue] = []
    for issue in issues or KNOWN_ISSUES:
        if re.search(issue.pattern, text):
            found.append(issue)
    return found


def scan_docs_for_issues(paths: Iterable[Path]) -> dict[str, list[tuple[Path, int]]]:
    """Map issue id → list of (path, line_number) hits."""
    hits: dict[str, list[tuple[Path, int]]] = {i.id: [] for i in KNOWN_ISSUES}
    compiled = [(issue, re.compile(issue.pattern)) for issue in KNOWN_ISSUES]

    for path in paths:
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for lineno, line in enumerate(lines, start=1):
            for issue, cre in compiled:
                if cre.search(line):
                    hits[issue.id].append((path, lineno))
    return {k: v for k, v in hits.items() if v}


def plmn_from_mcc_mnc(mcc: str, mnc: str) -> str:
    """Build a PLMN string as used by srsRAN gNB configs (MCC + zero-padded MNC)."""
    mcc = mcc.strip()
    mnc = mnc.strip()
    if len(mnc) == 2:
        return f"{mcc}{mnc}"
    return f"{mcc}{mnc}"


def parse_ini_like_kv(text: str) -> dict[str, str]:
    """Parse simple key = value lines from srsRAN-style conf files (ignores sections/comments)."""
    result: dict[str, str] = {}
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("["):
            continue
        if "=" not in stripped:
            continue
        key, _, value = stripped.partition("=")
        result[key.strip()] = value.split("#", 1)[0].strip().strip('"')
    return result


def parse_user_db_rows(text: str) -> list[dict[str, str]]:
    """Parse srsRAN HSS user_db.csv data rows."""
    headers = [
        "Name",
        "Auth",
        "IMSI",
        "Key",
        "OP_Type",
        "OP/OPc",
        "AMF",
        "SQN",
        "QCI",
        "IP_alloc",
    ]
    rows: list[dict[str, str]] = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        parts = [p.strip() for p in stripped.split(",")]
        if len(parts) < len(headers):
            continue
        rows.append(dict(zip(headers, parts[: len(headers)])))
    return rows
