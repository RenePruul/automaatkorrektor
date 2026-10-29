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
gate_output="$temporary_directory/gate-output.log"
set +e
PATH="$fake_bin:$PATH" \
  RELEASE_GATE_SKIP_EXECUTION=0 \
  "$repo_root/scripts/release-gate.sh" >"$gate_output" 2>&1
exit_code=$?
set -e

if [ "$exit_code" -ne 0 ]; then
  printf 'oodati edukat olekukoodi 0, saadi %s\n' "$exit_code" >&2
  cat "$gate_output" >&2
  exit 1
fi

grep -Fq 'Kõik automaatkontrollid läbitud.' "$gate_output"
grep -Fq '==> Xcode päris AX-testirakenduste build' "$gate_output"

printf '%s\n' 'väljalaskevärava automaatkontrollide lepingutestid läbitud'

timeout_log="$temporary_directory/timeout-commands.log"
child_pid_file="$temporary_directory/hanging-child.pid"
started_at=$(date +%s)
set +e
PATH="$fake_bin:$PATH" \
  RELEASE_GATE_TEST_HANG_FORMAT=1 \
  RELEASE_GATE_TEST_CHILD_PID_FILE="$child_pid_file" \
  RELEASE_GATE_TIMEOUT_SECONDS=1 \
  RELEASE_GATE_KILL_GRACE_SECONDS=0 \
  RELEASE_GATE_COMMAND_LOG_PATH="$timeout_log" \
  "$repo_root/scripts/release-gate.sh" \
  >/dev/null 2>&1
timeout_exit_code=$?
set -e
elapsed_seconds=$(($(date +%s) - started_at))

test "$timeout_exit_code" -eq 1
test "$elapsed_seconds" -lt 5
grep -Fq 'AJALIMIIT: range Swift-vormindus ületas 1s; protsessipuu lõpetatakse.' "$timeout_log"
grep -Fq 'FAIL: range Swift-vormindus (ajalimiit 1s)' "$timeout_log"
test -s "$child_pid_file"
hanging_child_pid=$(cat "$child_pid_file")
cleanup_attempt=0
while kill -0 "$hanging_child_pid" 2>/dev/null && [ "$cleanup_attempt" -lt 20 ]; do
  sleep 0.05
  cleanup_attempt=$((cleanup_attempt + 1))
done
if kill -0 "$hanging_child_pid" 2>/dev/null; then
  printf 'hangunud alamprotsess %s jäi pärast väljalaskevärava ajalimiiti tööle\n' \
    "$hanging_child_pid" >&2
  exit 1
fi

printf '%s\n' 'väljalaskevärava ajalimiidi lepingutestid läbitud'

assert_process_stopped() {
  stopped_process_id=$1
  stop_attempt=0
  while kill -0 "$stopped_process_id" 2>/dev/null && [ "$stop_attempt" -lt 20 ]; do
    sleep 0.05
    stop_attempt=$((stop_attempt + 1))
  done
  if kill -0 "$stopped_process_id" 2>/dev/null; then
    printf 'protsess %s jäi pärast väljalaskevärava signaalipuhastust tööle\n' \
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
  signal_child_pid_file="$case_directory/hanging-child.pid"
  mkdir -p "$signal_tmp"

  set -m
  PATH="$fake_bin:$PATH" \
    TMPDIR="$signal_tmp" \
    RELEASE_GATE_TEST_HANG_FORMAT=1 \
    RELEASE_GATE_TEST_CHILD_PID_FILE="$signal_child_pid_file" \
    RELEASE_GATE_TIMEOUT_SECONDS=30 \
    RELEASE_GATE_KILL_GRACE_SECONDS=0 \
    "$repo_root/scripts/release-gate.sh" \
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
  if grep -Fq '==> Giti tühimärgid' "$signal_output"; then
    printf 'väljalaskevärav jätkas pärast signaali %s\n' "$signal_name" >&2
    exit 1
  fi
  set -- "$signal_tmp"/automaatkorrektor-release-gate.*
  test ! -e "$1"
}

run_signal_cleanup_case TERM 143
run_signal_cleanup_case INT 130
run_signal_cleanup_case HUP 129

printf '%s\n' 'väljalaskevärava signaalipuhastuse lepingutestid läbitud'
