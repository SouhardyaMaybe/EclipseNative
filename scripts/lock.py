#!/usr/bin/env python3
"""Read the source lock without external dependencies.

Usage:
    lock.py --names
    lock.py --check
    lock.py <source> <url|sha256|root|version|license>
"""
from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOCK = ROOT / "sources.lock.json"


def load() -> dict:
    with LOCK.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if data.get("schema") != 1:
        raise SystemExit(f"{LOCK}: unsupported schema {data.get('schema')!r}")
    return data["sources"]


def main(argv: list[str]) -> int:
    sources = load()

    if argv == ["--names"]:
        print("\n".join(sorted(sources)))
        return 0

    if argv == ["--check"]:
        problems = []
        for name, source in sources.items():
            for field in ("url", "sha256", "root", "version", "license"):
                if not source.get(field):
                    problems.append(f"{name}: missing {field}")
            digest = source.get("sha256", "")
            if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
                problems.append(f"{name}: sha256 is not a lowercase hex digest")
            if not source.get("url", "").startswith("https://"):
                problems.append(f"{name}: url is not HTTPS")
        if problems:
            for problem in problems:
                print(f"lock: {problem}", file=sys.stderr)
            return 1
        print(f"lock: {len(sources)} source(s), schema 1, all fields present")
        return 0

    if len(argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    name, field = argv
    if name not in sources:
        print(f"lock: unknown source {name!r}", file=sys.stderr)
        return 2
    value = sources[name].get(field)
    if value is None:
        print(f"lock: {name!r} has no {field!r}", file=sys.stderr)
        return 2
    print(value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
