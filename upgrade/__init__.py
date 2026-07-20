"""Ubuntu LTS upgrade compatibility helpers for the telco training stack."""

from .compat_matrix import LTS_RELEASES, CompatibilityIssue, scan_docs_for_issues

__all__ = [
    "LTS_RELEASES",
    "CompatibilityIssue",
    "scan_docs_for_issues",
]
