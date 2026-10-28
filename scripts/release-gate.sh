#!/bin/bash
set -u

usage() {
  printf '%s\n' 'usage: scripts/release-gate.sh [--report PATH] [--manual-evidence PATH]'
}

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
report_path="$repo_root/.release-evidence/report.md"
manual_evidence_path=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --report)
      [ "$#" -ge 2 ] || { usage >&2; exit 64; }
      report_path=$2
      shift 2
      ;;
    --manual-evidence)
      [ "$#" -ge 2 ] || { usage >&2; exit 64; }
      manual_evidence_path=$2
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

# Each external check is bounded so a wedged compiler, package manager, or test
# process cannot hold the release gate forever. The override is intended for
# the gate's contract tests; normal runs use the per-check limits below.
timeout_override=${RELEASE_GATE_TIMEOUT_SECONDS:-}
kill_grace_seconds=${RELEASE_GATE_KILL_GRACE_SECONDS:-2}
case "$timeout_override" in ''|*[!0-9]*)
  [ -z "$timeout_override" ] || { printf '%s\n' 'RELEASE_GATE_TIMEOUT_SECONDS must be a positive integer' >&2; exit 64; }
  ;;
0) printf '%s\n' 'RELEASE_GATE_TIMEOUT_SECONDS must be a positive integer' >&2; exit 64 ;;
esac
case "$kill_grace_seconds" in ''|*[!0-9]*)
  printf '%s\n' 'RELEASE_GATE_KILL_GRACE_SECONDS must be a non-negative integer' >&2
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
mkdir -p "$(dirname "$report_path")"

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
  # Job control gives the command and all descendants an isolated process
  # group, allowing the watchdog to terminate the entire tree portably on
  # macOS without relying on GNU timeout(1).
  set -m
  "$@" >>"$command_log" 2>&1 &
  command_pid=$!
  active_command_group=$command_pid
  set +m
  set -m
  (
    sleep "$timeout_seconds"
    if kill -0 "$command_pid" 2>/dev/null; then
      printf 'TIMEOUT: %s exceeded %ss; terminating process tree.\n' \
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
    printf 'FAIL: %s (timed out after %ss)\n' "$label" "$timeout_seconds" >>"$command_log"
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
run_check 'strict Swift format' 120 swift format lint --recursive --strict Sources Tests Package.swift
run_check 'Git whitespace' 120 git diff --check
run_check 'clean Git tree' 120 /bin/sh -c \
  'test -z "$(git status --porcelain --untracked-files=normal)"'
if [ "$last_check_status" = PASS ]; then
  tree_state=clean
else
  tree_state=dirty
fi
run_check 'offline language API fixture tests' 300 \
  python3 -m unittest discover -s Tests/ReleaseEvidenceTests -p 'test_*.py'
run_check 'Swift package tests' 600 swift test
run_check 'Xcode macOS build' 900 xcodebuild \
  -project apps/macos/Automaatkorrektor.xcodeproj \
  -scheme Automaatkorrektor \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$temporary_directory/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build
run_check 'Xcode native AX evidence apps build' 900 xcodebuild \
  -project apps/macos/Automaatkorrektor.xcodeproj \
  -scheme NativeAXEvidence \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$temporary_directory/NativeAXDerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build

commit=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf '%s' unknown)
os_version=$(sw_vers 2>/dev/null | paste -sd '; ' - || printf '%s' unavailable)
xcode_version=$(xcodebuild -version 2>/dev/null | paste -sd '; ' - || printf '%s' unavailable)
safari_version=$(defaults read /Applications/Safari.app/Contents/Info CFBundleShortVersionString 2>/dev/null || printf '%s' unavailable)
chrome_version=$(defaults read '/Applications/Google Chrome.app/Contents/Info' CFBundleShortVersionString 2>/dev/null || printf '%s' unavailable)

if [ -n "$manual_evidence_path" ]; then
  if [ ! -f "$manual_evidence_path" ]; then
    printf 'manual evidence file not found: %s\n' "$manual_evidence_path" >&2
    exit 64
  fi
  seen_evidence="$temporary_directory/seen-manual-evidence"
  : > "$seen_evidence"
  while IFS=$'\t' read -r evidence_id evidence_status evidence_note; do
    case "$evidence_id" in ''|'#'*) continue ;; esac
    case "$evidence_id" in
      integration-native-host|integration-permission|manual-textedit|manual-safari|\
      manual-chrome|manual-permission-ui|manual-menu-shortcut|manual-errors-cancellation|\
      manual-privacy-canary|manual-supported-os|boundary-api-contract) ;;
      *)
        printf 'unknown manual evidence id: %s\n' "$evidence_id" >&2
        exit 64
        ;;
    esac
    if grep -Fxq "$evidence_id" "$seen_evidence"; then
      printf 'duplicate manual evidence id: %s\n' "$evidence_id" >&2
      exit 64
    fi
    printf '%s\n' "$evidence_id" >> "$seen_evidence"
    case "$evidence_status" in PASS|FAIL|PENDING) ;; *)
      printf 'invalid status for %s: %s\n' "$evidence_id" "$evidence_status" >&2
      exit 64
      ;;
    esac
    if [ "$evidence_status" != PENDING ] && [ -z "${evidence_note:-}" ]; then
      printf 'PASS/FAIL requires a metadata-only evidence note for %s\n' "$evidence_id" >&2
      exit 64
    fi
    case "${evidence_note:-}" in
      *'AUTOMAATKORREKTOR-PRIVACY-CANARY-'*|*'|'*)
        printf 'unsafe evidence note for %s\n' "$evidence_id" >&2
        exit 64
        ;;
    esac
  done < "$manual_evidence_path"
