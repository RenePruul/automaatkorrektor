#!/bin/sh
set -eu

usage() {
  printf '%s\n' \
    'kasutus: scripts/finalize-release-dmg.sh --candidate TEE --manual-evidence TEE [--output-dir TEE]'
}

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
candidate_path=''
manual_evidence_path=''
output_directory=''

while [ "$#" -gt 0 ]; do
  case "$1" in
    --candidate)
      [ "$#" -ge 2 ] || { usage >&2; exit 64; }
      candidate_path=$2
      shift 2
      ;;
    --manual-evidence)
      [ "$#" -ge 2 ] || { usage >&2; exit 64; }
      manual_evidence_path=$2
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
    *) usage >&2; exit 64 ;;
  esac
done

[ -f "$candidate_path" ] || { printf '%s\n' 'finaliseerimisest keelduti: kandidaadi DMG-d ei leitud' >&2; exit 1; }
[ -f "$manual_evidence_path" ] || { printf '%s\n' 'finaliseerimisest keelduti: käsitõendeid ei leitud' >&2; exit 1; }
[ -n "$output_directory" ] || output_directory="$repo_root/.release-evidence/releases"

candidate_directory=$(CDPATH= cd -- "$(dirname "$candidate_path")" && pwd)
candidate_name=$(basename "$candidate_path")
candidate_path="$candidate_directory/$candidate_name"
case "$candidate_name" in
  Automaatkorrektor-*.dmg) ;;
  *) printf '%s\n' 'finaliseerimisest keelduti: kandidaadi failinimi on ootamatu' >&2; exit 1 ;;
esac
artifact_base=${candidate_name%.dmg}
candidate_metadata="$candidate_directory/$artifact_base.candidate-metadata.txt"
[ -f "$candidate_metadata" ] || {
  printf '%s\n' 'finaliseerimisest keelduti: kandidaadi metaandmeid ei leitud' >&2
  exit 1
}

metadata_value() {
  key=$1
  sed -n "s/^$key: //p" "$candidate_metadata"
}
evidence_value() {
  key=$1
  awk -F '\t' -v key="$key" '$1 == "# " key { print $2; found = 1; exit } END { if (!found) exit 1 }' \
    "$manual_evidence_path"
}

[ "$(metadata_value Format-Version)" = 1 ] || {
  printf '%s\n' 'finaliseerimisest keelduti: kandidaadi metaandmete vormingut ei toetata' >&2
  exit 1
}
release_tag=$(metadata_value Tag)
candidate_commit=$(metadata_value Commit)
[ -n "$release_tag" ] && [ -n "$candidate_commit" ] || {
  printf '%s\n' 'finaliseerimisest keelduti: kandidaadi metaandmed on puudulikud' >&2
  exit 1
}
[ "$candidate_name" = "Automaatkorrektor-$release_tag.dmg" ] || {
  printf '%s\n' 'finaliseerimisest keelduti: kandidaadi failinimi ei vasta selle tägile' >&2
  exit 1
}
[ "$(evidence_value Candidate-Tag 2>/dev/null || true)" = "$release_tag" ] && \
  [ "$(evidence_value Candidate-Commit 2>/dev/null || true)" = "$candidate_commit" ] || {
  printf '%s\n' 'finaliseerimisest keelduti: tõendid ei tuvasta täpselt seda kandidaati' >&2
  exit 1
}

cd "$repo_root"
[ -z "$(git status --porcelain --untracked-files=normal)" ] || {
  printf '%s\n' 'finaliseerimisest keelduti: tööpuu peab olema puhas' >&2
  exit 1
}
head_commit=$(git rev-parse HEAD)
tag_commit=$(git rev-parse -q --verify "refs/tags/$release_tag^{commit}" 2>/dev/null || true)
[ "$head_commit" = "$candidate_commit" ] && [ "$tag_commit" = "$candidate_commit" ] || {
  printf '%s\n' 'finaliseerimisest keelduti: kandidaadi tägi ja commit pole praegused' >&2
  exit 1
}

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/automaatkorrektor-finalize.XXXXXX")
promotion_directory=''
cleanup() {
  rm -rf "$temporary_directory"
  if [ -n "$promotion_directory" ]; then
    rm -rf "$promotion_directory"
  fi
}
trap cleanup EXIT HUP INT TERM
ready_report="$temporary_directory/release-evidence.md"
"$repo_root/scripts/release-gate.sh" \
  --manual-evidence "$manual_evidence_path" \
  --report "$ready_report"
grep -Fq '**Väljalaskeotsus:** READY' "$ready_report" || {
  printf '%s\n' 'finaliseerimisest keelduti: väljalasketõendid ei ole olekus READY' >&2
  exit 1
}
grep -Fq -- "- Commit: \`$candidate_commit\`" "$ready_report" || {
  printf '%s\n' "finaliseerimisest keelduti: READY tõendid käivad teise commit'i kohta" >&2
  exit 1
}
{
  printf '\n## Kandidaadi seos\n\n'
  printf -- '- Tag: `%s`\n' "$release_tag"
  printf -- '- Commit: `%s`\n' "$candidate_commit"
} >> "$ready_report"

mkdir -p "$output_directory"
final_dmg_path="$output_directory/$candidate_name"
metadata_path="$output_directory/$artifact_base.release-metadata.txt"
report_path="$output_directory/$artifact_base.release-evidence.md"
for output_path in "$final_dmg_path" "$metadata_path" "$report_path"; do
  [ ! -e "$output_path" ] || {
    printf 'finaliseerimisest keelduti: väljund on juba olemas: %s\n' "$output_path" >&2
    exit 1
  }
done

promotion_directory=$(mktemp -d "$output_directory/.automaatkorrektor-finalize.XXXXXX")
cp "$candidate_path" "$promotion_directory/$candidate_name"
cmp -s "$candidate_path" "$promotion_directory/$candidate_name" || {
  printf '%s\n' 'finaliseerimisest keelduti: edutatud DMG erineb testitud kandidaadist' >&2
  exit 1
}

{
  printf 'Format-Version: 1\n'
  printf 'Tag: %s\n' "$release_tag"
  printf 'Commit: %s\n' "$candidate_commit"
} > "$promotion_directory/$artifact_base.release-metadata.txt"
cp "$ready_report" "$promotion_directory/$artifact_base.release-evidence.md"

for artifact_name in \
  "$candidate_name" \
  "$artifact_base.release-metadata.txt" \
  "$artifact_base.release-evidence.md"
do
  mv -n "$promotion_directory/$artifact_name" "$output_directory/$artifact_name"
  [ ! -e "$promotion_directory/$artifact_name" ] || {
    printf 'finaliseerimisest keelduti: edutamise ajal tekkis väljund: %s\n' \
      "$output_directory/$artifact_name" >&2
    exit 1
  }
done

cmp -s "$candidate_path" "$final_dmg_path" || {
  printf '%s\n' 'finaliseerimisest keelduti: lõplik DMG erineb testitud kandidaadist' >&2
  exit 1
}

printf 'Lõplik DMG: %s\n' "$final_dmg_path"
printf 'Metaandmed: %s\n' "$metadata_path"
printf 'READY tõendid: %s\n' "$report_path"
