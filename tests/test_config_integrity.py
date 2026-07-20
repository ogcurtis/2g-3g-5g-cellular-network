"""Validate live RF/core configs used on the Blade (student 7)."""

from __future__ import annotations

import re
from pathlib import Path

import pytest
import yaml

from upgrade.compat_matrix import parse_ini_like_kv, parse_user_db_rows, plmn_from_mcc_mnc

EXPECTED_MCC = "001"
EXPECTED_MNC = "08"
EXPECTED_IMSI = "001080000121617"
EXPECTED_KI = "a20087484610f3d99c8b5bc9ebdca461"
EXPECTED_OPC = "53867f4fe1d3af071b8c2a86f5fe50c4"


def test_lte_enb_epc_plmn_aligned(training_root: Path) -> None:
    enb = parse_ini_like_kv((training_root / "4g/conf/enb.conf").read_text())
    epc = parse_ini_like_kv((training_root / "4g/conf/epc.conf").read_text())

    assert enb["mcc"] == EXPECTED_MCC
    assert enb["mnc"] == EXPECTED_MNC
    assert epc["mcc"] == EXPECTED_MCC
    assert epc["mnc"] == EXPECTED_MNC
    assert enb["mme_addr"] == epc.get("mme_bind_addr") or enb["mme_addr"] == "127.0.1.100"


def test_lte_rf_params_present(training_root: Path) -> None:
    enb = parse_ini_like_kv((training_root / "4g/conf/enb.conf").read_text())
    assert enb["dl_earfcn"] == "3650"
    assert enb["n_prb"] == "25"
    assert int(enb["tx_gain"]) > 0
    assert int(enb["rx_gain"]) > 0


def test_user_db_subscriber_matches_sim_values(training_root: Path) -> None:
    rows = parse_user_db_rows((training_root / "4g/conf/user_db.csv").read_text())
    assert rows, "user_db.csv has no subscriber rows"
    ue = rows[0]
    assert ue["IMSI"] == EXPECTED_IMSI
    assert ue["Key"].lower() == EXPECTED_KI
    assert ue["OP/OPc"].lower() == EXPECTED_OPC
    assert ue["Auth"] == "mil"
    assert ue["OP_Type"].lower() == "opc"
    assert re.fullmatch(r"[0-9]{15}", ue["IMSI"])
    assert re.fullmatch(r"[0-9a-fA-F]{32}", ue["Key"])
    assert re.fullmatch(r"[0-9a-fA-F]{32}", ue["OP/OPc"])


def test_sim_values_notes_match_user_db(training_root: Path) -> None:
    text = (training_root / "SIM_Values").read_text(encoding="utf-8", errors="replace")
    assert EXPECTED_IMSI in text
    assert EXPECTED_KI in text
    assert EXPECTED_OPC in text
    assert "00108" in text or "MCC" in text or "Student" in text or "GNB" in text


def test_5g_sa_gnb_plmn_and_amf(training_root: Path) -> None:
    path = training_root / "5g_sa/conf/gnb_rf_b200_tdd_n78_20mhz.yml"
    data = yaml.safe_load(path.read_text())
    assert data["cell_cfg"]["plmn"] == plmn_from_mcc_mnc(EXPECTED_MCC, EXPECTED_MNC)
    assert data["cell_cfg"]["band"] == 78
    assert data["cell_cfg"]["dl_arfcn"] == 636000
    assert data["ru_sdr"]["device_driver"] == "uhd"
    assert "b200" in str(data["ru_sdr"]["device_args"]).lower()
    assert data["amf"]["addr"]
    assert data["amf"]["bind_addr"]


def test_5g_sa_docker_compose_parses(training_root: Path) -> None:
    path = training_root / "5g_sa/conf/docker-compose-basic-nrf.yaml"
    data = yaml.safe_load(path.read_text())
    assert isinstance(data, dict)
    # Compose file v2/v3 style or services-only
    assert "services" in data or "version" in data


def test_5g_nsa_compose_parses(training_root: Path) -> None:
    path = training_root / "5g_nsa/conf/docker-compose.yml"
    data = yaml.safe_load(path.read_text())
    assert isinstance(data, dict)
