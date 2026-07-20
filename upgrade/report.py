"""Print upgrade debt found in training docs/scripts.

Usage (from training/):
  python3 -m upgrade.report
  python3 -m upgrade.report --target 26.04
"""

from __future__ import annotations

import argparse
from pathlib import Path

from .compat_matrix import KNOWN_ISSUES, LTS_RELEASES, issues_for_target, scan_docs_for_issues

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DOCS = [
    ROOT / "README.md",
    ROOT / "commands_cheatsheet.txt",
    ROOT / "quecController_telco_training.sh",
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--target",
        default="26.04",
        choices=[r["version"] for r in LTS_RELEASES],
        help="Ubuntu LTS version you are porting toward",
    )
    args = parser.parse_args()

    relevant = {i.id: i for i in issues_for_target(args.target)}
    hits = scan_docs_for_issues(p for p in DEFAULT_DOCS if p.is_file())

    print(f"Ubuntu LTS port checklist → {args.target}")
    print("=" * 60)
    for issue in KNOWN_ISSUES:
        if issue.id not in relevant:
            continue
        status = "HIT" if issue.id in hits else "clean"
        print(f"\n[{issue.severity:7}] {issue.id} ({status})")
        print(f"  broken on: {issue.first_broken_on}+")
        print(f"  problem:   {issue.summary}")
        print(f"  fix:       {issue.fix}")
        if issue.id in hits:
            for path, lineno in hits[issue.id][:8]:
                print(f"  at:        {path.relative_to(ROOT)}:{lineno}")

    remaining = [i for i in relevant if i in hits]
    print("\n" + "=" * 60)
    print(f"{len(remaining)} issue(s) still present in docs/scripts for {args.target}")
    return 1 if remaining else 0


if __name__ == "__main__":
    raise SystemExit(main())
