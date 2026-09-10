#!/usr/bin/env bash
#
# mayhem/build.sh — build ez-vcard (Maven) + the Jazzer `fuzz-vcard` harness + the oracle inputs.
#
# Produces (all under /mayhem):
#   /mayhem/fuzz-vcard             ELF launcher -> Jazzer driver over VCardFuzz    (the Mayhem target)
#   /mayhem/fuzz-vcard-standalone  same launcher, prepends -runs=1: one-shot reproducer for one input
#   /mayhem/ez-vcard-tests         ELF launcher -> JUnitSuiteRunner (the upstream JUnit 4 suite)
#   /mayhem/ez-vcard-probe         ELF launcher -> VCardProbe (known-answer probe)
#   mayhem-build/{ezvcard.jar,lib/,testlib/,harness/,probe/,runner/}   the JVM classpaths
# plus the project's own Maven outputs in target/ (classes, test-classes, the bundle jar).
#
# The fuzzed code is JVM bytecode: Jazzer instruments it for coverage and turns any uncaught
# exception into a finding, so $SANITIZER_FLAGS/$DEBUG_FLAGS only reach the four ELF launcher shims
# built here (they still honour the contract: DWARF <= 3, LSan off via lsan_off.cc, and an explicit
# empty SANITIZER_FLAGS gives a clean, sanitizer-free build).
#
# AIR-GAPPED CONTRACT (SPEC §6.5): Maven's local repository is pinned to $MAVEN_REPO
# (/opt/toolchains/maven-repo, $HOME-independent). The FIRST build (online, during the image build)
# populates it and then drops the marker $MAVEN_REPO/.mayhem-warm; every later run sees the marker and
# forces `mvn -o`, so the PATCH-tier re-run never touches the network (a missing artifact fails loudly
# instead of silently fetching). test.sh never invokes Maven at all.
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${CC:=clang}" ; : "${CXX:=clang++}"
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"       # DWARF <= 3 on every ELF (SPEC §6.2 item 10)
: "${MAYHEM_JOBS:=$(nproc)}"
export CC CXX SANITIZER_FLAGS DEBUG_FLAGS MAYHEM_JOBS
echo "SANITIZER_FLAGS=${SANITIZER_FLAGS} (JVM target: applied to the ELF launcher shims)"

SRC="${SRC:-/mayhem}"
OUT=/mayhem
JAVA_HOME="${JAVA_HOME:-/opt/toolchains/jdk17}"
MAVEN_HOME="${MAVEN_HOME:-/opt/toolchains/maven}"
JAZZER_HOME="${JAZZER_HOME:-/opt/toolchains/jazzer}"
MAVEN_REPO="${MAVEN_REPO:-/opt/toolchains/maven-repo}"
export JAVA_HOME PATH="$JAVA_HOME/bin:$MAVEN_HOME/bin:$PATH"
BUILD="$SRC/mayhem-build"

cd "$SRC"
mkdir -p "$BUILD" "$MAVEN_REPO"
java -version 2>&1 | head -1

WARM="$MAVEN_REPO/.mayhem-warm"
MVN=(mvn -B --no-transfer-progress -Dmaven.repo.local="$MAVEN_REPO"
     -Dgpg.skip=true -Dmaven.javadoc.skip=true -Dmaven.source.skip=true -Djacoco.skip=true
     -Danimal.sniffer.skip=true)
if [ -f "$WARM" ]; then
  echo "=== Maven repository is warm ($WARM) — building OFFLINE (mvn -o) ==="
  MVN+=(-o)
else
  echo "=== first build: populating $MAVEN_REPO online ==="
fi

echo "=== mvn package (project + test classes, upstream's normal javac flags; tests are RUN by test.sh) ==="
"${MVN[@]}" -DskipTests package

jar="$(find "$SRC/target" -maxdepth 1 -name 'ez-vcard-*.jar' ! -name '*-javadoc.jar' ! -name '*-sources.jar' -print -quit)"
[ -n "$jar" ] || { echo "missing ez-vcard-*.jar under $SRC/target" >&2; exit 1; }
[ -d "$SRC/target/classes/ezvcard" ] || { echo "missing target/classes" >&2; exit 1; }
[ -d "$SRC/target/test-classes/ezvcard" ] || { echo "missing target/test-classes (upstream suite not compiled)" >&2; exit 1; }
cp -f "$jar" "$BUILD/ezvcard.jar"

