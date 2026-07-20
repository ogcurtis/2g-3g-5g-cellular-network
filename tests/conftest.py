"""Shared fixtures for training upgrade unit tests."""

from __future__ import annotations

from pathlib import Path

import pytest

TRAINING_ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="session")
def training_root() -> Path:
    return TRAINING_ROOT


@pytest.fixture(scope="session")
def doc_paths(training_root: Path) -> list[Path]:
    paths = [
        training_root / "README.md",
        training_root / "commands_cheatsheet.txt",
        training_root / "quecController_telco_training.sh",
    ]
    missing = [p for p in paths if not p.is_file()]
    if missing:
        pytest.fail(f"Missing required training files: {missing}")
    return paths


@pytest.fixture(scope="session")
def shell_scripts(training_root: Path) -> list[Path]:
    scripts = sorted(training_root.rglob("*.sh"))
    # Ignore vendor/build trees that may appear as the full rsync completes
    ignored_parts = {"src", "build", "uhd_releases", ".git", "tests"}
    filtered = [
        p
        for p in scripts
        if not any(part in ignored_parts for part in p.parts)
    ]
    assert filtered, "Expected at least one training shell script"
    return filtered
