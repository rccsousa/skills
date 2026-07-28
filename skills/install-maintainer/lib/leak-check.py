#!/usr/bin/env python3
"""Fail if the skill folder carries anything repo-, account- or person-specific.

This folder is mirrored to a public skills repo. Every id, handle and address
belongs in the target repo's .github/maintainer.json, never here — so the mirror
has nothing to sanitize. Run before publishing, and from the skill's own checks.

    leak-check.py [skill-root]
"""

import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent

PATTERNS = [
    ("long digit run (tracker/account id)", re.compile(r"(?<![\w.])\d{7,}(?![\w.])")),
    ("email address", re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+")),
    ("sha256 literal", re.compile(r"\b[0-9a-f]{64}\b")),
]

# Documented placeholder examples are the one legitimate way these shapes appear.
# The github-actions[bot] identity is a GitHub-wide constant, not repo-specific.
ALLOW = re.compile(r"\{\{|<[A-Z_]+>|e\.g\.|example|41898282\+github-actions")

findings = []
for path in sorted(ROOT.rglob("*")):
    if not path.is_file() or ".git" in path.parts:
        continue
    try:
        text = path.read_text()
    except UnicodeDecodeError:
        continue
    for lineno, line in enumerate(text.split("\n"), 1):
        if ALLOW.search(line):
            continue
        for label, pattern in PATTERNS:
            hit = pattern.search(line)
            if hit:
                rel = path.relative_to(ROOT)
                findings.append(f"{rel}:{lineno}: {label}: {hit.group(0)}")

if findings:
    print("LEAK CHECK FAILED — move these into the target repo's maintainer.json:")
    for f in findings:
        print("  " + f)
    sys.exit(1)

print(f"leak check clean: {ROOT}")
