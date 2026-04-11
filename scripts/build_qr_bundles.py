#!/usr/bin/env python3
"""en.lproj (qr.*) + i18n/qr_lang_patches.json → i18n/qr_bundles.json."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMET = ROOT / "cometeditor"
EN_PATH = COMET / "en.lproj" / "Localizable.strings"
PATCH_PATH = ROOT / "i18n" / "qr_lang_patches.json"
OUT_PATH = ROOT / "i18n" / "qr_bundles.json"
WM_PATH = ROOT / "i18n" / "watermark_bundles.json"

_LINE = re.compile(r'^"(qr\.[^"]+)"\s*=\s*"(.*)";\s*$')


def unesc(s: str) -> str:
    return s.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")


def parse_qr_en(path: Path) -> dict[str, str]:
    d: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = _LINE.match(line.strip())
        if m:
            d[m.group(1)] = unesc(m.group(2))
    d.setdefault("qr.wifi.enc.wpa", "WPA/WPA2")
    d.setdefault("qr.wifi.enc.wep", "WEP")
    d.setdefault("qr.settings.sizeUnit", "px")
    return d


def logical_lang(code: str) -> str:
    if code in ("zh-Hans", "zh-CN"):
        return "zh_Hans"
    if code in ("zh-Hant-TW", "zh-Hant-HK"):
        return "zh_Hant"
    if code.startswith("es-"):
        return "es"
    if code.startswith("pt-"):
        return "pt"
    if code == "en-CA":
        return "en"
    if code in ("gag", "tk"):
        return "tr"
    if code in ("ky", "ba", "tt", "cv", "tyv", "alt", "sah", "mk", "ug"):
        return "ru"
    return code


def bundle_for(code: str, en: dict[str, str], patches: dict[str, dict[str, str]]) -> dict[str, str]:
    base = dict(en)
    lg = logical_lang(code)
    if lg in patches:
        base.update(patches[lg])
    elif lg.split("-")[0] in patches:
        base.update(patches[lg.split("-")[0]])
    elif "_" in lg:
        a, _, b = lg.partition("_")
        stem = f"{a}_{b}" if b else lg
        if stem in patches:
            base.update(patches[stem])
    return base


def main() -> int:
    en = parse_qr_en(EN_PATH)
    patches: dict[str, dict[str, str]] = json.loads(PATCH_PATH.read_text(encoding="utf-8"))
    wm = json.loads(WM_PATH.read_text(encoding="utf-8"))
    langs = sorted(wm.keys())

    out = {code: bundle_for(code, en, patches) for code in langs}
    OUT_PATH.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUT_PATH} ({len(out)} langs)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
