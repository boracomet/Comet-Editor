#!/usr/bin/env python3
"""
Rebuild every cometeditor/*.lproj/Localizable.strings from i18n/master.json.

- Same key set and order in every locale
- Existing translations kept when present
- Deleted-feature keys never written (already absent from master)
- New locales: load i18n/packs/<locale>.json if present
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMET = ROOT / "cometeditor"
MASTER = ROOT / "i18n" / "master.json"
PACKS = ROOT / "i18n" / "packs"

_LINE_RE = re.compile(r'^"((?:\\.|[^\\"])*)"\s*=\s*"((?:\\.|[^\\"])*)"\s*;\s*$')

# Keys that are format lists, codes, or brand tokens — keep English.
IDENTITY_KEYS = {
    "convert.drop.formats",
    "upscale.drop.formats",
    "video.drop.formats",
    "home.quick.pngWebp.title",
    "home.preset.pngAvif.title",
    "home.preset.jpgWebp.title",
    "home.preset.mp4ToGif.title",
    "home.preset.aviToMp4.title",
    "home.preset.movToMp4.title",
    "video.fps.60",
    "video.fps.30",
    "video.fps.24",
    "pdf.tools.resolution.75",
    "pdf.tools.resolution.50",
    "pdf.tools.resolution.25",
    "pdf.addContent.typePDF",
    "qr.wifi.enc.wpa",
    "qr.wifi.enc.wep",
    "qr.settings.sizeUnit",
    "app.version",
    "font.typography.weightPair",
    "font.typography.weightPairItalic",
}


def unescape(raw: str) -> str:
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


def escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def parse_strings(path: Path) -> dict[str, str]:
    if not path.is_file():
        return {}
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if not s or s.startswith("//"):
            continue
        m = _LINE_RE.match(s)
        if m:
            out[unescape(m.group(1))] = unescape(m.group(2))
    return out


def load_master() -> tuple[list[str], dict[str, str]]:
    data = json.loads(MASTER.read_text(encoding="utf-8"))
    keys = data["keys"]
    # Preserve insertion order from master.json
    return list(keys.keys()), keys


def write_strings(path: Path, ordered_keys: list[str], values: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "/* Comet Editor — Localizable.strings */",
        "/* Regenerated from i18n/master.json. Do not mix deleted-feature keys. */",
        "",
    ]
    prev_prefix = ""
    for key in ordered_keys:
        prefix = key.split(".", 1)[0]
        if prev_prefix and prefix != prev_prefix:
            lines.append("")
        prev_prefix = prefix
        val = values[key]
        lines.append(f'"{escape(key)}" = "{escape(val)}";')
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def existing_locales() -> list[str]:
    return sorted(p.parent.name.removesuffix(".lproj") for p in COMET.glob("*.lproj/Localizable.strings"))


def load_pack(locale: str) -> dict[str, str]:
    p = PACKS / f"{locale}.json"
    if not p.is_file():
        return {}
    return json.loads(p.read_text(encoding="utf-8"))


def merge_values(
    ordered_keys: list[str],
    en: dict[str, str],
    *sources: dict[str, str],
) -> dict[str, str]:
    out: dict[str, str] = {}
    for key in ordered_keys:
        if key in IDENTITY_KEYS:
            out[key] = en[key]
            continue
        chosen = None
        for src in sources:
            if key in src and src[key].strip():
                chosen = src[key]
                break
        out[key] = chosen if chosen is not None else en[key]
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="Comma-separated locales to rewrite")
    args = ap.parse_args()
    if not MASTER.is_file():
        print("missing i18n/master.json", file=sys.stderr)
        return 1
    ordered, en = load_master()
    targets = existing_locales()
    pack_locales = [
        p.stem for p in PACKS.glob("*.json") if PACKS.is_dir() and not p.stem.startswith("_")
    ]
    for loc in pack_locales:
        if loc not in targets:
            targets.append(loc)
    if args.only:
        want = {x.strip() for x in args.only.split(",") if x.strip()}
        targets = [t for t in targets if t in want]
    targets = sorted(set(targets))

    for loc in targets:
        existing = parse_strings(COMET / f"{loc}.lproj" / "Localizable.strings")
        pack = load_pack(loc)
        if loc in ("en", "en-CA"):
            values = merge_values(ordered, en, existing if loc == "en-CA" else {}, en)
            if loc == "en":
                values = dict(en)
        else:
            values = merge_values(ordered, en, pack, existing)
        write_strings(COMET / f"{loc}.lproj" / "Localizable.strings", ordered, values)
        missing = [k for k in ordered if values[k] == en[k] and k not in IDENTITY_KEYS]
        print(f"{loc}: {len(ordered)} keys  english-fallback {len(missing)}")
    print(f"done ({len(targets)} locales, {len(ordered)} keys)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
