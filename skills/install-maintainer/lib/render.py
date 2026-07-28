#!/usr/bin/env python3
"""Render a maintainer workflow template against a repo's maintainer.json.

    render.py <template> <maintainer.json> [--skill-root DIR] [-o OUT]

Placeholders
    {{NAME}}            scalar from .vars, substituted inline
    {{BLOCK:NAME}}      alone on a line; replaced by a multi-line block,
                        re-indented to the placeholder's own indent
    {{BLOCK:SOURCE_ENV}} generated from .source_env (ordered key/value/comment)

Blocks resolve lockfile .blocks first, then
<skill-root>/sources/<source>/blocks/<NAME>.txt — repo-shaped blocks live with
the repo, source-shaped blocks live with the adapter.

Unresolved placeholders are a hard error: a workflow that reaches GitHub with a
literal {{ in it fails at 2am, not here.
"""

import argparse
import json
import re
import sys
from pathlib import Path

BLOCK_LINE = re.compile(r"^([ \t]*)\{\{BLOCK:([A-Z0-9_]+)\}\}[ \t]*$")
SCALAR = re.compile(r"\{\{([A-Z0-9_]+)\}\}")
# Must not match GitHub Actions expressions (`${{ github.event.x }}`) — those
# legitimately survive rendering. Only our own placeholder shape is an error.
LEFTOVER = re.compile(r"\{\{(?:BLOCK:)?[A-Z0-9_]+\}\}")


def die(msg):
    sys.stderr.write(f"render: {msg}\n")
    sys.exit(1)


def indent_block(text, indent):
    return "\n".join(indent + ln if ln.strip() else ln for ln in text.split("\n"))


def source_env_block(cfg, stage):
    indent = cfg.get("source_env_indent", {}).get(stage, "  ")
    out = []
    for e in cfg.get("source_env", []):
        if stage not in e.get("stages", []):
            continue
        line = f'{indent}{e["key"]}: "{e["value"]}"'
        if e.get("comment"):
            line += f' # {e["comment"]}'
        out.append(line)
    return "\n".join(out)


def resolve_block(name, cfg, skill_root):
    if name.startswith("SOURCE_ENV_"):
        return source_env_block(cfg, name[len("SOURCE_ENV_") :].lower())
    blocks = cfg.get("blocks", {})
    if name in blocks:
        return blocks[name].rstrip("\n")
    path = skill_root / "sources" / cfg["source"] / "blocks" / f"{name}.txt"
    if path.is_file():
        return path.read_text().rstrip("\n")
    die(f"unresolved block {{{{BLOCK:{name}}}}} — not in .blocks, not at {path}")


def render(template, cfg, skill_root):
    variables = cfg.get("vars", {})

    def sub(mo):
        key = mo.group(1)
        if key not in variables:
            die(f"unresolved scalar {{{{{key}}}}} — add it to .vars")
        return str(variables[key])

    out = []
    for raw in template.split("\n"):
        m = BLOCK_LINE.match(raw)
        if m:
            indent, name = m.group(1), m.group(2)
            body = resolve_block(name, cfg, skill_root)
            # Adapter blocks carry placeholders too — the Basecamp triage prompt
            # names the account it assigns to, which must not be baked into the
            # skill folder.
            out.append(indent_block(SCALAR.sub(sub, body), indent))
            continue
        out.append(SCALAR.sub(sub, raw))
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("template")
    ap.add_argument("config")
    ap.add_argument("--skill-root", default=str(Path(__file__).resolve().parent.parent))
    ap.add_argument("-o", "--out")
    args = ap.parse_args()

    cfg = json.loads(Path(args.config).read_text())
    result = render(Path(args.template).read_text(), cfg, Path(args.skill_root))

    stray = LEFTOVER.search(result)
    if stray:
        die(f"template left an unsubstituted placeholder: {stray.group(0)}")

    # Block insertion is indentation-sensitive; a mis-indented block yields YAML
    # that GitHub rejects at push time. Catch it here instead.
    try:
        import yaml

        yaml.safe_load(result)
    except ImportError:
        pass
    except Exception as exc:
        die(f"rendered output is not valid YAML: {exc}")

    if args.out:
        Path(args.out).write_text(result)
    else:
        sys.stdout.write(result)


if __name__ == "__main__":
    main()
