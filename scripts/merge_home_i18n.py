#!/usr/bin/env python3
"""
Eski betik: home.* anahtarlarını sabit DE_VALUES ile enjekte ediyordu (kırılgan).

Artık tüm diller için kullanın:
  python3 scripts/i18n_sync.py export    # i18n/master.json
  python3 scripts/i18n_sync.py report
  python3 scripts/i18n_sync.py fill      # eksikleri İngilizce placeholder ile doldurur
  python3 scripts/i18n_sync.py verify    # CI — eksik varsa çıkış 1

Bu dosya geriye dönük uyumluluk için i18n_sync.py'ye yönlendirir.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

SYNC = Path(__file__).resolve().parent / "i18n_sync.py"
ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    argv = [sys.executable, str(SYNC)]
    if len(sys.argv) > 1:
        argv.extend(sys.argv[1:])
    else:
        print(
            "merge_home_i18n.py artık kullanılmıyor; i18n_sync çalıştırılıyor: export",
            file=sys.stderr,
        )
        argv.append("export")
    return subprocess.call(argv, cwd=str(ROOT))


if __name__ == "__main__":
    raise SystemExit(main())
