#!/bin/sh
set -eu

usage() {
  printf '%s\n' \
    'usage: scripts/build-release-candidate.sh --tag TAG [--output-dir PATH]'
}

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
release_tag=''
output_directory="$repo_root/.release-evidence/candidates"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tag)
      [ "$#" -ge 2 ] || { usage >&2; exit 64; }
      release_tag=$2
      shift 2
      ;;
    --output-dir)
      [ "$#" -ge 2 ] || { usage >&2; exit 64; }
      output_directory=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 64
      ;;
  esac
done

[ -n "$release_tag" ] || { usage >&2; exit 64; }
case "$release_tag" in
  *[!A-Za-z0-9._-]*|'')
    printf 'invalid release tag: %s\n' "$release_tag" >&2
    exit 64
    ;;
esac

cd "$repo_root"
if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
  printf '%s\n' 'release refused: working tree must be clean' >&2
  exit 1
fi

head_commit=$(git rev-parse HEAD)
tag_commit=$(git rev-parse -q --verify "refs/tags/$release_tag^{commit}" 2>/dev/null || true)
if [ -z "$tag_commit" ] || [ "$tag_commit" != "$head_commit" ]; then
  printf 'release refused: tag %s does not point to HEAD\n' "$release_tag" >&2
  exit 1
fi

artifact_base="Automaatkorrektor-$release_tag"
dmg_name="$artifact_base.dmg"
metadata_name="$artifact_base.candidate-metadata.txt"
report_name="$artifact_base.candidate-report.md"
dmg_path="$output_directory/$dmg_name"
metadata_path="$output_directory/$metadata_name"
report_path="$output_directory/$report_name"
for artifact_path in "$dmg_path" "$metadata_path" "$report_path"; do
  if [ -e "$artifact_path" ]; then
    printf 'release refused: artifact already exists: %s\n' "$artifact_path" >&2
    exit 1
  fi
done

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/automaatkorrektor-release.XXXXXX")
mount_directory="$temporary_directory/mount"
dmg_is_mounted=false
cleanup() {
  if [ "$dmg_is_mounted" = true ]; then
    hdiutil detach "$mount_directory" >/dev/null 2>&1 || true
  fi
  rm -rf "$temporary_directory"
}
trap cleanup EXIT HUP INT TERM

set +e
"$repo_root/scripts/release-gate.sh" \
  --report "$temporary_directory/release-evidence.md"
gate_exit=$?
set -e
if [ "$gate_exit" -ne 2 ] || \
  ! grep -Fq '**Release decision:** BLOCKED' "$temporary_directory/release-evidence.md" || \
  ! grep -Eq -- '- Result: [0-9]+ passed, 0 failed, [1-9][0-9]* pending' \
    "$temporary_directory/release-evidence.md"
then
  printf '%s\n' 'candidate refused: automated checks must pass with only manual rows pending' >&2
  exit 1
fi

derived_data="$temporary_directory/DerivedData"
xcodebuild \
  -project "$repo_root/apps/macos/Automaatkorrektor.xcodeproj" \
  -scheme Automaatkorrektor \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

app_path="$derived_data/Build/Products/Release/Automaatkorrektor.app"
[ -d "$app_path" ] || {
  printf 'release failed: expected app was not built: %s\n' "$app_path" >&2
  exit 1
}

minimum_system_version=$(/usr/bin/plutil -extract LSMinimumSystemVersion raw \
  "$app_path/Contents/Info.plist")
if ! awk -v version="$minimum_system_version" \
  'BEGIN { exit ! (version ~ /^[0-9]+([.][0-9]+)*$/ && version + 0 >= 15) }'
then
  printf 'release failed: app requires macOS %s instead of macOS 15 or later\n' \
    "$minimum_system_version" >&2
  exit 1
fi

codesign --force --deep --sign - "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
signature_details=$(codesign -dv --verbose=4 "$app_path" 2>&1)
printf '%s\n' "$signature_details" | grep -Fq 'Signature=adhoc' || {
  printf '%s\n' 'release failed: app does not have an ad-hoc signature' >&2
  exit 1
}
printf '%s\n' "$signature_details" | grep -Fq 'TeamIdentifier=not set' || {
  printf '%s\n' 'release failed: app unexpectedly has a signing team' >&2
  exit 1
}
printf '%s\n' 'Ad-hoc signature verified (no signing team).'

staging_directory="$temporary_directory/staging"
mkdir -p "$staging_directory"
/usr/bin/ditto "$app_path" "$staging_directory/Automaatkorrektor.app"

temporary_dmg="$temporary_directory/$dmg_name"
hdiutil create \
  -volname Automaatkorrektor \
  -srcfolder "$staging_directory" \
  -format UDZO \
  "$temporary_dmg"
hdiutil verify "$temporary_dmg"

mkdir -p "$mount_directory"
hdiutil attach -readonly -nobrowse -mountpoint "$mount_directory" "$temporary_dmg"
dmg_is_mounted=true
[ -d "$mount_directory/Automaatkorrektor.app" ] || {
  printf '%s\n' 'release failed: DMG does not contain Automaatkorrektor.app' >&2
  exit 1
}
codesign --verify --deep --strict --verbose=2 \
  "$mount_directory/Automaatkorrektor.app"
hdiutil detach "$mount_directory"
dmg_is_mounted=false

mkdir -p "$output_directory"
mv -n "$temporary_dmg" "$dmg_path"
[ ! -e "$temporary_dmg" ] && [ -f "$dmg_path" ] || {
  printf 'release failed: could not create %s without overwriting a file\n' \
    "$dmg_path" >&2
  exit 1
}

candidate_sha256=$(shasum -a 256 "$dmg_path" | awk '{print $1}')
{
  printf 'Format-Version: 1\n'
  printf 'Tag: %s\n' "$release_tag"
  printf 'Commit: %s\n' "$head_commit"
  printf 'Candidate-SHA256: %s\n' "$candidate_sha256"
} > "$metadata_path"
cp "$temporary_directory/release-evidence.md" "$report_path"

printf 'Candidate DMG: %s\n' "$dmg_path"
printf 'Candidate metadata: %s\n' "$metadata_path"
printf 'Candidate report: %s\n' "$report_path"