fi

manual_value() {
  requested_id=$1
  requested_column=$2
  awk -F '\t' -v id="$requested_id" -v column="$requested_column" \
    '$1 == id { print $column; found = 1; exit } END { if (!found) exit 1 }' \
    "$manual_evidence_path"
}

rows="$temporary_directory/rows.tsv"
: > "$rows"

add_automatic() {
  printf '%s\t%s\t%s\t%s\n' "$overall_automation" "$1" "$2" "$3" >> "$rows"
}

add_pending() {
  evidence_id=$1
  title=$2
  default_note=$3
  status=PENDING
  note=$default_note
  if [ -n "$manual_evidence_path" ]; then
    supplied_status=$(manual_value "$evidence_id" 2 2>/dev/null || true)
    supplied_note=$(manual_value "$evidence_id" 3 2>/dev/null || true)
    [ -z "$supplied_status" ] || status=$supplied_status
    [ -z "$supplied_note" ] || note=$supplied_note
  fi
  printf '%s\t%s\t%s\t%s\n' "$status" "$evidence_id" "$title" "$note" >> "$rows"
}

# Six deterministic core checks.
add_automatic core-eligibility 'Eligibility and no-read policy' 'AutomaatkorrektorMacOSTests: closed allowlist and no content access.'
add_automatic core-protected 'Protected controls' 'AutomaatkorrektorMacOSTests: protected controls stop before content or API access.'
add_automatic core-sequencing 'LanguageCheckUseCase sequencing' 'AutomaatkorrektorCoreTests: one read, one detection, verdict-only output.'
add_automatic core-latest-wins 'Latest check wins' 'AutomaatkorrektorCoreTests: obsolete work is cancelled and ignored.'
add_automatic core-presentation 'Exhaustive presentation states' 'LanguageCheckViewModelTests: approved mutually exclusive states.'
add_automatic core-permission-isolation 'Permission isolation' 'AccessibilityPermissionFlowTests: permission checks never read text.'

# Six API-adapter checks.
add_automatic api-request 'Exact POST /detect request' 'LanguageAPIAdapterTests: method, headers, URL, and one Unicode text field.'
add_automatic api-verdicts 'Three verdicts' 'LanguageAPIAdapterTests: jah, ei, and ebakindel remain distinct.'
add_automatic api-errors 'Stable error mapping' 'LanguageAPIAdapterTests: protocol, HTTP, and transport mappings.'
add_automatic api-deadline 'Three-second deadline and no retry' 'LanguageAPIAdapterTests: three-second configuration and one request.'
add_automatic api-url-policy 'Base URL security' 'APIBaseURLSettingsTests: loopback HTTP only and HTTPS elsewhere.'
add_automatic api-ephemeral 'Ephemeral log-free transport' 'LanguageAPIAdapterTests: no cache, cookies, credentials, redirects, or body logging.'

# Six adapter integration checks. Two require operator-controlled macOS state.
add_pending integration-native-host 'Test-only native AX harness' 'Run the bundled host and isolated AX harness checklist; production must reject the host.'
add_automatic integration-browser-fixture 'Offline Safari and Chrome fixture' 'Synthetic offline fixture matrix is packaged and tested.'
add_automatic integration-chrome-activation 'Chrome metadata-only activation' 'Adapter test reacquires focus after metadata-only activation.'
add_automatic integration-focus-race 'Focus-race rejection' 'Adapter tests reject identity and metadata changes before networking.'
add_pending integration-permission 'Real permission changes' 'Grant and revoke real TCC Accessibility permission using the operator checklist.'
add_automatic integration-session 'Real ephemeral URLSession configuration' 'URLProtocol integration and concrete ephemeral configuration tests pass.'

