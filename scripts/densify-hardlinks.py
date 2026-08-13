#!/usr/bin/env python3
"""Break hardlinks so Docker context owns unique file bytes."""
from __future__ import annotations

import os
import sys
from pathlib import Path


def densify(root: Path) -> int:
    if not root.exists():
        return 0
    n = 0
    for dirpath, _, files in os.walk(root):
        for name in files:
            p = Path(dirpath) / name
            try:
                st = p.stat()
            except FileNotFoundError:
                continue
            if st.st_nlink <= 1:
                continue
            tmp = p.with_name(p.name + ".__u")
            with open(p, "rb") as src, open(tmp, "wb") as dst:
                while True:
                    chunk = src.read(1024 * 1024)
                    if not chunk:
                        break
                    dst.write(chunk)
            os.chmod(tmp, st.st_mode)
            os.replace(tmp, p)
            n += 1
    return n


def main() -> int:
    total = 0
    for arg in sys.argv[1:]:
        total += densify(Path(arg))
    print(f"densified {total} hardlinked files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
