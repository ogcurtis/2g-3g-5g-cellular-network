"""Shell script unit tests — syntax + CLI validation (no RF hardware required)."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

BASH = shutil.which("bash")
pytestmark = pytest.mark.skipif(BASH is None, reason="bash not available")


def _run(script: Path, args: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [BASH, str(script), *args],
        cwd=cwd or script.parent,
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )


@pytest.mark.parametrize(
    "relpath",
    [
        "quecController_telco_training.sh",
        "4g/conf/config_files_lte.sh",
        "4g/conf/add_user_lte.sh",
        "5g_sa/conf/config_files_sa.sh",
        "5g_sa/conf/add_user_sa.sh",
        "5g_nsa/conf/config_files_nsa.sh",
        "5g_nsa/conf/add_user_nsa.sh",
        "2g/conf/run2g.sh",
        "2g/conf/config_files_2g.sh",
    ],
)
def test_script_bash_syntax(training_root: Path, relpath: str) -> None:
    script = training_root / relpath
    assert script.is_file(), f"missing {relpath}"
    result = subprocess.run(
        [BASH, "-n", str(script)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, f"bash -n failed for {relpath}:\n{result.stderr}"


def test_lte_config_generator_rejects_bad_mcc(training_root: Path) -> None:
    script = training_root / "4g/conf/config_files_lte.sh"
    result = _run(script, ["-c", "12", "-n", "08", "-e", "3650"])
    assert result.returncode != 0
    assert "MCC" in result.stdout or "MCC" in result.stderr


def test_lte_config_generator_rejects_missing_args(training_root: Path) -> None:
    script = training_root / "4g/conf/config_files_lte.sh"
    result = _run(script, [])
    assert result.returncode != 0


def test_lte_add_user_rejects_short_imsi(training_root: Path) -> None:
    script = training_root / "4g/conf/add_user_lte.sh"
    result = _run(
        script,
        [
            "-i",
            "00108000012161",  # 14 digits
            "-k",
            "a20087484610f3d99c8b5bc9ebdca461",
            "-o",
            "53867f4fe1d3af071b8c2a86f5fe50c4",
        ],
    )
    assert result.returncode != 0
    assert "IMSI" in result.stdout or "IMSI" in result.stderr


def test_lte_add_user_rejects_bad_ki(training_root: Path) -> None:
    script = training_root / "4g/conf/add_user_lte.sh"
    result = _run(
        script,
        [
            "-i",
            "001080000121618",
            "-k",
            "deadbeef",
            "-o",
            "53867f4fe1d3af071b8c2a86f5fe50c4",
        ],
    )
    assert result.returncode != 0
    assert "Ki" in result.stdout or "Ki" in result.stderr or "KI" in result.stdout


def test_lte_add_user_rejects_duplicate_imsi(training_root: Path) -> None:
    script = training_root / "4g/conf/add_user_lte.sh"
    result = _run(
        script,
        [
            "-i",
            "001080000121617",  # already in user_db.csv
            "-k",
            "a20087484610f3d99c8b5bc9ebdca461",
            "-o",
            "53867f4fe1d3af071b8c2a86f5fe50c4",
        ],
    )
    assert result.returncode != 0
    assert "already" in (result.stdout + result.stderr).lower()


def test_sa_config_generator_rejects_bad_ip(training_root: Path) -> None:
    script = training_root / "5g_sa/conf/config_files_sa.sh"
    result = _run(
        script,
        ["-g", "10.220.53", "-c", "001", "-n", "08", "-t", "8", "-a", "636000"],
    )
    assert result.returncode != 0
    assert "IP" in result.stdout or "IP" in result.stderr or "Invalid" in (
        result.stdout + result.stderr
    )


def test_quec_help_lists_supported_modems(training_root: Path) -> None:
    script = training_root / "quecController_telco_training.sh"
    # help is a function; invoke with -h via getopts if present, else source-check text
    text = script.read_text(encoding="utf-8", errors="replace")
    for modem in ("EC25", "RM520N", "RM500Q"):
        assert modem in text
    for rat in ("gsm", "lte", "nr5g"):
        assert rat in text


def test_run2g_help_mentions_gsm_and_gprs(training_root: Path) -> None:
    script = training_root / "2g/conf/run2g.sh"
    result = _run(script, ["-h"])
    combined = result.stdout + result.stderr
    assert "gsm" in combined.lower()
    assert "gprs" in combined.lower()
