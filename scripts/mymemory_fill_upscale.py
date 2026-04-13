#!/usr/bin/env python3
"""
Eksik upscale.* ve videoedit.resize.* anahtarlarını MyMemory ücretsiz API ile çevirir.
en ve tr dosyalarına dokunmaz (tr elle; en kaynak).
Mevcut satırları kaldırıp dosya sonuna // MARK: - Upscale & video resize (localized) bloğu ekler.
"""
from __future__ import annotations

import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMET = ROOT / "cometeditor"

_LINE_RE = re.compile(r'^"((?:\\.|[^\\"])*)"\s*=\s*"((?:\\.|[^\\"])*)"\s*;\s*$')


def unescape_key(raw: str) -> str:
    return raw.replace('\\"', '"').replace("\\\\", "\\")


def unescape_val(raw: str) -> str:
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


def parse_lines(path: Path) -> tuple[list[str], dict[str, str]]:
    """Satırları koru; ayrıca son 'kazanır' sözlük."""
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    d: dict[str, str] = {}
    for line in lines:
        s = line.strip()
        if not s or s.startswith("//"):
            continue
        m = _LINE_RE.match(s)
        if not m:
            continue
        k = unescape_key(m.group(1))
        d[k] = unescape_val(m.group(2))
    return lines, d


def mymemory_translate(text: str, target: str, cache: dict[tuple[str, str], str]) -> str:
    if target == "en" or not text.strip():
        return text
    key = (text, target)
    if key in cache:
        return cache[key]
    q = urllib.parse.quote(text[:450], safe="")
    url = f"https://api.mymemory.translated.net/get?q={q}&langpair=en|{urllib.parse.quote(target)}"
    try:
        with urllib.request.urlopen(url, timeout=45) as r:
            data = json.loads(r.read().decode())
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
        print(f"WARN translate fail {target!r}: {e}", file=sys.stderr)
        cache[key] = text
        return text
    rd = data.get("responseData") or {}
    out = rd.get("translatedText") or text
    if "MYMEMORY WARNING" in out or "INVALID" in out.upper():
        cache[key] = text
        return text
    cache[key] = out
    return out


def api_lang(locale: str) -> str:
    """MyMemory langpair hedef kodu."""
    special = {
        "zh-Hans": "zh-CN",
        "zh-CN": "zh-CN",
        "zh-Hant-TW": "zh-TW",
        "zh-Hant-HK": "zh-TW",
        "pt-BR": "pt",
        "pt-PT": "pt",
        "en-CA": "en",
        "es-MX": "es",
        "es-AR": "es",
        "es-CL": "es",
        "bs": "hr",
        "gag": "tr",
        "cv": "ru",
        "ba": "ru",
        "tt": "ru",
        "sah": "ru",
        "tyv": "ru",
        "kk": "kk",
        "ky": "ky",
        "uz": "uz",
        "ug": "ug",
        "tk": "tr",
    }
    if locale in special:
        return special[locale]
    if locale.startswith("en"):
        return "en"
    if "-" in locale:
        return locale.split("-")[0]
    return locale


KEYS: list[str] = [
    "upscale.settings.title",
    "upscale.settings.model",
    "upscale.model.cometStandard",
    "upscale.model.scaleHint",
    "upscale.settings.scale",
    "upscale.scale.multiPassHint",
    "upscale.settings.outputFormat",
    "upscale.drop.title",
    "upscale.drop.subtitle",
    "upscale.drop.formats",
    "upscale.wrongType",
    "upscale.runButton",
    "upscale.preview.run",
    "upscale.preview.hint",
    "upscale.preview.processing",
    "upscale.preview.before",
    "upscale.preview.after",
    "upscale.preview.save",
    "upscale.preview.saveSettings",
    "upscale.preview.autoSave",
    "upscale.preview.autoSaveHint",
    "upscale.preview.saveNeedFolder",
    "upscale.preview.saveFailed",
    "upscale.preview.loadFailed",
    "upscale.backend.missing.hint",
    "upscale.error.bundle",
    "upscale.error.binary",
    "upscale.error.model",
    "upscale.error.process",
    "upscale.error.none",
    "videoedit.resize.modePercent",
    "videoedit.resize.modeCustom",
    "videoedit.resize.autoFill",
    "videoedit.resize.autoFillHint",
]

KEY_SET = set(KEYS)


def strip_keys_from_body(text: str) -> str:
    out_lines: list[str] = []
    for line in text.splitlines(keepends=True):
        s = line.strip()
        if not s or s.startswith("//"):
            out_lines.append(line)
            continue
        m = _LINE_RE.match(s)
        if m:
            k = unescape_key(m.group(1))
            if k in KEY_SET:
                continue
        out_lines.append(line)
    return "".join(out_lines).rstrip() + "\n"


def main() -> int:
    en_path = COMET / "en.lproj" / "Localizable.strings"
    _, en_d = parse_lines(en_path)
    missing_any = [k for k in KEYS if k not in en_d]
    if missing_any:
        print("en eksik anahtar:", missing_any, file=sys.stderr)
        return 1

    cache: dict[tuple[str, str], str] = {}
    paths = sorted(COMET.glob("*.lproj/Localizable.strings"))
    for path in paths:
        loc = path.parent.name.removesuffix(".lproj")
        if loc in ("en", "tr"):
            print(f"skip {loc}")
            continue
        tgt = api_lang(loc)
        body = strip_keys_from_body(path.read_text(encoding="utf-8"))
        block_lines = [
            "",
            "// MARK: - Upscale & video resize (mymemory_fill_upscale.py)",
        ]
        for k in KEYS:
            src = en_d[k]
            if tgt == "en":
                trans = src
            else:
                trans = mymemory_translate(src, tgt, cache)
                time.sleep(0.08)
            block_lines.append(f'"{escape_strings_value(k)}" = "{escape_strings_value(trans)}";')
        path.write_text(body.rstrip() + "\n" + "\n".join(block_lines) + "\n", encoding="utf-8")
        print(f"patched {loc} -> api {tgt} ({len(KEYS)} keys)")
    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
