#!/usr/bin/env python3
"""home.* anahtarlarını i18n/home_bundles.json ile tüm .lproj dosyalarına yazar."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMET = ROOT / "cometeditor"
BUNDLES_PATH = ROOT / "i18n" / "home_bundles.json"

_LINE_RE = re.compile(r'^"(home\.[^"]+)"\s*=\s*"((?:\\.|[^\\"])*)"\s*;\s*$')


def unescape(raw: str) -> str:
    out: list[str] = []
    i = 0
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


def escape(raw: str) -> str:
    return raw.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def parse_home_keys(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if not s or s.startswith("//"):
            continue
        m = _LINE_RE.match(s)
        if m:
            out[m.group(1)] = unescape(m.group(2))
    return out


def patch_strings_file(path: Path, trans: dict[str, str]) -> int:
    text = path.read_text(encoding="utf-8")
    changed = 0
    for key, val in trans.items():
        pattern = re.compile(rf'^"{re.escape(key)}"\s*=\s*".*";$', re.MULTILINE)
        new_line = f'"{key}" = "{escape(val)}";'
        new_text, n = pattern.subn(new_line, text, count=1)
        if n:
            text = new_text
            changed += n
        else:
            if not text.endswith("\n"):
                text += "\n"
            text += f'"{key}" = "{escape(val)}";\n'
            changed += 1
    path.write_text(text, encoding="utf-8")
    return changed


def resolve_bundle(lang: str, bundles: dict[str, dict[str, str]], tr_strings: dict[str, str]) -> dict[str, str]:
    if lang == "tr":
        merged = dict(bundles.get("en", {}))
        merged.update(tr_strings)
        return merged
    if lang in ("zh-Hans", "zh-CN"):
        return bundles["zh_Hans"]
    if lang in ("zh-Hant-TW", "zh-Hant-HK"):
        return bundles["zh_Hant"]
    if lang.startswith("es-"):
        return bundles["es"]
    if lang.startswith("pt-"):
        return bundles["pt"]
    if lang == "en-CA":
        return bundles["en"]
    if lang in ("gag", "tk"):
        merged = dict(bundles.get("en", {}))
        merged.update(tr_strings)
        return merged
    if lang in ("ky", "ba", "tt", "cv", "tyv", "alt", "sah", "mk", "ug"):
        return bundles["ru"]
    if lang in bundles:
        return bundles[lang]
    stem = lang.split("-")[0]
    if stem in bundles:
        return bundles[stem]
    return bundles["en"]


def main() -> int:
    if not BUNDLES_PATH.is_file():
        print(f"Eksik: {BUNDLES_PATH} — önce: python3 scripts/gen_home_bundles_mt.py", file=sys.stderr)
        return 1
    bundles: dict[str, dict[str, str]] = json.loads(BUNDLES_PATH.read_text(encoding="utf-8"))
    tr_path = COMET / "tr.lproj" / "Localizable.strings"
    tr_strings = parse_home_keys(tr_path)

    total = 0
    for lproj in sorted(COMET.glob("*.lproj")):
        lang = lproj.name.removesuffix(".lproj")
        path = lproj / "Localizable.strings"
        if not path.is_file():
            continue
        trans = resolve_bundle(lang, bundles, tr_strings)
        n = patch_strings_file(path, trans)
        if n:
            print(f"{lang}: updated {n} home.* keys")
        total += n
    print(f"done, total operations: {total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
