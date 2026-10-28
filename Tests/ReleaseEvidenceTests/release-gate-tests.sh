#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/automaatkorrektor-release-gate-tests.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

fake_bin="$temporary_directory/bin"
mkdir -p "$fake_bin"

cat > "$fake_bin/swift" <<'EOF'
#!/bin/sh
if [ "${RELEASE_GATE_TEST_HANG_FORMAT:-0}" = 1 ] && [ "${1:-}" = format ]; then
  (trap '' TERM; sleep 30) &
  child_pid=$!
  printf '%s\n' "$child_pid" > "${RELEASE_GATE_TEST_CHILD_PID_FILE:?}"
  wait "$child_pid"
fi
case "$1" in
  test) printf '%s\n' 'Test run with 68 tests passed.' ;;
  format) exit 0 ;;
  *) exit 64 ;;
esac
EOF

cat > "$fake_bin/python3" <<'EOF'
#!/bin/sh
printf '%s\n' 'Ran 5 tests' 'OK'
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

test "$(grep -Ec '^\| (PASS|FAIL|PENDING) \|' "$report")" -eq 35
grep -Fq '| PASS | core-eligibility |' "$report"
grep -Fq '| PASS | language-check-consent-decline |' "$report"
grep -Fq '| PASS | language-check-consent-grant |' "$report"
grep -Fq '| PASS | language-check-consent-origin-change |' "$report"
grep -Fq '| PASS | language-check-consent-revocation |' "$report"
grep -Fq '| PENDING | integration-native-host |' "$report"
grep -Fq '| PENDING | manual-textedit |' "$report"
grep -Fq '| PENDING | manual-dmg-install |' "$report"
grep -Fq '| PENDING | manual-language-check-consent |' "$report"
grep -Fq '| PENDING | boundary-api-contract |' "$report"
grep -Fq '**Väljalaskeotsus:** BLOCKED' "$report"
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
  manual-dmg-install manual-language-check-consent \
  boundary-api-contract
do
  printf '%s\tPASS\tVerified with synthetic fixtures; metadata recorded externally.\n' \
    "$evidence_id" >> "$complete_manual"
done

PATH="$fake_bin:$PATH" "$repo_root/scripts/release-gate.sh" \
  --manual-evidence "$complete_manual" --report "$temporary_directory/ready-report.md" \
  >/dev/null
grep -Fq '**Väljalaskeotsus:** READY' "$temporary_directory/ready-report.md"
test "$(grep -Ec '^\| PASS \|' "$temporary_directory/ready-report.md")" -eq 35

printf '%s\n' 'manual evidence validation tests passed'

timeout_log="$temporary_directory/timeout-commands.log"
timeout_report="$temporary_directory/timeout-report.md"
child_pid_file="$temporary_directory/hanging-child.pid"
started_at=$(date +%s)
set +e
PATH="$fake_bin:$PATH" \
  RELEASE_GATE_TEST_HANG_FORMAT=1 \
  RELEASE_GATE_TEST_CHILD_PID_FILE="$child_pid_file" \
  RELEASE_GATE_TIMEOUT_SECONDS=1 \
  RELEASE_GATE_KILL_GRACE_SECONDS=0 \
  RELEASE_GATE_COMMAND_LOG_PATH="$timeout_log" \
  "$repo_root/scripts/release-gate.sh" --report "$timeout_report" \
  >/dev/null 2>&1
timeout_exit_code=$?
set -e
elapsed_seconds=$(($(date +%s) - started_at))

test "$timeout_exit_code" -eq 2
test "$elapsed_seconds" -lt 5
grep -Fq 'TIMEOUT: strict Swift format exceeded 1s; terminating process tree.' "$timeout_log"
grep -Fq 'FAIL: strict Swift format (timed out after 1s)' "$timeout_log"
test -s "$child_pid_file"
hanging_child_pid=$(cat "$child_pid_file")
cleanup_attempt=0
while kill -0 "$hanging_child_pid" 2>/dev/null && [ "$cleanup_attempt" -lt 20 ]; do
  sleep 0.05
  cleanup_attempt=$((cleanup_attempt + 1))
done
if kill -0 "$hanging_child_pid" 2>/dev/null; then
  printf 'hanging child process %s survived the release-gate timeout\n' \
    "$hanging_child_pid" >&2
  exit 1
fi

printf '%s\n' 'release gate timeout contract tests passed'

assert_process_stopped() {
  stopped_process_id=$1
  stop_attempt=0
  while kill -0 "$stopped_process_id" 2>/dev/null && [ "$stop_attempt" -lt 20 ]; do
    sleep 0.05
    stop_attempt=$((stop_attempt + 1))
  done
  if kill -0 "$stopped_process_id" 2>/dev/null; then
    printf 'process %s survived release-gate signal cleanup\n' \
      "$stopped_process_id" >&2
    exit 1
  fi
}

collect_descendant_pids() {
  descendant_parent_pid=$1
  for descendant_pid in $(/usr/bin/pgrep -P "$descendant_parent_pid" 2>/dev/null || true); do
    printf '%s ' "$descendant_pid"
    collect_descendant_pids "$descendant_pid"
  done
}

run_signal_cleanup_case() {
  signal_name=$1
  expected_exit_code=$2
  case_directory="$temporary_directory/signal-$signal_name"
  signal_tmp="$case_directory/tmp"
  signal_output="$case_directory/output.log"
  signal_report="$case_directory/report.md"
  signal_child_pid_file="$case_directory/hanging-child.pid"
  mkdir -p "$signal_tmp"

  set -m
  PATH="$fake_bin:$PATH" \
    TMPDIR="$signal_tmp" \
    RELEASE_GATE_TEST_HANG_FORMAT=1 \
    RELEASE_GATE_TEST_CHILD_PID_FILE="$signal_child_pid_file" \
    RELEASE_GATE_TIMEOUT_SECONDS=30 \
    RELEASE_GATE_KILL_GRACE_SECONDS=0 \
    "$repo_root/scripts/release-gate.sh" --report "$signal_report" \
    >"$signal_output" 2>&1 &
  gate_pid=$!
  set +m

  start_attempt=0
  while [ ! -s "$signal_child_pid_file" ] && [ "$start_attempt" -lt 40 ]; do
    sleep 0.05
    start_attempt=$((start_attempt + 1))
  done
  test -s "$signal_child_pid_file"

  tracked_process_ids="$gate_pid $(cat "$signal_child_pid_file")"
  tracked_process_ids="$tracked_process_ids $(collect_descendant_pids "$gate_pid")"

  kill -"$signal_name" "$gate_pid"
  set +e
  wait "$gate_pid"
  signal_exit_code=$?
  set -e

  test "$signal_exit_code" -eq "$expected_exit_code"
  for tracked_process_id in $tracked_process_ids; do
    assert_process_stopped "$tracked_process_id"
  done
  test ! -e "$signal_report"
  if grep -Fq '==> Git whitespace' "$signal_output"; then
    printf 'release gate continued after %s\n' "$signal_name" >&2
    exit 1
  fi
  set -- "$signal_tmp"/automaatkorrektor-release-gate.*
  test ! -e "$1"
}

run_signal_cleanup_case TERM 143
run_signal_cleanup_case INT 130
run_signal_cleanup_case HUP 129

printf '%s\n' 'release gate signal cleanup contract tests passed'