# Eight repeatable manual checks.
add_pending manual-textedit 'TextEdit' 'Run the TextEdit matrix on the release candidate.'
add_pending manual-safari 'Safari standard fields' 'Run the offline Safari fixture matrix.'
add_pending manual-chrome 'Chrome standard fields' 'Run the offline Chrome fixture matrix.'
add_pending manual-permission-ui 'Permission and recovery UI' 'Run missing, granted, and revoked permission states.'
add_pending manual-menu-shortcut 'Menu and shortcut equivalence' 'Run both explicit actions and compare visible outcomes.'
add_pending manual-errors-cancellation 'Visible failures and cancellation' 'Exercise timeout, unavailable, incompatible, and silent cancellation states.'
add_pending manual-privacy-canary 'Synthetic privacy canary' 'Run the one-use canary procedure; do not put the canary in this file or report.'
add_pending manual-supported-os 'macOS 15 or later' 'Run the core manual matrix on the current development Mac running macOS 15 or later.'

# Three release-boundary checks.
add_pending boundary-api-contract 'Tested language API contract and version' 'Record the tested API repository commit and confirm POST /detect wire compatibility.'
add_automatic boundary-supported-scope 'Limited compatibility claims' 'README claims only TextEdit and standard Safari/Chrome fields.'
add_automatic boundary-report 'Reproducible metadata-only report' 'This script records metadata, commands, and exactly 29 status rows.'

row_count=$(wc -l < "$rows" | tr -d ' ')
if [ "$row_count" -ne 29 ]; then
  printf 'internal error: expected 29 evidence rows, got %s\n' "$row_count" >&2
  exit 70
fi

failed_count=$(awk -F '\t' '$1 == "FAIL" { count += 1 } END { print count + 0 }' "$rows")
pending_count=$(awk -F '\t' '$1 == "PENDING" { count += 1 } END { print count + 0 }' "$rows")
passed_count=$(awk -F '\t' '$1 == "PASS" { count += 1 } END { print count + 0 }' "$rows")
if [ "$failed_count" -eq 0 ] && [ "$pending_count" -eq 0 ]; then
  decision=READY
else
  decision=BLOCKED
fi

{
  printf '# Automaatkorrektor macOS v0.1 release evidence\n\n'
  printf '**Release decision:** %s\n\n' "$decision"
  printf 'All 29 rows are required. A FAIL or PENDING row blocks release; there is no score or waiver.\n\n'
  printf '## Environment\n\n'
  printf -- '- Commit: `%s`\n' "$commit"
  printf -- '- Git tree: `%s`\n' "$tree_state"
  printf -- '- OS: `%s`\n' "$os_version"
  printf -- '- Xcode: `%s`\n' "$xcode_version"
  printf -- '- Safari %s\n' "$safari_version"
  printf -- '- Chrome %s\n' "$chrome_version"
  printf -- '- Result: %s passed, %s failed, %s pending\n\n' "$passed_count" "$failed_count" "$pending_count"
  printf '## Commands\n\n'
  printf '```text\n'
  printf '%s\n' 'swift format lint --recursive --strict Sources Tests Package.swift'
  printf '%s\n' 'git diff --check'
  printf '%s\n' 'git status --porcelain --untracked-files=normal'
  printf '%s\n' "python3 -m unittest discover -s Tests/ReleaseEvidenceTests -p 'test_*.py'"
  printf '%s\n' 'swift test'
  printf '%s\n' "xcodebuild -project apps/macos/Automaatkorrektor.xcodeproj -scheme Automaatkorrektor -configuration Debug -destination platform=macOS CODE_SIGNING_ALLOWED=NO build"
  printf '%s\n' "xcodebuild -project apps/macos/Automaatkorrektor.xcodeproj -scheme NativeAXEvidence -configuration Debug -destination platform=macOS CODE_SIGNING_ALLOWED=NO build"
  printf '```\n\n'
  printf '## Required evidence\n\n'
  printf '| Status | ID | Check | Evidence |\n'
  printf '|---|---|---|---|\n'
  while IFS=$'\t' read -r status evidence_id title note; do
    printf '| %s | %s | %s | %s |\n' "$status" "$evidence_id" "$title" "$note"
  done < "$rows"
  printf '\n## Privacy\n\n'
  printf 'The report intentionally contains no selected text, request body, response body, or privacy-canary value. '\
  printf 'A canary value belongs only in the one stub request body inspected during the operator procedure.\n'
} > "$report_path"

if grep -Eq 'AUTOMAATKORREKTOR-PRIVACY-CANARY-[[:alnum:]-]+' "$report_path"; then
  printf 'privacy failure: report contains a canary value\n' >&2
  exit 1
fi

printf 'Report: %s\n' "$report_path"
printf 'Decision: %s (%s pass, %s fail, %s pending)\n' \
  "$decision" "$passed_count" "$failed_count" "$pending_count"

if [ "$decision" = READY ]; then
  exit 0
fi
exit 2
