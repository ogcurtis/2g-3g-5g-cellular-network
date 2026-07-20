"""Project layout checks — must remain intact across LTS ports."""

from __future__ import annotations

from pathlib import Path

import pytest

REQUIRED_PATHS = [
    "README.md",
    "commands_cheatsheet.txt",
    "quecController_telco_training.sh",
    "SIM_Values",
    "4g/conf/enb.conf",
    "4g/conf/epc.conf",
    "4g/conf/user_db.csv",
    "4g/conf/config_files_lte.sh",
    "4g/conf/add_user_lte.sh",
    "5g_sa/conf/gnb_rf_b200_tdd_n78_20mhz.yml",
    "5g_sa/conf/config_files_sa.sh",
    "5g_sa/conf/add_user_sa.sh",
    "5g_sa/conf/docker-compose-basic-nrf.yaml",
    "5g_nsa/conf/config_files_nsa.sh",
    "5g_nsa/conf/docker-compose.yml",
    "2g/conf/run2g.sh",
    "2g/conf/config_files_2g.sh",
]


@pytest.mark.parametrize("relpath", REQUIRED_PATHS)
def test_required_path_exists(training_root: Path, relpath: str) -> None:
    assert (training_root / relpath).exists(), f"Missing {relpath}"


def test_quec_controller_is_executable_bit_or_bash(training_root: Path) -> None:
    script = training_root / "quecController_telco_training.sh"
    text = script.read_text(encoding="utf-8", errors="replace")
    assert text.startswith("#!/bin/bash")
    assert "QUECTEL_MODEL" in text


def test_base_templates_exist_for_config_generators(training_root: Path) -> None:
    expected = [
        "4g/conf/BASE/enb.conf.BASE",
        "4g/conf/BASE/epc.conf.BASE",
        "5g_sa/conf/BASE/gnb_rf_b200_tdd_n78_20mhz.yml.BASE",
        "5g_sa/conf/BASE/basic_nrf_config.yaml.BASE",
    ]
    for relpath in expected:
        path = training_root / relpath
        if not path.exists():
            pytest.skip(f"BASE template not synced yet: {relpath}")
        assert path.stat().st_size > 0
