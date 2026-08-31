#!/usr/bin/env python3
"""Write i18n/packs/<locale>.json for newly added world languages."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKS = ROOT / "i18n" / "packs"
MASTER = ROOT / "i18n" / "master.json"
COMET = ROOT / "cometeditor"

sys.path.insert(0, str(Path(__file__).parent))

# When a new locale is missing a late-added key, borrow from a close existing locale.
RELATED = {
    "ar": "he",
    "fa": "ur",
    "sw": "id",
    "fil": "id",
    "ca": "es",
    "gl": "es",
    "eu": "es",
    "ga": "en",
    "cy": "en",
    "af": "nl",
    "be": "uk",
    "mn": "ru",
    "ne": "hi",
    "si": "hi",
    "ta": "hi",
    "te": "hi",
    "ml": "hi",
    "pa": "hi",
    "km": "th",
    "lo": "th",
    "my": "th",
    "am": "he",
}


def parse_strings(path: Path) -> dict[str, str]:
    import re
    line_re = re.compile(r'^"((?:\\.|[^\\"])*)"\s*=\s*"((?:\\.|[^\\"])*)"\s*;\s*$')
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    for raw in path.read_text(encoding="utf-8").splitlines():
        s = raw.strip()
        if not s or s.startswith("//"):
            continue
        m = line_re.match(s)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def main() -> int:
    from world_packs_a import ALL_PACKS as PACKS_A
    from world_packs_b import ALL_PACKS as PACKS_B

    extra_path = PACKS / "_extra.json"
    extra_all: dict[str, dict[str, str]] = {}
    if extra_path.is_file():
        try:
            extra_all = json.loads(extra_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            extra_all = {}

    all_packs = {**PACKS_A, **PACKS_B}
    PACKS.mkdir(parents=True, exist_ok=True)
    master = json.loads(MASTER.read_text(encoding="utf-8"))["keys"]
    related_cache: dict[str, dict[str, str]] = {}
    bad = False
    for loc, bundle in all_packs.items():
        merged = dict(bundle)
        merged.update(extra_all.get(loc, {}))
        related = RELATED.get(loc)
        if related and related not in related_cache:
            related_cache[related] = parse_strings(COMET / f"{related}.lproj" / "Localizable.strings")
        for key in master:
            if key in merged and merged[key].strip():
                continue
            if related and key in related_cache.get(related, {}):
                merged[key] = related_cache[related][key]
            else:
                merged[key] = master[key]
        extra = [k for k in list(merged) if k not in master]
        for k in extra:
            merged.pop(k, None)
        missing = [k for k in master if k not in merged]
        if missing:
            bad = True
            print(f"{loc}: MISSING {missing}")
        (PACKS / f"{loc}.json").write_text(
            json.dumps(merged, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"{loc}: {len(merged)} keys")
    print(f"wrote {len(all_packs)} packs")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