echo "=== runtime dependency jars (compile scope, copied by the pom's own copy-dependencies execution) ==="
rm -rf "$BUILD/lib"; mkdir -p "$BUILD/lib"
cp -f "$SRC"/target/dependency/*.jar "$BUILD/lib/"
LIB_CP="$(find "$BUILD/lib" -name '*.jar' | sort | paste -sd: -)"
[ -n "$LIB_CP" ] || { echo "no runtime dependency jars in target/dependency" >&2; exit 1; }

echo "=== test-scope dependency jars (junit, mockito, xmlunit, ...) for the oracle ==="
rm -rf "$BUILD/testlib"
"${MVN[@]}" dependency:copy-dependencies -DincludeScope=test -DoutputDirectory="$BUILD/testlib"
TESTLIB_CP="$(find "$BUILD/testlib" -name '*.jar' | sort | paste -sd: -)"
[ -n "$TESTLIB_CP" ] || { echo "no test dependency jars copied" >&2; exit 1; }

echo "=== javac: Jazzer harness, JUnit suite runner, known-answer probe ==="
rm -rf "$BUILD/harness" "$BUILD/runner" "$BUILD/probe"
mkdir -p "$BUILD/harness" "$BUILD/runner" "$BUILD/probe"
javac -encoding UTF-8 -nowarn -cp "$BUILD/ezvcard.jar:$LIB_CP" -d "$BUILD/harness" mayhem/VCardFuzz.java
javac -encoding UTF-8 -nowarn -cp "$BUILD/ezvcard.jar:$LIB_CP" -d "$BUILD/probe"   mayhem/VCardProbe.java
javac -encoding UTF-8 -nowarn -cp "$TESTLIB_CP"                -d "$BUILD/runner"  mayhem/JUnitSuiteRunner.java

FUZZ_CP="$BUILD/ezvcard.jar:$LIB_CP:$BUILD/harness"
PROBE_CP="$BUILD/ezvcard.jar:$LIB_CP:$BUILD/probe"
# The suite runs against target/classes + target/test-classes exactly as Surefire would.
TESTS_CP="$SRC/target/test-classes:$SRC/target/classes:$TESTLIB_CP:$BUILD/runner"

echo "=== ELF launchers ($CXX $SANITIZER_FLAGS $DEBUG_FLAGS) ==="
# Build-time LSan off-switch, linked into every sanitizer-built ELF (fleet policy; never a runtime option).
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$BUILD/lsan_off.o"

compile_jazzer_launcher() {   # <out> <mode>
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -c mayhem/jazzer_launcher.c -o "$BUILD/$1.o" \
    -DJAZZER_DRIVER="\"$JAZZER_HOME/jazzer\"" -DJAVA_HOME_DIR="\"$JAVA_HOME\"" \
    -DFUZZ_CP="\"$FUZZ_CP\"" -DFUZZ_TARGET="\"VCardFuzz\"" -DLAUNCHER_MODE="$2"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -o "$OUT/$1" "$BUILD/$1.o" "$BUILD/lsan_off.o"
}
compile_java_launcher() {     # <out> <main class> <classpath>
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -c mayhem/java_launcher.c -o "$BUILD/$1.o" \
    -DJAVA_BIN="\"$JAVA_HOME/bin/java\"" -DMAIN_CLASS="\"$2\"" -DCLASSPATH="\"$3\""
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -o "$OUT/$1" "$BUILD/$1.o" "$BUILD/lsan_off.o"
}
compile_jazzer_launcher fuzz-vcard            0
compile_jazzer_launcher fuzz-vcard-standalone 2
compile_java_launcher   ez-vcard-tests JUnitSuiteRunner "$TESTS_CP"
compile_java_launcher   ez-vcard-probe VCardProbe       "$PROBE_CP"

for b in fuzz-vcard fuzz-vcard-standalone ez-vcard-tests ez-vcard-probe; do
  [ -x "$OUT/$b" ] || { echo "missing $OUT/$b" >&2; exit 1; }
done
[ -x "$JAZZER_HOME/jazzer" ] || { echo "missing Jazzer driver $JAZZER_HOME/jazzer" >&2; exit 1; }

touch "$WARM"
echo "build.sh complete: $OUT/fuzz-vcard $OUT/fuzz-vcard-standalone $OUT/ez-vcard-tests $OUT/ez-vcard-probe"
