#!/bin/bash
set -u

usage() {
  printf '%s\n' 'kasutus: scripts/release-gate.sh [--report TEE] [--manual-evidence TEE]'
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
if [ "$last_check_status" = PASS ]; then
  tree_state=clean
else
  tree_state=dirty
fi
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
run_check 'Xcode päris AX-tõendirakenduste build' 900 xcodebuild \
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
    printf 'käsitõendite faili ei leitud: %s\n' "$manual_evidence_path" >&2
    exit 64
  fi
  seen_evidence="$temporary_directory/seen-manual-evidence"
  : > "$seen_evidence"
  while IFS=$'\t' read -r evidence_id evidence_status evidence_note; do
    case "$evidence_id" in ''|'#'*) continue ;; esac
    case "$evidence_id" in
      integration-native-host|integration-permission|manual-textedit|manual-safari|\
      manual-chrome|manual-permission-ui|manual-menu-shortcut|manual-errors-cancellation|\
      manual-privacy-canary|manual-supported-os|manual-dmg-install|\
      manual-language-check-consent|boundary-api-contract) ;;
      *)
        printf 'tundmatu käsitõendi ID: %s\n' "$evidence_id" >&2
        exit 64
        ;;
    esac
    if grep -Fxq "$evidence_id" "$seen_evidence"; then
      printf 'korduv käsitõendi ID: %s\n' "$evidence_id" >&2
      exit 64
    fi
    printf '%s\n' "$evidence_id" >> "$seen_evidence"
    case "$evidence_status" in PASS|FAIL|PENDING) ;; *)
      printf 'ID %s olek on vigane: %s\n' "$evidence_id" "$evidence_status" >&2
      exit 64
      ;;
    esac
    if [ "$evidence_status" != PENDING ] && [ -z "${evidence_note:-}" ]; then
      printf 'PASS/FAIL nõuab ID %s jaoks ainult metaandmetega tõendimärkust\n' "$evidence_id" >&2
      exit 64
    fi
    case "${evidence_note:-}" in
      *'AUTOMAATKORREKTOR-PRIVACY-CANARY-'*|*'|'*)
        printf 'ID %s tõendimärkus pole turvaline\n' "$evidence_id" >&2
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

# Kuus deterministlikku põhikontrolli.
add_automatic core-eligibility 'Sobivus- ja mittelugemisreegel' 'AutomaatkorrektorMacOSTests: suletud lubatud loend ja sisule juurdepääsu puudumine.'
add_automatic core-protected 'Kaitstud juhtelemendid' 'AutomaatkorrektorMacOSTests: kaitstud juhtelemendid peatavad töö enne sisule või API-le juurdepääsu.'
add_automatic core-sequencing 'LanguageCheckUseCase järjestus' 'AutomaatkorrektorCoreTests: üks lugemine, üks tuvastus ja ainult otsuse väljund.'
add_automatic core-latest-wins 'Uusim kontroll võidab' 'AutomaatkorrektorCoreTests: aegunud töö katkestatakse ja seda eiratakse.'
add_automatic core-presentation 'Täielikud kuvamisolekud' 'LanguageCheckViewModelTests: lubatud üksteist välistavad olekud.'
add_automatic core-permission-isolation 'Loa eraldatus' 'AccessibilityPermissionFlowTests: loakontroll ei loe kunagi teksti.'

# Neli keelekontrolli nõusoleku kontrolli kokkulepitud avalikul liidesel.
add_automatic language-check-consent-decline 'Keelekontrolli nõusolekust keeldumine' 'LanguageCheckUseCaseTests ja LanguageCheckConsentTests: keeldumine ei loe valikut ega tee päringut.'
add_automatic language-check-consent-grant 'Origin-põhine keelekontrolli nõusolek' 'LanguageCheckConsentTests: kuvatud origini nõusolek käivitab ühe uue selge kontrolli.'
add_automatic language-check-consent-origin-change 'Keelekontrolli nõusoleku origini muutus' 'LanguageCheckConsentTests: muutunud host või tegelik port nõuab uut nõusolekut.'
add_automatic language-check-consent-revocation 'Keelekontrolli nõusoleku tühistamine' 'LanguageCheckConsentTests: tühistamine blokeerib järgmise kontrolli enne sisule juurdepääsu.'

