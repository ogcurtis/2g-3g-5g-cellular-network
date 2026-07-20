"""Ubuntu LTS upgrade compatibility tests (20.04 → 22.04 → 24.04 → 26.04)."""

from __future__ import annotations

from pathlib import Path

import pytest

from upgrade.compat_matrix import (
    KNOWN_ISSUES,
    LTS_RELEASES,
    issues_for_target,
    plmn_from_mcc_mnc,
    scan_docs_for_issues,
    scan_text,
)

# Hazards that must be cleared before the 20.04 → 22.04 hop.
REQUIRED_CLEAN_FOR_22_04 = (
    "libncurses5",
    "python39-pin",
    "docker-compose-v1",
    "docker-compose-v1-binary-url",
    "git-core-transitional",
    "ubuntu-20-only-docs",
)


def test_lts_path_includes_baseline_and_ubuntu_26() -> None:
    versions = [r["version"] for r in LTS_RELEASES]
    assert versions[0] == "20.04"
    assert versions[-1] == "26.04"
    assert "22.04" in versions
    assert "24.04" in versions


def test_python_versions_increase_along_lts_path() -> None:
    pythons = [tuple(map(int, r["python"].split("."))) for r in LTS_RELEASES]
    assert pythons == sorted(pythons)
    assert pythons[0] == (3, 8)
    assert pythons[-1] >= (3, 13)


@pytest.mark.parametrize(
    "issue_id",
    ["libncurses5", "python39-pin", "docker-compose-v1", "var-log-syslog", "ubuntu-20-only-docs"],
)
def test_known_blocker_catalog_contains_critical_ids(issue_id: str) -> None:
    ids = {i.id for i in KNOWN_ISSUES}
    assert issue_id in ids


def test_issues_accumulate_toward_26_04() -> None:
    at_22 = {i.id for i in issues_for_target("22.04")}
    at_24 = {i.id for i in issues_for_target("24.04")}
    at_26 = {i.id for i in issues_for_target("26.04")}
    assert at_22 <= at_24 <= at_26
    assert "libncurses5" in at_22
    assert "var-log-syslog" in at_24
    assert "var-log-syslog" in at_26


def test_22_04_doc_hazards_are_cleared(doc_paths: list[Path]) -> None:
    """Docs/scripts must be ready for the first LTS hop to Ubuntu 22.04."""
    hits = scan_docs_for_issues(doc_paths)
    still_open = [issue_id for issue_id in REQUIRED_CLEAN_FOR_22_04 if issue_id in hits]
    assert not still_open, f"22.04 blockers still present: {still_open} → {hits}"


def test_quec_controller_has_journalctl_fallback(training_root: Path) -> None:
    text = (training_root / "quecController_telco_training.sh").read_text(
        encoding="utf-8", errors="replace"
    )
    assert "journalctl" in text
    assert "find_quec_usbdevice" in text
    # Must not use raw syslog-only pipeline without fallback
    syslog_only = [i for i in KNOWN_ISSUES if i.id == "var-log-syslog"]
    assert not scan_text(text, syslog_only)


def test_each_issue_has_actionable_fix() -> None:
    for issue in KNOWN_ISSUES:
        assert issue.fix.strip(), f"{issue.id} missing fix guidance"
        assert issue.severity in {"blocker", "high", "medium", "low"}
        assert issue.first_broken_on in {r["version"] for r in LTS_RELEASES}


def test_upgrade_checklist_for_26_04_is_non_empty() -> None:
    checklist = issues_for_target("26.04")
    assert len(checklist) >= 5
    blockers = [i for i in checklist if i.severity == "blocker"]
    assert blockers, "Expected at least one blocker before Ubuntu 26.04"


def test_plmn_helper_matches_srsran_gnb_format() -> None:
    assert plmn_from_mcc_mnc("001", "08") == "00108"
    assert plmn_from_mcc_mnc("001", "001") == "001001"


def test_scan_text_detects_compose_v1_hazards() -> None:
    curl = (
        'sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/'
        'docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose'
    )
    cli = "sudo docker-compose -f docker-compose-basic-nrf.yaml down"
    assert "docker-compose-v1-binary-url" in {i.id for i in scan_text(curl)}
    assert "docker-compose-v1" in {i.id for i in scan_text(cli)}


def test_docs_prefer_compose_v2_plugin(doc_paths: list[Path]) -> None:
    combined = "\n".join(p.read_text(encoding="utf-8", errors="replace") for p in doc_paths)
    assert "docker-compose-plugin" in combined
    assert "docker compose" in combined
    assert "libncurses-dev" in combined
    assert "python3.9" not in combined


def test_report_22_04_is_printable(doc_paths: list[Path]) -> None:
    hits = scan_docs_for_issues(doc_paths)
    open_22 = [i for i in REQUIRED_CLEAN_FOR_22_04 if i in hits]
    assert open_22 == []
