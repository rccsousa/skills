#!/usr/bin/env python3
"""Prove a template set still renders the workflows it was extracted from.

    roundtrip.py <maintainer.json> --live triage=<path> [--live implement=<path>] ...

Two diffs, two different jobs:

  CODE PARITY (hard gate) — comments and blank lines stripped from both sides,
  then compared byte for byte. This must be empty. It is the whole claim of the
  extraction: no runnable line changed.

  FULL DIFF (advisory) — printed for review. Comment rewording is expected and
  intended; generalising repo-specific prose out of the headers is the point.
"""

import argparse
import difflib
import subprocess
import sys
from pathlib import Path

SKILL = Path(__file__).resolve().parent.parent


def code_only(text):
    out = []
    for ln in text.split("\n"):
        stripped = ln.strip()
        if not stripped or stripped.startswith("#"):
            continue
        out.append(ln.rstrip())
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("config")
    ap.add_argument("--live", action="append", required=True,
                    metavar="STAGE=PATH", help="repeatable, e.g. triage=.github/workflows/x.yml")
    ap.add_argument("--full-diff", action="store_true")
    args = ap.parse_args()

    failures = 0
    for pair in args.live:
        stage, live_path = pair.split("=", 1)
        template = SKILL / "templates" / f"maintainer-{stage}.yml.tmpl"
        rendered = subprocess.run(
            [sys.executable, str(SKILL / "lib/render.py"), str(template), args.config],
            capture_output=True, text=True)
        if rendered.returncode != 0:
            print(f"FAIL {stage}: render errored\n{rendered.stderr}")
            failures += 1
            continue

        live = Path(live_path).read_text()
        got, want = code_only(rendered.stdout), code_only(live)

        if got == want:
            print(f"PASS {stage}: {len(want)} runnable lines identical")
        else:
            failures += 1
            print(f"FAIL {stage}: code parity broken")
            for ln in difflib.unified_diff(want, got, "live", "rendered", lineterm="", n=2):
                print("   " + ln)

        if args.full_diff:
            print(f"\n--- {stage}: full diff (comments included, advisory) ---")
            for ln in difflib.unified_diff(live.split("\n"), rendered.stdout.split("\n"),
                                           "live", "rendered", lineterm="", n=1):
                print("   " + ln)

    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
