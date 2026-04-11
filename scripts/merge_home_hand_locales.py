#!/usr/bin/env python3
"""i18n/home_hand_<kieli>.json düz anahtar sözlüklerini home_bundles.json içine yazar."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLES = ROOT / "i18n" / "home_bundles.json"


def main() -> int:
    if not BUNDLES.is_file():
        print("Eksik home_bundles.json", file=sys.stderr)
        return 1
    bundles: dict[str, dict[str, str]] = json.loads(BUNDLES.read_text(encoding="utf-8"))
    n = 0
    for path in sorted((ROOT / "i18n").glob("home_hand_*.json")):
        stem = path.stem  # home_hand_fi
        if not stem.startswith("home_hand_"):
            continue
        raw = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(raw, dict) or not raw:
            continue
        # İç içe: { "it": { "home.x": "..." }, "pl": { ... } }
        if all(isinstance(v, dict) for v in raw.values()) and not any(
            isinstance(k, str) and k.startswith("home.") for k in raw
        ):
            for lang, patch in raw.items():
                if not isinstance(patch, dict):
                    continue
                if lang not in bundles:
                    bundles[lang] = dict(bundles.get("en", {}))
                bundles[lang].update(patch)
                n += 1
                print(f"merged {path.name} → {lang} ({len(patch)} keys)")
            continue
        lang = stem.removeprefix("home_hand_")
        patch = raw
        if lang not in bundles:
            bundles[lang] = dict(bundles.get("en", {}))
        bundles[lang].update(patch)
        n += 1
        print(f"merged {path.name} → {lang} ({len(patch)} keys)")
    BUNDLES.write_text(json.dumps(bundles, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"updated {BUNDLES} ({n} hand files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
