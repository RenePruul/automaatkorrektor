#!/bin/sh
set -eu

usage() {
  printf '%s\n' 'kasutus: scripts/release-gate.sh'
}

case "${1:-}" in
  '') ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
[ "$#" -le 1 ] || { usage >&2; exit 64; }

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/automaatkorrektor-release-gate.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

cd "$repo_root"

printf '%s\n' '==> Swift-vormindus'
swift format lint --recursive --strict Sources Tests Package.swift

printf '%s\n' '==> Giti tööpuu'
git diff --check
test -z "$(git status --porcelain --untracked-files=normal)"

printf '%s\n' '==> Väljalasketestid'
python3 -m unittest discover -s Tests/ReleaseTests -p 'test_*.py'

printf '%s\n' '==> Swifti testid'
swift test

printf '%s\n' '==> Xcode macOS build'
xcodebuild \
  -project apps/macos/Automaatkorrektor.xcodeproj \
  -scheme Automaatkorrektor \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$temporary_directory/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build

printf '%s\n' '==> Xcode päris AX-testirakenduste build'
xcodebuild \
  -project apps/macos/Automaatkorrektor.xcodeproj \
  -scheme NativeAXEvidence \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$temporary_directory/NativeAXDerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build

printf '%s\n' 'Kõik automaatkontrollid läbitud.'
