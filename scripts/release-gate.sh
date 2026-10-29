#!/bin/bash
set -u

usage() {
  printf '%s\n' 'kasutus: scripts/release-gate.sh'
}

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

while [ "$#" -gt 0 ]; do
  case "$1" in
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

# Igal välisel kontrollil on ajalimiit, et hangunud kompilaator, paketihaldur
# või testiprotsess ei saaks väljalaskeväravat lõputult kinni hoida. Üldine
# ajalimiit on mõeldud värava lepingutestidele; tavakäivitused kasutavad
# allpool iga kontrolli jaoks määratud piirangut.
timeout_override=${RELEASE_GATE_TIMEOUT_SECONDS:-}
kill_grace_seconds=${RELEASE_GATE_KILL_GRACE_SECONDS:-2}
case "$timeout_override" in ''|*[!0-9]*)
  [ -z "$timeout_override" ] || { printf '%s\n' 'RELEASE_GATE_TIMEOUT_SECONDS peab olema positiivne täisarv' >&2; exit 64; }
  ;;
0) printf '%s\n' 'RELEASE_GATE_TIMEOUT_SECONDS peab olema positiivne täisarv' >&2; exit 64 ;;
esac
case "$kill_grace_seconds" in ''|*[!0-9]*)
  printf '%s\n' 'RELEASE_GATE_KILL_GRACE_SECONDS peab olema mittenegatiivne täisarv' >&2
  exit 64
  ;;
esac

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/automaatkorrektor-release-gate.XXXXXX")
active_command_group=""
active_watchdog_group=""

terminate_process_group() {
  process_group_id=$1
  signal=$2
  /bin/kill -"$signal" -- "-$process_group_id" 2>/dev/null || true
}

process_group_is_running() {
  /bin/kill -0 -- "-$1" 2>/dev/null
}

terminate_active_process_groups() {
  for process_group_id in "$active_command_group" "$active_watchdog_group"; do
    [ -z "$process_group_id" ] || terminate_process_group "$process_group_id" TERM
  done

  remaining_checks=$((kill_grace_seconds * 10))
  while [ "$remaining_checks" -gt 0 ]; do
    groups_are_running=false
    for process_group_id in "$active_command_group" "$active_watchdog_group"; do
      if [ -n "$process_group_id" ] && process_group_is_running "$process_group_id"; then
        groups_are_running=true
      fi
    done
    [ "$groups_are_running" = true ] || break
    sleep 0.1
    remaining_checks=$((remaining_checks - 1))
  done

  for process_group_id in "$active_command_group" "$active_watchdog_group"; do
    if [ -n "$process_group_id" ] && process_group_is_running "$process_group_id"; then
      terminate_process_group "$process_group_id" KILL
    fi
  done
  [ -z "$active_command_group" ] || wait "$active_command_group" 2>/dev/null || true
  [ -z "$active_watchdog_group" ] || wait "$active_watchdog_group" 2>/dev/null || true
  active_command_group=""
  active_watchdog_group=""
}

cleanup_on_exit() {
  trap - EXIT
  rm -rf "$temporary_directory"
}

cleanup_on_signal() {
  signal_exit_code=$1
  trap - EXIT
  trap '' HUP INT TERM
  terminate_active_process_groups
  rm -rf "$temporary_directory"
  exit "$signal_exit_code"
}

trap cleanup_on_exit EXIT
trap 'cleanup_on_signal 129' HUP
trap 'cleanup_on_signal 130' INT
trap 'cleanup_on_signal 143' TERM

command_log=${RELEASE_GATE_COMMAND_LOG_PATH:-"$temporary_directory/commands.log"}
mkdir -p "$(dirname "$command_log")"

export CLANG_MODULE_CACHE_PATH="$temporary_directory/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$temporary_directory/swiftpm-module-cache"

overall_automation=PASS
last_check_status=PASS
run_check() {
  label=$1
  default_timeout=$2
  timeout_seconds=${timeout_override:-$default_timeout}
  shift
  shift
  timeout_marker="$temporary_directory/timeout-marker-$$"
  rm -f "$timeout_marker"
  printf '==> %s\n' "$label"
  # Tööde juhtimine annab käsule ja kõigile alamprotsessidele eraldi
  # protsessirühma. Nii saab valvur lõpetada macOS-is kogu protsessipuu ilma
  # GNU timeout(1) käsust sõltumata.
  set -m
  "$@" >>"$command_log" 2>&1 &
  command_pid=$!
  active_command_group=$command_pid
  set +m
  set -m
  (
    sleep "$timeout_seconds"
    if kill -0 "$command_pid" 2>/dev/null; then
      printf 'AJALIMIIT: %s ületas %ss; protsessipuu lõpetatakse.\n' \
        "$label" "$timeout_seconds" >>"$command_log"
      : > "$timeout_marker"
      terminate_process_group "$command_pid" TERM
      sleep "$kill_grace_seconds"
      terminate_process_group "$command_pid" KILL
    fi
  ) &
  watchdog_pid=$!
  active_watchdog_group=$watchdog_pid
  set +m

  if wait "$command_pid"; then
    command_wait_status=0
  else
    command_wait_status=$?
  fi
  active_command_group=""
  if [ "$command_wait_status" -eq 0 ]; then
    command_succeeded=true
  else
    command_succeeded=false
  fi
  if [ -f "$timeout_marker" ]; then
    if wait "$watchdog_pid" 2>/dev/null; then
      watchdog_wait_status=0
    else
      watchdog_wait_status=$?
    fi
  else
    terminate_process_group "$watchdog_pid" TERM
    if wait "$watchdog_pid" 2>/dev/null; then
      watchdog_wait_status=0
    else
      watchdog_wait_status=$?
    fi
  fi
  active_watchdog_group=""

  if [ -f "$timeout_marker" ]; then
    printf 'FAIL: %s (ajalimiit %ss)\n' "$label" "$timeout_seconds" >>"$command_log"
    overall_automation=FAIL
    last_check_status=TIMEOUT
  elif [ "$command_succeeded" = true ]; then
    printf 'PASS: %s\n' "$label" >>"$command_log"
    last_check_status=PASS
  else
    printf 'FAIL: %s\n' "$label" >>"$command_log"
    overall_automation=FAIL
    last_check_status=FAIL
  fi
}

cd "$repo_root" || exit 1
run_check 'range Swift-vormindus' 120 swift format lint --recursive --strict Sources Tests Package.swift
run_check 'Giti tühimärgid' 120 git diff --check
run_check 'puhas Giti tööpuu' 120 /bin/sh -c \
  'test -z "$(git status --porcelain --untracked-files=normal)"'
run_check 'võrguühenduseta keele-API fixture-testid' 300 \
  python3 -m unittest discover -s Tests/ReleaseEvidenceTests -p 'test_*.py'
run_check 'Swifti paketitestid' 600 swift test
run_check 'Xcode macOS build' 900 xcodebuild \
  -project apps/macos/Automaatkorrektor.xcodeproj \
  -scheme Automaatkorrektor \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$temporary_directory/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build
run_check 'Xcode päris AX-testirakenduste build' 900 xcodebuild \
  -project apps/macos/Automaatkorrektor.xcodeproj \
  -scheme NativeAXEvidence \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$temporary_directory/NativeAXDerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [ "$overall_automation" = PASS ]; then
  printf '%s\n' 'Kõik automaatkontrollid läbitud.'
  exit 0
fi

printf '%s\n' 'Vähemalt üks automaatkontroll ebaõnnestus.' >&2
cat "$command_log" >&2
exit 1
