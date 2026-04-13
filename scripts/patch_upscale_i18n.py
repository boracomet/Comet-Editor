#!/usr/bin/env python3
"""
Upscale + videoedit.resize.* satırlarını .lproj içinde anahtara göre günceller
(satır sırası / alfabetik veya anlamsal blok fark etmez).

Kullanım (proje kökünden):
  python3 scripts/patch_upscale_i18n.py

Veri: scripts/upscale_translations_data.py içindeki TABLES sözlüğü.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMETEDITOR = ROOT / "cometeditor"

_LINE_RE = re.compile(r'^"((?:\\.|[^\\"])*)"\s*=\s*"((?:\\.|[^\\"])*)"\s*;\s*$')


def unescape_strings_value(raw: str) -> str:
    i = 0
    out: list[str] = []
    while i < len(raw):
        if raw[i] == "\\" and i + 1 < len(raw):
            n = raw[i + 1]
            if n == "n":
                out.append("\n")
                i += 2
                continue
            if n == "t":
                out.append("\t")
                i += 2
                continue
            if n in ('"', "\\"):
                out.append(n)
                i += 2
                continue
        out.append(raw[i])
        i += 1
    return "".join(out)


def escape_strings_value(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def patch_file(path: Path, trans: dict[str, str]) -> tuple[int, int]:
    raw = path.read_text(encoding="utf-8")
    original = raw
    lines = raw.splitlines(keepends=True)
    hits = 0
    replaced = 0
    for i, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        m = _LINE_RE.match(stripped)
        if not m:
            continue
        key = unescape_strings_value(m.group(1))
        if key not in trans:
            continue
        hits += 1
        new_val = trans[key]
        if unescape_strings_value(m.group(2)) == new_val:
            continue
        indent = line[: len(line) - len(line.lstrip(" \t"))]
        if line.endswith("\r\n"):
            suffix = "\r\n"
        elif line.endswith("\n"):
            suffix = "\n"
        else:
            suffix = ""
        lines[i] = f'{indent}"{escape_strings_value(key)}" = "{escape_strings_value(new_val)}";{suffix}'
        replaced += 1
    text = "".join(lines)
    text = text.replace(
        "// MARK: - Upscale & video resize (mymemory_fill_upscale.py)",
        "// MARK: - Upscale & video resize (localized)",
    )
    if text != original:
        path.write_text(text, encoding="utf-8")
    return hits, replaced


def main() -> int:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from upscale_translations_data import TABLES  # noqa: E402

    total_r = 0
    for lproj in sorted(COMETEDITOR.glob("*.lproj")):
        loc = lproj.name.removesuffix(".lproj")
        if loc not in TABLES:
            continue
        p = lproj / "Localizable.strings"
        if not p.is_file():
            continue
        h, r = patch_file(p, TABLES[loc])
        if h:
            print(f"{loc}: keys matched {h}, lines updated {r}")
        total_r += r
    print(f"Total lines updated: {total_r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
