#!/usr/bin/env python3
"""
home_bundles.json içinde rehber başlığı hâlâ İngilizce olan dillere yedek çeviri yazar.

- Öncelik: İspanyolca (es) paketi — Latin Amerika / Avrupa dilleri için makul varsayılan.
- uk, kk: Rusça (ru) paketine eşitlenir (ru dolu olmalı).
"""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "i18n" / "home_bundles.json"


def main() -> int:
    if not PATH.is_file():
        print("Eksik home_bundles.json", file=sys.stderr)
        return 1
    b = json.loads(PATH.read_text(encoding="utf-8"))
    en_title = b["en"]["home.guide.title"]
    es = copy.deepcopy(b["es"])
    ru = copy.deepcopy(b.get("ru", b["es"]))

    ru_mirror = ("uk", "kk", "bg", "mk")
    # Kiril / Slav dilleri: ru paketi (ru elle doldurulmuş olmalı)
    for lang in ru_mirror:
        if lang not in b:
            continue
        if b[lang].get("home.guide.title") == en_title:
            b[lang] = copy.deepcopy(ru)

    # Bu dillere asla es ile dokunma (elle paket veya ayrı mantık)
    skip_es = frozenset(
        {
            "en",
            "de",
            "tr",
            "fi",
            "fr",
            "es",
            "nl",
            "ru",
            "ja",
            "ko",
            "zh_Hans",
            "zh_Hant",
            "it",
            "pl",
            "pt",
            "sv",
            "da",
            "no",
            "az",
            "bn",
            "bs",
        }
    )
    es_fill = [
        lang
        for lang in b
        if lang not in skip_es and b[lang].get("home.guide.title") == en_title
    ]

    for lang in es_fill:
        b[lang] = copy.deepcopy(es)

    PATH.write_text(json.dumps(b, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("home_bundles.json yedek doldurma tamam (es / ru kopyası).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
