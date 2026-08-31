#!/bin/bash
# Sign bundled helper tools with App Sandbox entitlements and emit dSYMs.
#
# Used as:
#   1. Xcode Run Script (last build phase) — CODESIGNING_FOLDER_PATH
#   2. Archive post-action — ARCHIVE_PATH
#   3. Manual:  ./scripts/sign_bundled_helpers.sh --latest-archive
#
# Helpers live in Contents/MacOS (nested code). Organizer "Distribute App"
# preserves nested-code entitlements; Mach-O files left in Resources get
# re-signed WITHOUT entitlements and fail App Store error 90296.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCROOT="${SRCROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CLI_LATEST=0

# Prefer versions already written by Xcode into the built Info.plist.
# Fall back to Xcode env, then 2.0 / 1 so this script never fights pbxproj.

if [ "${1:-}" = "--latest-archive" ]; then
  CLI_LATEST=1
  ARCHIVE_PATH="$(find "${HOME}/Library/Developer/Xcode/Archives" -name '*.xcarchive' -maxdepth 2 2>/dev/null \
    | xargs -I{} stat -f '%m %N' {} 2>/dev/null \
    | sort -n \
    | tail -1 \
    | cut -d' ' -f2- || true)"
  if [ -z "${ARCHIVE_PATH}" ] || [ ! -d "${ARCHIVE_PATH}" ]; then
    echo "error: no Xcode archive found in ~/Library/Developer/Xcode/Archives" >&2
    exit 1
  fi
  echo "Using latest archive: ${ARCHIVE_PATH}"
fi

ENTITLEMENTS="${SRCROOT}/cometeditor/ffmpeg.entitlements"
if [ ! -f "${ENTITLEMENTS}" ]; then
  echo "error: missing entitlements file: ${ENTITLEMENTS}" >&2
  exit 1
fi

APP_ENTITLEMENTS="${SRCROOT}/cometeditor/cometeditor.entitlements"

APP_ROOT=""
if [ -n "${ARCHIVE_PATH:-}" ] && [ -d "${ARCHIVE_PATH}/Products/Applications" ]; then
  APP_ROOT="$(find "${ARCHIVE_PATH}/Products/Applications" -maxdepth 1 -name '*.app' -print -quit)"
elif [ -n "${CODESIGNING_FOLDER_PATH:-}" ]; then
  APP_ROOT="${CODESIGNING_FOLDER_PATH}"
fi

if [ -z "${APP_ROOT}" ] || [ ! -d "${APP_ROOT}" ]; then
  echo "error: could not locate app bundle to sign helpers" >&2
  echo "  ARCHIVE_PATH=${ARCHIVE_PATH:-}" >&2
  echo "  CODESIGNING_FOLDER_PATH=${CODESIGNING_FOLDER_PATH:-}" >&2
  exit 1
fi

# Never silently skip during archive / App Store export. Empty identity is
# why previous archives shipped adhoc linker-signed ffmpeg/ffprobe/cometscaly.
pick_identity_named() {
  local needle="$1"
  security find-identity -v -p codesigning 2>/dev/null \
    | grep -F "${needle}" \
    | head -1 \
    | sed -n 's/.*"\(.*\)".*/\1/p'
}

resolve_identity() {
  if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
    printf '%s\n' "${EXPANDED_CODE_SIGN_IDENTITY}"
    return
  fi
  if [ -n "${CODE_SIGN_IDENTITY:-}" ] && [ "${CODE_SIGN_IDENTITY}" != "-" ] \
     && [ "${CODE_SIGN_IDENTITY}" != "Apple Development" ] \
     && [ "${CODE_SIGN_IDENTITY}" != "Apple Distribution" ]; then
    printf '%s\n' "${CODE_SIGN_IDENTITY}"
    return
  fi

  local found=""
  # Automatic signing archives with Development; Organizer re-signs with
  # Distribution on export. Use Distribution only when it is actually installed.
  if [ -n "${ARCHIVE_PATH:-}" ] || [ "${ACTION:-}" = "install" ] || [ "${CLI_LATEST}" = "1" ]; then
    found="$(pick_identity_named "Apple Distribution")"
  fi
  if [ -z "${found}" ]; then
    found="$(pick_identity_named "Apple Development")"
  fi
  if [ -z "${found}" ]; then
    found="$(security find-identity -v -p codesigning 2>/dev/null \
      | grep -E 'Apple (Development|Distribution)' \
      | head -1 \
      | sed -n 's/.*"\(.*\)".*/\1/p')"
  fi
  if [ -z "${found}" ]; then
    echo "error: no usable codesign identity in the keychain" >&2
    security find-identity -v -p codesigning >&2 || true
    exit 1
  fi
  printf '%s\n' "${found}"
}