# Kuus API-adapteri kontrolli.
add_automatic api-request 'Täpne POST /detect päring' 'LanguageAPIAdapterTests: meetod, päised, URL ja üks Unicode-tekstiväli.'
add_automatic api-verdicts 'Kolm otsust' 'LanguageAPIAdapterTests: jah, ei ja ebakindel jäävad eristatavaks.'
add_automatic api-errors 'Stabiilne vigade vastendus' 'LanguageAPIAdapterTests: protokolli-, HTTP- ja transpordivigade vastendused.'
add_automatic api-deadline 'Kolmesekundiline tähtaeg ilma korduskatseta' 'LanguageAPIAdapterTests: kolmesekundiline seadistus ja üks päring.'
add_automatic api-url-policy 'Keeleteenuse endpoint-turvalisus' 'LanguageServiceEndpointSettingsTests: HTTP ainult loopback-aadressile ja mujal HTTPS.'
add_automatic api-ephemeral 'Ajutine logivaba transport' 'LanguageAPIAdapterTests: puuduvad vahemälu, küpsised, mandaadid, ümbersuunamised ja keha logimine.'

# Kuus adapteri integratsioonikontrolli. Kaks nõuavad haldaja juhitud macOS-i olekut.
add_pending integration-native-host 'Ainult testimiseks mõeldud päris AX-testirakendus' 'Käivita pakitud hosti ja eraldatud AX-testirakenduse juhend; tootmisrakendus peab hosti tagasi lükkama.'
add_automatic integration-browser-fixture 'Võrguühenduseta Safari ja Chrome fixture' 'Sünteetiline võrguühenduseta kontrollmaatriks on pakitud ja testitud.'
add_automatic integration-chrome-activation 'Chrome ainult metaandmetega aktiveerimine' 'Adapteritest taastab pärast ainult metaandmetega aktiveerimist fookuse.'
add_automatic integration-focus-race 'Fookuse võidujooksu tagasilükkamine' 'Adapteritestid lükkavad identiteedi ja metaandmete muutused tagasi enne võrgu kasutamist.'
add_pending integration-permission 'Päris loa muutused' 'Anna ja tühista päris TCC Accessibility-luba haldaja juhendi järgi.'
add_automatic integration-session 'Päris ajutine URLSessioni seadistus' 'URLProtocoli integratsiooni- ja konkreetse ajutise seadistuse testid läbivad.'

# Kümme korratavat käsikontrolli.
add_pending manual-textedit 'TextEdit' 'Tee väljalaskekandidaadil TextEditi kontrollmaatriks.'
add_pending manual-safari 'Safari standardväljad' 'Tee võrguühenduseta Safari fixture kontrollmaatriks.'
add_pending manual-chrome 'Chrome standardväljad' 'Tee võrguühenduseta Chrome fixture kontrollmaatriks.'
add_pending manual-permission-ui 'Loa ja taastamise vaated' 'Kontrolli puuduva, antud ja tühistatud loa olekuid.'
add_pending manual-menu-shortcut 'Menüü ja kiirklahvi samaväärsus' 'Käivita mõlemad selged toimingud ja võrdle nähtavaid tulemusi.'
add_pending manual-errors-cancellation 'Nähtavad vead ja katkestamine' 'Kontrolli ajalimiidi, kättesaamatu ja ühildumatu teenuse ning vaikse katkestamise olekuid.'
add_pending manual-privacy-canary 'Sünteetiline privaatsusnäide' 'Tee ühekordse privaatsusnäite kontroll; ära lisa näidet sellesse faili või raportisse.'
add_pending manual-supported-os 'macOS 15 või uuem' 'Tee põhikontroll arendus-Macis, kus töötab macOS 15 või uuem.'
add_pending manual-dmg-install 'Loodud DMG paigaldustee' 'Paigalda loodud DMG ning kontrolli Gatekeeperit, Accessibility-loa taastamist ja üht kohalikku kontrolli.'
add_pending manual-language-check-consent 'Keelekontrolli nõusoleku privaatsustee' 'Kontrolli ajutise sünteetilise privaatsusnäitega keeldumist, lubamist, origini muutust ja tühistamist.'

