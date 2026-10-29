#!/bin/sh
set -eu

usage() {
  printf '%s\n' \
    'kasutus: scripts/build-release-dmg.sh --tag TAG [--output-dir TEE]'
}

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
release_tag=''
output_directory="$repo_root/.release-evidence/releases"

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
    printf 'vigane väljalaske tägi: %s\n' "$release_tag" >&2
    exit 64
    ;;
esac

cd "$repo_root"
if [ -n "$(git status --porcelain --untracked-files=normal)" ]; then
  printf '%s\n' 'väljalaskest keelduti: tööpuu peab olema puhas' >&2
  exit 1
fi

head_commit=$(git rev-parse HEAD)
tag_commit=$(git rev-parse -q --verify "refs/tags/$release_tag^{commit}" 2>/dev/null || true)
if [ -z "$tag_commit" ] || [ "$tag_commit" != "$head_commit" ]; then
  printf 'väljalaskest keelduti: tägi %s ei osuta HEAD-ile\n' "$release_tag" >&2
  exit 1
fi

artifact_base="Automaatkorrektor-$release_tag"
dmg_name="$artifact_base.dmg"
dmg_path="$output_directory/$dmg_name"
[ ! -e "$dmg_path" ] || {
  printf 'väljalaskest keelduti: DMG on juba olemas: %s\n' "$dmg_path" >&2
  exit 1
}

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

"$repo_root/scripts/release-gate.sh"

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
  printf 'väljalase ebaõnnestus: oodatud rakendust ei ehitatud: %s\n' "$app_path" >&2
  exit 1
}

minimum_system_version=$(/usr/bin/plutil -extract LSMinimumSystemVersion raw \
  "$app_path/Contents/Info.plist")
if ! awk -v version="$minimum_system_version" \
  'BEGIN { exit ! (version ~ /^[0-9]+([.][0-9]+)*$/ && version + 0 >= 15) }'
then
  printf 'väljalase ebaõnnestus: rakendus nõuab macOS %s, mitte macOS 15 või uuemat\n' \
    "$minimum_system_version" >&2
  exit 1
fi

codesign --force --deep --sign - "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
signature_details=$(codesign -dv --verbose=4 "$app_path" 2>&1)
printf '%s\n' "$signature_details" | grep -Fq 'Signature=adhoc' || {
  printf '%s\n' 'väljalase ebaõnnestus: rakendusel puudub ad-hoc-allkiri' >&2
  exit 1
}
printf '%s\n' "$signature_details" | grep -Fq 'TeamIdentifier=not set' || {
  printf '%s\n' 'väljalase ebaõnnestus: rakendusel on ootamatult allkirjastamismeeskond' >&2
  exit 1
}
printf '%s\n' 'Ad-hoc-allkiri kontrollitud (allkirjastamismeeskond puudub).'

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
  printf '%s\n' 'väljalase ebaõnnestus: DMG ei sisalda rakendust Automaatkorrektor.app' >&2
  exit 1
}
codesign --verify --deep --strict --verbose=2 \
  "$mount_directory/Automaatkorrektor.app"
hdiutil detach "$mount_directory"
dmg_is_mounted=false

mkdir -p "$output_directory"
mv -n "$temporary_dmg" "$dmg_path"
[ ! -e "$temporary_dmg" ] && [ -f "$dmg_path" ] || {
  printf 'väljalase ebaõnnestus: faili %s ei saanud luua olemasolevat faili üle kirjutamata\n' \
    "$dmg_path" >&2
  exit 1
}

printf 'DMG valmis: %s\n' "$dmg_path"