if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ] && [ -z "${ARCHIVE_PATH:-}" ]; then
  echo "note: skipping helper codesign (CODE_SIGNING_ALLOWED=NO)"
  exit 0
fi

IDENTITY="$(resolve_identity)"
echo "Signing bundled helpers in: ${APP_ROOT}"
echo "Identity: ${IDENTITY}"

MACOS_DIR="${APP_ROOT}/Contents/MacOS"
RES_DIR="${APP_ROOT}/Contents/Resources"
mkdir -p "${MACOS_DIR}"

# Relocate any leftover Resource Mach-Os into Contents/MacOS so Organizer
# treats them as nested code (preserve-metadata=entitlements on export).
relocate_helper() {
  local name="$1"
  local dest="${MACOS_DIR}/${name}"
  local src=""
  for candidate in \
    "${MACOS_DIR}/${name}" \
    "${APP_ROOT}/Contents/Helpers/${name}" \
    "${RES_DIR}/${name}" \
    "${RES_DIR}/upscale/${name}"
  do
    if [ -f "${candidate}" ]; then
      src="${candidate}"
      break
    fi
  done
  if [ -z "${src}" ]; then
    echo "error: helper not found: ${name}" >&2
    exit 1
  fi
  if [ "${src}" != "${dest}" ]; then
    echo "relocating ${src} -> ${dest}"
    cp -f "${src}" "${dest}"
    rm -f "${src}"
  fi
  chmod +x "${dest}"
}

relocate_helper "ffmpeg"
relocate_helper "ffprobe"
relocate_helper "cometscaly"

# Apple validates ALL Mach-O in the pkg. Never leave helpers in Resources.
strip_resources_helpers() {
  local leftovers
  find "${RES_DIR}" \( -name ffmpeg -o -name ffprobe -o -name cometscaly \) -type f -delete 2>/dev/null || true
  rmdir "${APP_ROOT}/Contents/Helpers" 2>/dev/null || true
  leftovers="$(find "${RES_DIR}" \( -name ffmpeg -o -name ffprobe -o -name cometscaly \) -type f 2>/dev/null || true)"
  if [ -n "${leftovers}" ]; then
    echo "error: refusing to ship Mach-O helpers in Resources:" >&2
    printf '%s\n' "${leftovers}" >&2
    exit 1
  fi
  echo "Resources has no ffmpeg/ffprobe/cometscaly"
}

strip_resources_helpers

stamp_plist_key() {
  local plist="$1"
  local key="$2"
  local value="$3"
  if [ ! -f "${plist}" ]; then
    return 0
  fi
  if /usr/libexec/PlistBuddy -c "Print ${key}" "${plist}" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set ${key} ${value}" "${plist}"
  else
    /usr/libexec/PlistBuddy -c "Add ${key} string ${value}" "${plist}"
  fi
}

PLIST="${APP_ROOT}/Contents/Info.plist"
plist_print() {
  local plist="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print ${key}" "${plist}" 2>/dev/null || true
}

SHIP_BUNDLE_VERSION="$(plist_print "${PLIST}" ":CFBundleVersion")"
SHIP_MARKETING_VERSION="$(plist_print "${PLIST}" ":CFBundleShortVersionString")"
if [ -z "${SHIP_BUNDLE_VERSION}" ]; then
  SHIP_BUNDLE_VERSION="${CURRENT_PROJECT_VERSION:-1}"
