#!/usr/bin/env bash
#
# mayhem/test.sh — RUN ez-vcard's functional oracle (everything was built by mayhem/build.sh; nothing
# is compiled here and Maven is never invoked, so this runs air-gapped).
#
# Two legs, both through project ELFs under /mayhem (so neutering the program makes them fail):
#  1. /mayhem/ez-vcard-tests  — the upstream JUnit 4 suite (Surefire's selection of
#     src/test/java, ~1000 assertion-based tests) run by JUnitSuiteRunner; its
#     `JUNIT classes=C tests=N failures=F ignored=I` summary line is parsed for the counts.
#     A missing summary (runner died / neutered / printed nothing) is a failure, never a pass.
#  2. /mayhem/ez-vcard-probe  — known-answer probe: parse ONE fixed vCard (RFC 6350's example, a
#     committed seed) and compare every printed field, plus text/jCard/xCard/hCard round-trip
#     read-backs, against exact expected values. Each comparison is one CTRF test; every probe is
#     unconditional (a missing binary or fixture fails it).
# Emits the CTRF summary (emit_ctrf) and exits non-zero iff failed > 0.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
SRC="${SRC:-/mayhem}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

PASS=0; FAIL=0; SKIP=0
TOOL="junit4+kat-probe"

# ---- leg 1: the upstream JUnit 4 suite --------------------------------------------------------
if [ ! -x /mayhem/ez-vcard-tests ]; then
  echo "FATAL: /mayhem/ez-vcard-tests missing — mayhem/build.sh must build it" >&2
  emit_ctrf "$TOOL" 0 1 0; exit 1
fi
if [ ! -d "$SRC/target/test-classes/ezvcard" ]; then
  echo "FATAL: target/test-classes missing — mayhem/build.sh must compile the upstream suite" >&2
  emit_ctrf "$TOOL" 0 1 0; exit 1
fi
echo "=== JUnit 4 suite via /mayhem/ez-vcard-tests ==="
jlog="$(mktemp "${TMPDIR:-/tmp}/ezvcard-junit.XXXXXX")"
/mayhem/ez-vcard-tests "$SRC/target/test-classes" >"$jlog" 2>&1; jrc=$?
grep -E '^(FAILURE:|JUNIT |OK \(|Tests run:|Time:)' "$jlog" | head -60
summary="$(grep -m1 -E '^JUNIT classes=[0-9]+ tests=[0-9]+ failures=[0-9]+ ignored=[0-9]+$' "$jlog" || true)"
if [ -z "$summary" ]; then
  echo "JUnit suite produced NO summary line (rc=$jrc) — runner died or was neutered; counting as a failure" >&2
  tail -20 "$jlog" >&2
  FAIL=$(( FAIL + 1 ))
else
  jc="$(sed -E 's/.* classes=([0-9]+).*/\1/'  <<<"$summary")"
  jt="$(sed -E 's/.* tests=([0-9]+).*/\1/'    <<<"$summary")"
  jf="$(sed -E 's/.* failures=([0-9]+).*/\1/' <<<"$summary")"
  ji="$(sed -E 's/.* ignored=([0-9]+).*/\1/'  <<<"$summary")"
  echo "junit: classes=$jc tests=$jt failures=$jf ignored=$ji (rc=$jrc)"
  # A suite that "ran" a handful of tests is a broken classpath/discovery, not a pass: ez-vcard has
  # ~96 test classes / ~1000 tests (Surefire reports the same count). Also treat a non-zero rc with
  # 0 recorded failures as a failure.
  if [ "$jt" -lt 500 ] || [ "$jc" -lt 60 ]; then echo "suite far too small ($jc classes / $jt tests) — discovery/classpath broken" >&2; jf=$(( jf + 1 )); fi
  if [ "$jrc" -ne 0 ] && [ "$jf" -eq 0 ]; then jf=1; fi
  PASS=$(( PASS + jt - jf )); FAIL=$(( FAIL + jf )); SKIP=$(( SKIP + ji ))
fi
rm -f "$jlog"

# ---- leg 2: known-answer probe over RFC 6350's example vCard -------------------------------------
FIXTURE="$SRC/mayhem/fuzz-vcard/testsuite/rfc6350-example.vcf"
echo "=== known-answer probe via /mayhem/ez-vcard-probe on $FIXTURE ==="
plog="$(mktemp "${TMPDIR:-/tmp}/ezvcard-probe.XXXXXX")"
if [ -x /mayhem/ez-vcard-probe ]; then
  /mayhem/ez-vcard-probe "$FIXTURE" >"$plog" 2>&1; prc=$?
else
  echo "FATAL: /mayhem/ez-vcard-probe missing" >&2; prc=127
fi
echo "probe rc=$prc"; sed 's/^/  | /' "$plog" | head -40
expect() {   # expect <KEY> <exact expected value>
  local key="$1" want="$2" got
  got="$(sed -n "s/^${key}=//p" "$plog" | head -1)"
  if [ "$got" = "$want" ]; then PASS=$(( PASS + 1 ))
  else FAIL=$(( FAIL + 1 )); echo "KAT FAIL $key: want [$want] got [$got]" >&2; fi
}
expect COUNT            "1"
expect VERSION          "4.0"
expect FN               "Simon Perreault"
expect N_FAMILY         "Perreault"
expect N_GIVEN          "Simon"
expect N_SUFFIXES       "ing. jr|M.Sc."
expect EMAIL            "simon.perreault@viagenie.ca"
expect EMAIL_TYPES      "[work]"
expect TEL_COUNT        "2"
expect TEL_URI          "tel:+1-418-656-9254;ext=102"
expect ORG              "Viagenie"
expect GEO              "46.772673,-71.282945"
expect LANG_COUNT       "2"
expect URL              "http://nomis80.org"
expect ADR_LOCALITY     "Quebec"
expect ADR_POSTAL       "G1V 2M2"
expect BDAY             "--02-03"
expect VALIDATION_EMPTY "true"
expect RT_V3_VERSION    "3.0"
expect RT_V3_FN         "Simon Perreault"
expect RT_V3_TEL_COUNT  "2"
expect RT_JSON_STARTS   '["vcard",'
expect RT_JSON_EMAIL    "simon.perreault@viagenie.ca"
expect RT_JSON_ORG      "Viagenie"
expect RT_XML_FN        "Simon Perreault"
expect RT_XML_N_FAMILY  "Perreault"
expect RT_HTML_FN       "Simon Perreault"
expect RT_HTML_EMAIL    "simon.perreault@viagenie.ca"
[ "$prc" -eq 0 ] || { echo "probe exited $prc" >&2; FAIL=$(( FAIL + 1 )); }
rm -f "$plog"

emit_ctrf "$TOOL" "$PASS" "$FAIL" "$SKIP"
