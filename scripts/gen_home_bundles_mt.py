#!/usr/bin/env python3
"""
en.lproj içindeki tüm home.* anahtarları için çok dilli paket üretir.

- Önce her dilin mevcut .lproj dosyasındaki home.* değerleri okunur; İngilizce
  metinden farklıysa korunur (de, tr gibi elle zaten çevrilmiş satırlar).
- Eksik anahtarlar için MyMemory açık API kullanılır (önbellek: i18n/.home_mt_cache.json).

Kullanım:
  python3 scripts/gen_home_bundles_mt.py
  HOME_MT_DELAY=0.25 python3 scripts/gen_home_bundles_mt.py   # istekler arası gecikme (sn)
"""
from __future__ import annotations

import hashlib
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
EN_PATH = COMET / "en.lproj" / "Localizable.strings"
WM_PATH = ROOT / "i18n" / "watermark_bundles.json"
OUT_PATH = ROOT / "i18n" / "home_bundles.json"
CACHE_PATH = ROOT / "i18n" / ".home_mt_cache.json"
# Biçim / kısaltma aynı kalsın (→, codec adları)

_LINE_RE = re.compile(r'^"(home\.[^"]+)"\s*=\s*"((?:\\.|[^\\"])*)"\s*;\s*$')

_os = __import__("os")
DELAY = float(_os.environ.get("HOME_MT_DELAY", "0.22"))
# Virgülle sınırlı dil listesi (örn. "fi,fr") — boşsa watermark’taki tüm diller (en hariç)
_MT_ONLY = [x.strip() for x in _os.environ.get("HOME_MT_LANGS", "").split(",") if x.strip()]


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
    d: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if not s or s.startswith("//"):
            continue
        m = _LINE_RE.match(s)
        if m:
            d[m.group(1)] = unescape(m.group(2))
    return d


def lproj_for_logical(lang: str) -> Path | None:
    """watermark / videoedit mantıksal dil kodu → .lproj klasör adı."""
    special = {
        "zh_Hans": "zh-Hans",
        "zh_Hant": "zh-Hant-TW",
    }
    name = special.get(lang, lang)
    p = COMET / f"{name}.lproj" / "Localizable.strings"
    if p.is_file():
        return p
    if lang == "zh_Hant":
        p2 = COMET / "zh-Hant-HK.lproj" / "Localizable.strings"
        if p2.is_file():
            return p2
    return None


def should_skip_mt(key: str, text: str) -> bool:
    if "→" in text:
        return True
    if key in (
        "home.preset.aviToMp4.title",
        "home.preset.movToMp4.title",
        "home.preset.mp4ToGif.title",
        "home.preset.pngAvif.title",
        "home.preset.jpgWebp.title",
        "home.quick.pngWebp.title",
    ):
        return True
    return False


def mymemory_translate(text: str, target: str, cache: dict[str, str]) -> str:
    if not text.strip():
        return text
    ck = f"{target}::{hashlib.sha256(text.encode()).hexdigest()}"
    if ck in cache:
        return cache[ck]
    pair = f"en|{target.replace('_', '-')}"
    # API hedef kodları: fi, fr, de, es, it, nl, pl, pt, ru, ja, ko, zh-CN, zh-TW, sv, da, nb, cs, sk, hu, ro, el, he, id, vi, th, ms, bg, hr, bs, sl, sq, et, lt, lv, kk, az, uz, hi, bn, ur, hy, ka, is, sr, uk
    pair_map = {
        "zh_Hans": "en|zh-CN",
        "zh_Hant": "en|zh-TW",
        "no": "en|nb",
    }
    langpair = pair_map.get(target, pair)
    url = "https://api.mymemory.translated.net/get?" + urllib.parse.urlencode(
        {"q": text[:480], "langpair": langpair}
    )
    req = urllib.request.Request(url, headers={"User-Agent": "CometEditor-i18n/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        if e.code == 429:
            print(f"WARN 429 {target!r}, odak bekleniyor…", file=sys.stderr)
            time.sleep(8.0)
        else:
            print(f"WARN translate fail {target!r}: {e}", file=sys.stderr)
        # Başarısız çeviriyi önbelleğe yazma (sonraki çalıştırmada yeniden dene)
        return text
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
        print(f"WARN translate fail {target!r}: {e}", file=sys.stderr)
        return text
    if data.get("responseStatus") != 200:
        print(f"WARN status {data.get('responseStatus')} {target} quota={data.get('quotaFinished')}", file=sys.stderr)
        return text
    out = data.get("responseData", {}).get("translatedText", text)
    # API bazen aynı metni döndürür
    cache[ck] = out or text
    time.sleep(DELAY)
    return cache[ck]


def main() -> int:
    en = parse_home_keys(EN_PATH)
    if not en:
        print("No home.* keys in en", file=sys.stderr)
        return 1
    wm = json.loads(WM_PATH.read_text(encoding="utf-8"))
    langs = sorted(k for k in wm if k != "en")
    if _MT_ONLY:
        langs = [x for x in langs if x in _MT_ONLY]
        if not langs:
            print("HOME_MT_LANGS eşleşmedi", file=sys.stderr)
            return 1
    cache: dict[str, str] = {}
    if CACHE_PATH.is_file():
        cache = json.loads(CACHE_PATH.read_text(encoding="utf-8"))

    all_wm = sorted(k for k in wm if k != "en")
    existing: dict[str, dict[str, str]] = {}
    if OUT_PATH.is_file():
        existing = json.loads(OUT_PATH.read_text(encoding="utf-8"))

    bundles: dict[str, dict[str, str]] = {"en": dict(en)}
    keys_sorted = sorted(en.keys())

    to_process = langs if _MT_ONLY else all_wm
    for lang in all_wm:
        if lang not in to_process:
            bundles[lang] = existing.get(lang) or dict(en)
            continue
        bundle = dict(en)
        path = lproj_for_logical(lang)
        if path:
            loc = parse_home_keys(path)
            for k in keys_sorted:
                if k in loc and loc[k] != en[k]:
                    bundle[k] = loc[k]
        # Eksikleri MT ile doldur
        missing = [k for k in keys_sorted if bundle[k] == en[k]]
        if missing:
            print(f"{lang}: MT fill {len(missing)} / {len(keys_sorted)} keys…")
        for k in missing:
            if should_skip_mt(k, en[k]):
                bundle[k] = en[k]
                continue
            bundle[k] = mymemory_translate(en[k], lang, cache)
        bundles[lang] = bundle
        print(f"{lang}: done")

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps(bundles, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    CACHE_PATH.write_text(json.dumps(cache, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {OUT_PATH} ({len(bundles)} langs)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