fi
if [ -z "${SHIP_MARKETING_VERSION}" ]; then
  SHIP_MARKETING_VERSION="${MARKETING_VERSION:-2.0}"
fi
echo "Info.plist CFBundleVersion=${SHIP_BUNDLE_VERSION} CFBundleShortVersionString=${SHIP_MARKETING_VERSION}"

# Organizer reads the xcarchive metadata, not only the app Info.plist.
if [ -n "${ARCHIVE_PATH:-}" ] && [ -f "${ARCHIVE_PATH}/Info.plist" ]; then
  stamp_plist_key "${ARCHIVE_PATH}/Info.plist" ":ApplicationProperties:CFBundleVersion" "${SHIP_BUNDLE_VERSION}"
  stamp_plist_key "${ARCHIVE_PATH}/Info.plist" ":ApplicationProperties:CFBundleShortVersionString" "${SHIP_MARKETING_VERSION}"
  echo "xcarchive ApplicationProperties CFBundleVersion=${SHIP_BUNDLE_VERSION}"
fi

DSYM_DIR="${DWARF_DSYM_FOLDER_PATH:-}"
if [ -z "${DSYM_DIR}" ] && [ -n "${ARCHIVE_PATH:-}" ] && [ -d "${ARCHIVE_PATH}/dSYMs" ]; then
  DSYM_DIR="${ARCHIVE_PATH}/dSYMs"
fi

EXTRA=(--options runtime --generate-entitlement-der)
if [ "${ACTION:-}" = "install" ] || [ -n "${ARCHIVE_PATH:-}" ]; then
  EXTRA+=(--timestamp)
fi

sign_one() {
  local name="$1"
  local identifier="$2"
  local binary="${MACOS_DIR}/${name}"

  if [ ! -f "${binary}" ]; then
    echo "error: helper not found after relocate: ${binary}" >&2
    exit 1
  fi

  codesign --force --sign "${IDENTITY}" \
    --entitlements "${ENTITLEMENTS}" \
    --identifier "${identifier}" \
    "${EXTRA[@]}" \
    "${binary}"

  if ! codesign -d --entitlements - "${binary}" 2>/dev/null | grep -q "app-sandbox"; then
    echo "error: sandbox entitlement missing after sign: ${name}" >&2
    codesign -d --verbose=2 --entitlements - "${binary}" >&2 || true
    exit 1
  fi

  echo "signed Contents/MacOS/${name} (${identifier})"

  if [ -n "${DSYM_DIR}" ]; then
    mkdir -p "${DSYM_DIR}"
    dsymutil "${binary}" -o "${DSYM_DIR}/${name}.dSYM" \
      || echo "warning: dsymutil failed for ${name}"
  fi
}

sign_one "ffmpeg" "com.cometeditor.app.ffmpeg"
sign_one "ffprobe" "com.cometeditor.app.ffprobe"
sign_one "cometscaly" "com.cometeditor.app.cometscaly"

# Belt-and-suspenders: a later copy phase must not have restored Resources Mach-O.
strip_resources_helpers

# Archive post-action runs AFTER Xcode signed the .app. Re-seal the bundle
# so Organizer export sees a consistent tree of nested signed helpers.
if [ -n "${ARCHIVE_PATH:-}" ] && [ -f "${APP_ENTITLEMENTS}" ]; then
  echo "Re-signing app bundle after helper updates..."
  APP_SIGN_EXTRA=(--options runtime --generate-entitlement-der)
  if [ "${ACTION:-}" = "install" ] || [ -n "${ARCHIVE_PATH:-}" ]; then
    APP_SIGN_EXTRA+=(--timestamp)
  fi
  codesign --force --sign "${IDENTITY}" \
    --entitlements "${APP_ENTITLEMENTS}" \
    "${APP_SIGN_EXTRA[@]}" \
    "${APP_ROOT}"
fi

echo "Bundled helpers signed with App Sandbox entitlements (Contents/MacOS)."
echo "Confirm in Organizer: version ${SHIP_MARKETING_VERSION} (${SHIP_BUNDLE_VERSION}) before upload."
echo "Confirm Resources has no ffmpeg/ffprobe/cometscaly before Distribute."
