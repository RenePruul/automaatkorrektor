#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/automaatkorrektor-release-gate-tests.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

fake_bin="$temporary_directory/bin"
mkdir -p "$fake_bin"

cat > "$fake_bin/swift" <<'EOF'
#!/bin/sh
case "$1" in
  test) printf '%s\n' 'Test run with 68 tests passed.' ;;
  format) exit 0 ;;
  *) exit 64 ;;
esac
EOF

cat > "$fake_bin/xcodebuild" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "-version" ]; then
  printf '%s\n' 'Xcode 26.3' 'Build version 17C529'
else
  printf '%s\n' '** BUILD SUCCEEDED **'
fi
EOF

cat > "$fake_bin/sw_vers" <<'EOF'
#!/bin/sh
printf '%s\n' 'ProductName: macOS' 'ProductVersion: 15.7.1' 'BuildVersion: 24G231'
EOF

cat > "$fake_bin/git" <<'EOF'
#!/bin/sh
if [ "${1:-}" = '-C' ]; then
  shift 2
fi
case "${1:-} ${2:-}" in
  'rev-parse HEAD') printf '%s\n' '0123456789abcdef0123456789abcdef01234567' ;;
  'status --porcelain') exit 0 ;;
  'diff --check') exit 0 ;;
  *) exec /usr/bin/git "$@" ;;
esac
EOF

cat > "$fake_bin/defaults" <<'EOF'
#!/bin/sh
case "$*" in
  *Safari*CFBundleShortVersionString*) printf '%s\n' '18.6' ;;
  *Google\ Chrome*CFBundleShortVersionString*) printf '%s\n' '141.0' ;;
  *) exit 1 ;;
esac
EOF

chmod +x "$fake_bin"/*
expected_commit=0123456789abcdef0123456789abcdef01234567

report="$temporary_directory/report.md"
set +e
PATH="$fake_bin:$PATH" \
  RELEASE_GATE_SKIP_EXECUTION=0 \
  "$repo_root/scripts/release-gate.sh" --report "$report"
exit_code=$?
set -e

if [ "$exit_code" -ne 2 ]; then
  printf 'expected blocked exit code 2, got %s\n' "$exit_code" >&2
  exit 1
fi

test "$(grep -Ec '^\| (PASS|FAIL|PENDING) \|' "$report")" -eq 29
grep -Fq '| PASS | core-eligibility |' "$report"
grep -Fq '| PENDING | integration-native-host |' "$report"
grep -Fq '| PENDING | manual-textedit |' "$report"
grep -Fq '| PENDING | boundary-api-contract |' "$report"
grep -Fq '**Release decision:** BLOCKED' "$report"
grep -Fq "$expected_commit" "$report"
grep -Fq 'Xcode 26.3' "$report"
grep -Fq 'Safari 18.6' "$report"
grep -Fq 'Chrome 141.0' "$report"

if grep -Fq 'AUTOMAATKORREKTOR-PRIVACY-CANARY-' "$report"; then
  printf 'report contains the private canary prefix\n' >&2
  exit 1
fi

printf '%s\n' 'release gate contract tests passed'

invalid_manual="$temporary_directory/invalid-manual.tsv"
printf 'manual-textedit\tPASS\t\n' > "$invalid_manual"
set +e
PATH="$fake_bin:$PATH" "$repo_root/scripts/release-gate.sh" \
  --manual-evidence "$invalid_manual" --report "$temporary_directory/invalid-report.md" \
  >/dev/null 2>&1
invalid_exit_code=$?
set -e
test "$invalid_exit_code" -eq 64

complete_manual="$temporary_directory/complete-manual.tsv"
for evidence_id in \
  integration-native-host integration-permission manual-textedit manual-safari \
  manual-chrome manual-permission-ui manual-menu-shortcut \
  manual-errors-cancellation manual-privacy-canary manual-supported-os \
  boundary-api-contract
do
  printf '%s\tPASS\tVerified with synthetic fixtures; metadata recorded externally.\n' \
    "$evidence_id" >> "$complete_manual"
done

PATH="$fake_bin:$PATH" "$repo_root/scripts/release-gate.sh" \
  --manual-evidence "$complete_manual" --report "$temporary_directory/ready-report.md" \
  >/dev/null
grep -Fq '**Release decision:** READY' "$temporary_directory/ready-report.md"
test "$(grep -Ec '^\| PASS \|' "$temporary_directory/ready-report.md")" -eq 29

printf '%s\n' 'manual evidence validation tests passed'
