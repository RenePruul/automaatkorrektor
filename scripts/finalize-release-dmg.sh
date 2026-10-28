#!/bin/sh
set -eu

usage() {
  printf '%s\n' \
    'usage: scripts/finalize-release-dmg.sh --candidate PATH --manual-evidence PATH [--output-dir PATH]'
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

[ -f "$candidate_path" ] || { printf '%s\n' 'finalization refused: candidate DMG not found' >&2; exit 1; }
[ -f "$manual_evidence_path" ] || { printf '%s\n' 'finalization refused: manual evidence not found' >&2; exit 1; }
[ -n "$output_directory" ] || output_directory="$repo_root/.release-evidence/releases"

candidate_directory=$(CDPATH= cd -- "$(dirname "$candidate_path")" && pwd)
candidate_name=$(basename "$candidate_path")
candidate_path="$candidate_directory/$candidate_name"
case "$candidate_name" in
  Automaatkorrektor-*.dmg) ;;
  *) printf '%s\n' 'finalization refused: unexpected candidate filename' >&2; exit 1 ;;
esac
artifact_base=${candidate_name%.dmg}
candidate_metadata="$candidate_directory/$artifact_base.candidate-metadata.txt"
[ -f "$candidate_metadata" ] || {
  printf '%s\n' 'finalization refused: candidate metadata not found' >&2
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
  printf '%s\n' 'finalization refused: unsupported candidate metadata' >&2
  exit 1
}
release_tag=$(metadata_value Tag)
candidate_commit=$(metadata_value Commit)
recorded_sha256=$(metadata_value Candidate-SHA256)
actual_sha256=$(shasum -a 256 "$candidate_path" | awk '{print $1}')
[ -n "$release_tag" ] && [ -n "$candidate_commit" ] && [ -n "$recorded_sha256" ] || {
  printf '%s\n' 'finalization refused: incomplete candidate metadata' >&2
  exit 1
}
[ "$candidate_name" = "Automaatkorrektor-$release_tag.dmg" ] || {
  printf '%s\n' 'finalization refused: candidate filename does not match its tag' >&2
  exit 1
}
[ "$recorded_sha256" = "$actual_sha256" ] || {
  printf '%s\n' 'finalization refused: candidate bytes changed after build' >&2
  exit 1
}
[ "$(evidence_value Candidate-Tag 2>/dev/null || true)" = "$release_tag" ] && \
  [ "$(evidence_value Candidate-Commit 2>/dev/null || true)" = "$candidate_commit" ] && \
  [ "$(evidence_value Candidate-SHA256 2>/dev/null || true)" = "$actual_sha256" ] || {
  printf '%s\n' 'finalization refused: evidence does not identify this exact candidate' >&2
  exit 1
}

cd "$repo_root"
[ -z "$(git status --porcelain --untracked-files=normal)" ] || {
  printf '%s\n' 'finalization refused: working tree must be clean' >&2
  exit 1
}
head_commit=$(git rev-parse HEAD)
tag_commit=$(git rev-parse -q --verify "refs/tags/$release_tag^{commit}" 2>/dev/null || true)
[ "$head_commit" = "$candidate_commit" ] && [ "$tag_commit" = "$candidate_commit" ] || {
  printf '%s\n' 'finalization refused: candidate tag and commit are not current' >&2
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
grep -Fq '**Release decision:** READY' "$ready_report" || {
  printf '%s\n' 'finalization refused: release evidence is not READY' >&2
  exit 1
}
grep -Fq -- "- Commit: \`$candidate_commit\`" "$ready_report" || {
  printf '%s\n' 'finalization refused: READY evidence is for another commit' >&2
  exit 1
}
{
  printf '\n## Candidate binding\n\n'
  printf -- '- Tag: `%s`\n' "$release_tag"
  printf -- '- Commit: `%s`\n' "$candidate_commit"
  printf -- '- DMG SHA-256: `%s`\n' "$actual_sha256"
} >> "$ready_report"

mkdir -p "$output_directory"
final_dmg_path="$output_directory/$candidate_name"
checksum_path="$output_directory/$candidate_name.sha256"
metadata_path="$output_directory/$artifact_base.release-metadata.txt"
report_path="$output_directory/$artifact_base.release-evidence.md"
for output_path in "$final_dmg_path" "$checksum_path" "$metadata_path" "$report_path"; do
  [ ! -e "$output_path" ] || {
    printf 'finalization refused: output already exists: %s\n' "$output_path" >&2
    exit 1
  }
done

promotion_directory=$(mktemp -d "$output_directory/.automaatkorrektor-finalize.XXXXXX")
cp "$candidate_path" "$promotion_directory/$candidate_name"
promoted_sha256=$(shasum -a 256 "$promotion_directory/$candidate_name" | awk '{print $1}')
[ "$promoted_sha256" = "$recorded_sha256" ] || {
  printf '%s\n' 'finalization refused: promoted DMG differs from tested candidate' >&2
  exit 1
}

printf '%s  %s\n' "$actual_sha256" "$candidate_name" \
  > "$promotion_directory/$candidate_name.sha256"
{
  printf 'Format-Version: 1\n'
  printf 'Tag: %s\n' "$release_tag"
  printf 'Commit: %s\n' "$candidate_commit"
  printf 'DMG-SHA256: %s\n' "$actual_sha256"
} > "$promotion_directory/$artifact_base.release-metadata.txt"
cp "$ready_report" "$promotion_directory/$artifact_base.release-evidence.md"

final_candidate_sha256=$(shasum -a 256 "$candidate_path" | awk '{print $1}')
[ "$final_candidate_sha256" = "$recorded_sha256" ] || {
  printf '%s\n' 'finalization refused: candidate bytes changed during finalization' >&2
  exit 1
}

for artifact_name in \
  "$candidate_name" \
  "$candidate_name.sha256" \
  "$artifact_base.release-metadata.txt" \
  "$artifact_base.release-evidence.md"
do
  mv -n "$promotion_directory/$artifact_name" "$output_directory/$artifact_name"
  [ ! -e "$promotion_directory/$artifact_name" ] || {
    printf 'finalization refused: output appeared during promotion: %s\n' \
      "$output_directory/$artifact_name" >&2
    exit 1
  }
done

final_sha256=$(shasum -a 256 "$final_dmg_path" | awk '{print $1}')
[ "$final_sha256" = "$recorded_sha256" ] || {
  printf '%s\n' 'finalization refused: final DMG differs from tested candidate' >&2
  exit 1
}

printf 'Final DMG: %s\n' "$final_dmg_path"
printf 'SHA-256: %s\n' "$checksum_path"
printf 'Metadata: %s\n' "$metadata_path"
printf 'READY evidence: %s\n' "$report_path"
