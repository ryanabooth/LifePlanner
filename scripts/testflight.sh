#!/usr/bin/env bash
#
# scripts/testflight.sh — one-command TestFlight upload for LifePlanner.
#
# Runs the four steps from ROADMAP / TestFlight notes:
#   1. agvtool next-version -all   (bump CURRENT_PROJECT_VERSION)
#   2. xcodebuild archive          (Release, generic/iOS)
#   3. xcodebuild -exportArchive   (app-store-connect method)
#   4. xcrun altool --upload-app   (credentials below)
#
# Usage:
#   scripts/testflight.sh            # full flow (bump, archive, export, upload)
#   scripts/testflight.sh --no-bump  # use the current build number (e.g. retrying after a failed upload)
#   scripts/testflight.sh --no-upload  # archive + export but stop before upload (for inspection)
#
# Credentials are read from scripts/.env (which is gitignored). One of:
#
#   APPLE_ID=you@example.com
#   APP_SPECIFIC_PASSWORD=abcd-efgh-ijkl-mnop
#
# ...or, preferred:
#
#   APP_STORE_KEY_ID=KEYID12345
#   APP_STORE_ISSUER_ID=00000000-0000-0000-0000-000000000000
#   APP_STORE_KEY_PATH=/path/to/AuthKey_KEYID12345.p8
#
# The API-key triple wins if both are present.

set -euo pipefail

cd "$(dirname "$0")/.."
SCRIPT_DIR="scripts"
PROJECT="LifePlanner.xcodeproj"
SCHEME="LifePlanner"
ARCHIVE_PATH="build/LifePlanner.xcarchive"
EXPORT_DIR="build/export"
IPA_PATH="${EXPORT_DIR}/LifePlanner.ipa"

# --- flag parsing -------------------------------------------------------------
DO_BUMP=1
DO_UPLOAD=1
for arg in "$@"; do
  case "$arg" in
    --no-bump)   DO_BUMP=0 ;;
    --no-upload) DO_UPLOAD=0 ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown flag: $arg" >&2
      exit 1
      ;;
  esac
done

# --- env load -----------------------------------------------------------------
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a; . "${SCRIPT_DIR}/.env"; set +a
fi

# --- step 1: bump -------------------------------------------------------------
if [[ "$DO_BUMP" -eq 1 ]]; then
  echo "==> Bumping build number"
  xcrun agvtool next-version -all
fi

CURRENT_BUILD=$(xcrun agvtool what-version -terse)
MARKETING=$(xcrun agvtool what-marketing-version -terse1)
echo "==> Building ${MARKETING} (${CURRENT_BUILD})"

# --- step 2: archive ----------------------------------------------------------
echo "==> Cleaning previous archive"
rm -rf "${ARCHIVE_PATH}" "${EXPORT_DIR}"

echo "==> Archiving"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  -allowProvisioningUpdates \
  archive | xcbeautify 2>/dev/null || \
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  -allowProvisioningUpdates \
  archive

# --- step 3: export -----------------------------------------------------------
echo "==> Exporting .ipa"
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_DIR}" \
  -exportOptionsPlist "${SCRIPT_DIR}/ExportOptions.plist" \
  -allowProvisioningUpdates

if [[ ! -f "${IPA_PATH}" ]]; then
  echo "Export did not produce ${IPA_PATH}" >&2
  exit 1
fi
echo "==> Exported $(ls -lh "${IPA_PATH}" | awk '{print $5}') to ${IPA_PATH}"

# --- step 4: upload -----------------------------------------------------------
if [[ "$DO_UPLOAD" -eq 0 ]]; then
  echo "==> Skipping upload (--no-upload). Run manually with:"
  echo "    xcrun altool --upload-app --type ios --file ${IPA_PATH} ..."
  exit 0
fi

if [[ -n "${APP_STORE_KEY_ID:-}" && -n "${APP_STORE_ISSUER_ID:-}" && -n "${APP_STORE_KEY_PATH:-}" ]]; then
  echo "==> Uploading via App Store Connect API key (KEY_ID=${APP_STORE_KEY_ID})"
  # altool reads the key from ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 if --apiKey is used.
  # Ensure the file is in that location, or symlink it once.
  KEY_HOME="${HOME}/.appstoreconnect/private_keys"
  mkdir -p "${KEY_HOME}"
  KEY_FILE="${KEY_HOME}/AuthKey_${APP_STORE_KEY_ID}.p8"
  if [[ ! -f "${KEY_FILE}" ]]; then
    ln -sf "${APP_STORE_KEY_PATH}" "${KEY_FILE}"
  fi
  xcrun altool --upload-app \
    --type ios \
    --file "${IPA_PATH}" \
    --apiKey "${APP_STORE_KEY_ID}" \
    --apiIssuer "${APP_STORE_ISSUER_ID}"
elif [[ -n "${APPLE_ID:-}" && -n "${APP_SPECIFIC_PASSWORD:-}" ]]; then
  echo "==> Uploading via app-specific password (${APPLE_ID})"
  xcrun altool --upload-app \
    --type ios \
    --file "${IPA_PATH}" \
    --username "${APPLE_ID}" \
    --password "${APP_SPECIFIC_PASSWORD}"
else
  echo "No upload credentials in scripts/.env." >&2
  echo "Set either (APPLE_ID + APP_SPECIFIC_PASSWORD) or" >&2
  echo "(APP_STORE_KEY_ID + APP_STORE_ISSUER_ID + APP_STORE_KEY_PATH)." >&2
  echo "Or re-run with --no-upload to stop after export." >&2
  exit 1
fi

echo "==> Done. Build is processing in App Store Connect — typically 5–30 minutes."
echo "    https://appstoreconnect.apple.com -> TestFlight -> iOS Builds"