# Kolm väljalaskepiiri kontrolli.
add_pending boundary-api-contract 'Kontrollitud keele-API leping ja versioon' 'Salvesta kontrollitud API repo commit ja kinnita POST /detect juhtmeprotokolli ühilduvus.'
add_automatic boundary-supported-scope 'Piiratud ühilduvuslubadused' 'README lubab ainult TextEditi ja standardseid Safari või Chrome välju.'
add_automatic boundary-report 'Korratav ainult metaandmetega raport' 'Skript salvestab metaandmed, käsud ja täpselt 35 olekurida.'

row_count=$(wc -l < "$rows" | tr -d ' ')
if [ "$row_count" -ne 35 ]; then
  printf 'sisemine viga: oodati 35 tõendirida, saadi %s\n' "$row_count" >&2
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
  printf '# Automaatkorrektori macOS v0.1 väljalasketõendid\n\n'
  printf '**Väljalaskeotsus:** %s\n\n' "$decision"
  printf 'Kõik 35 rida on kohustuslikud. FAIL või PENDING blokeerib väljalaske; punktisummat ega erandit pole.\n\n'
  printf '## Keskkond\n\n'
  printf -- '- Commit: `%s`\n' "$commit"
  printf -- '- Giti tööpuu: `%s`\n' "$tree_state"
  printf -- '- OS: `%s`\n' "$os_version"
  printf -- '- Xcode: `%s`\n' "$xcode_version"
  printf -- '- Safari %s\n' "$safari_version"
  printf -- '- Chrome %s\n' "$chrome_version"
  printf -- '- Tulemus: %s läbitud, %s ebaõnnestunud, %s ootel\n\n' "$passed_count" "$failed_count" "$pending_count"
  printf '## Käsud\n\n'
  printf '```text\n'
  printf '%s\n' 'swift format lint --recursive --strict Sources Tests Package.swift'
  printf '%s\n' 'git diff --check'
  printf '%s\n' 'git status --porcelain --untracked-files=normal'
  printf '%s\n' "python3 -m unittest discover -s Tests/ReleaseEvidenceTests -p 'test_*.py'"
  printf '%s\n' 'swift test'
  printf '%s\n' "xcodebuild -project apps/macos/Automaatkorrektor.xcodeproj -scheme Automaatkorrektor -configuration Debug -destination platform=macOS CODE_SIGNING_ALLOWED=NO build"
  printf '%s\n' "xcodebuild -project apps/macos/Automaatkorrektor.xcodeproj -scheme NativeAXEvidence -configuration Debug -destination platform=macOS CODE_SIGNING_ALLOWED=NO build"
  printf '```\n\n'
  printf '## Nõutavad tõendid\n\n'
  printf '| Olek | ID | Kontroll | Tõend |\n'
  printf '|---|---|---|---|\n'
  while IFS=$'\t' read -r status evidence_id title note; do
    printf '| %s | %s | %s | %s |\n' "$status" "$evidence_id" "$title" "$note"
  done < "$rows"
  printf '\n## Privaatsus\n\n'
  printf 'Raport ei sisalda teadlikult valitud teksti, päringukeha, vastusekeha ega privaatsusnäite väärtust. '\
  printf 'Privaatsusnäite väärtus kuulub ainult haldaja kontrolli ajal vaadeldavasse ühte stub-päringukehasse.\n'
} > "$report_path"

if grep -Eq 'AUTOMAATKORREKTOR-PRIVACY-CANARY-[[:alnum:]-]+' "$report_path"; then
  printf 'privaatsusviga: raport sisaldab privaatsusnäite väärtust\n' >&2
  exit 1
fi

printf 'Raport: %s\n' "$report_path"
printf 'Otsus: %s (%s läbitud, %s ebaõnnestunud, %s ootel)\n' \
  "$decision" "$passed_count" "$failed_count" "$pending_count"

if [ "$decision" = READY ]; then
  exit 0
fi
exit 2
