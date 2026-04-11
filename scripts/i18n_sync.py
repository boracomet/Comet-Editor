#!/usr/bin/env python3
"""
Comet Editor — çok dillı Localizable.strings yönetimi.

Şablon (dil-bağımsız anahtar kümesi + referans metin):
  i18n/master.json  — export ile üretilir; tüm .lproj dosyalarındaki anahtarların birleşimi
                      ve referans çevirisi (varsayılan: en, yoksa diğer dillerden).

Komutlar:
  export      Birleşik anahtar listesini i18n/master.json olarak yazar.
  report      Her dilde master'a göre eksik / fazla anahtar özetini yazdırır.
  verify      master.json ile tüm dilleri karşılaştırır; eksik varsa çıkış kodu 1 (CI).
  keys-only   Sadece anahtarları (satır başına bir key) i18n/keys.txt yazar.
  fill        Eksik anahtarları hedef dillere ekler (değer: master ref, genelde İngilizce).

Örnek:
  python3 scripts/i18n_sync.py export
  python3 scripts/i18n_sync.py report
  python3 scripts/i18n_sync.py fill --dry-run
  python3 scripts/i18n_sync.py fill --locale de
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMETEDITOR = ROOT / "cometeditor"
MASTER_DIR = ROOT / "i18n"
MASTER_JSON = MASTER_DIR / "master.json"
KEYS_TXT = MASTER_DIR / "keys.txt"

# "key" = "value";  — value içinde kaçışlı çift tırnak ve ters eğik çizgi
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


def parse_strings(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    out: dict[str, str] = {}
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("//"):
            continue
        m = _LINE_RE.match(s)
        if not m:
            print(f"WARN skip (parse): {path.name}:{line[:80]}", file=sys.stderr)
            continue
        key = unescape_strings_value(m.group(1))
        val = unescape_strings_value(m.group(2))
        out[key] = val
    return out


def all_locale_files() -> list[Path]:
    return sorted(COMETEDITOR.glob("*.lproj/Localizable.strings"))


def locale_tag(path: Path) -> str:
    return path.parent.name.removesuffix(".lproj")


def load_all_locales() -> dict[str, dict[str, str]]:
    return {locale_tag(p): parse_strings(p) for p in all_locale_files()}


def build_master(locales: dict[str, dict[str, str]], ref_locale: str = "en") -> dict[str, str]:
    """Tüm dillerdeki anahtarların birleşimi; ref metin önce ref_locale, yoksa sırayla diğerleri."""
    all_keys: set[str] = set()
    for d in locales.values():
        all_keys |= set(d.keys())
    order_locales = [ref_locale] + sorted(k for k in locales if k != ref_locale)
    master: dict[str, str] = {}
    for key in sorted(all_keys):
        ref = ""
        for loc in order_locales:
            if loc in locales and key in locales[loc]:
                ref = locales[loc][key]
                break
        master[key] = ref
    return master


def cmd_export(args: argparse.Namespace) -> int:
    locales = load_all_locales()
    if not locales:
        print("No Localizable.strings found.", file=sys.stderr)
        return 1
    master = build_master(locales, ref_locale=args.ref)
    MASTER_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "version": 1,
        "ref_locale": args.ref,
        "key_count": len(master),
        "keys": master,
    }
    MASTER_JSON.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {MASTER_JSON} ({len(master)} keys)")
    return 0


def cmd_keys_only(_: argparse.Namespace) -> int:
    if not MASTER_JSON.is_file():
        print("Run `export` first.", file=sys.stderr)
        return 1
    data = json.loads(MASTER_JSON.read_text(encoding="utf-8"))
    keys = sorted(data["keys"].keys())
    MASTER_DIR.mkdir(parents=True, exist_ok=True)
    KEYS_TXT.write_text("\n".join(keys) + "\n", encoding="utf-8")
    print(f"Wrote {KEYS_TXT} ({len(keys)} keys)")
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    """CI: eksik anahtar varsa hata kodu döndür."""
    if not MASTER_JSON.is_file():
        print("master.json yok — önce: python3 scripts/i18n_sync.py export", file=sys.stderr)
        return 1
    master_keys = set(json.loads(MASTER_JSON.read_text(encoding="utf-8"))["keys"])
    locales = load_all_locales()
    bad = False
    for loc in sorted(locales):
        if loc == args.skip_locale:
            continue
        ks = set(locales[loc])
        missing = sorted(master_keys - ks)
        if missing:
            bad = True
            print(f"VERIFY FAIL {loc}: missing {len(missing)} keys", file=sys.stderr)
            for k in missing[:20]:
                print(f"  - {k}", file=sys.stderr)
            if len(missing) > 20:
                print(f"  ... ve {len(missing) - 20} tane daha", file=sys.stderr)
    if bad:
        return 1
    print(f"VERIFY OK: {len(locales)} bundle, master {len(master_keys)} key")
    return 0


def cmd_report(_: argparse.Namespace) -> int:
    if not MASTER_JSON.is_file():
        print("Run `export` first.", file=sys.stderr)
        return 1
    master_keys = set(json.loads(MASTER_JSON.read_text(encoding="utf-8"))["keys"])
    locales = load_all_locales()
    print(f"Master keys: {len(master_keys)}\n")
    for loc in sorted(locales):
        ks = set(locales[loc])
        missing = sorted(master_keys - ks)
        extra = sorted(ks - master_keys)
        print(f"{loc}: present {len(ks)}  missing {len(missing)}  extra(not in master) {len(extra)}")
        if missing and len(missing) <= 12:
            for k in missing:
                print(f"  - {k}")
        elif missing:
            for k in missing[:8]:
                print(f"  - {k}")
            print(f"  ... and {len(missing) - 8} more")
        if extra and len(extra) <= 8:
            for k in extra:
                print(f"  + orphan {k}")
    return 0


def cmd_fill(args: argparse.Namespace) -> int:
    if not MASTER_JSON.is_file():
        print("Run `export` first.", file=sys.stderr)
        return 1
    payload = json.loads(MASTER_JSON.read_text(encoding="utf-8"))
    master: dict[str, str] = payload["keys"]
    targets = all_locale_files()
    if args.locale:
        targets = [p for p in targets if locale_tag(p) == args.locale]
        if not targets:
            print(f"No bundle for locale {args.locale}", file=sys.stderr)
            return 1

    block_lines = [
        "",
        "// MARK: - Auto-filled missing keys (i18n_sync.py — translate from ref_locale)",
    ]
    for path in targets:
        loc = locale_tag(path)
        if loc == args.skip_locale:
            continue
        cur = parse_strings(path)
        missing = [k for k in sorted(master) if k not in cur]
        if not missing:
            continue
        addition = "\n".join(
            block_lines
            + [f'"{escape_strings_value(k)}" = "{escape_strings_value(master[k])}";' for k in missing]
        )
        if args.dry_run:
            print(f"[dry-run] {loc}: would add {len(missing)} keys")
            continue
        text = path.read_text(encoding="utf-8")
        if not text.endswith("\n"):
            text += "\n"
        path.write_text(text.rstrip() + addition + "\n", encoding="utf-8")
        print(f"Patched {loc}: +{len(missing)} keys")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Comet Editor i18n — Localizable.strings sync")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_exp = sub.add_parser("export", help="Write i18n/master.json from all .lproj files")
    p_exp.add_argument("--ref", default="en", help="Reference locale for values in master (default: en)")

    sub.add_parser("keys-only", help="Write i18n/keys.txt from master.json")

    sub.add_parser("report", help="Print missing/extra keys per locale vs master.json")

    p_ver = sub.add_parser("verify", help="Exit 1 if any locale (except skip) is missing keys vs master.json")
    p_ver.add_argument(
        "--skip-locale",
        default="",
        help="Bu dili doğrulamaya dahil etme (ör. boş veya sadece rapor için)",
    )

    p_fill = sub.add_parser("fill", help="Append missing keys to locale files (values from master)")
    p_fill.add_argument("--locale", help="Only this locale code (e.g. de)")
    p_fill.add_argument(
        "--skip-locale",
        default="en",
        help="Never patch this locale (default: en)",
    )
    p_fill.add_argument("--dry-run", action="store_true")

    args = ap.parse_args()
    if args.cmd == "export":
        return cmd_export(args)
    if args.cmd == "keys-only":
        return cmd_keys_only(args)
    if args.cmd == "report":
        return cmd_report(args)
    if args.cmd == "verify":
        return cmd_verify(args)
    if args.cmd == "fill":
        return cmd_fill(args)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
