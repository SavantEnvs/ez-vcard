/*
 * mayhem/jazzer_launcher.c — the ELF Mayhem runs for the `fuzz-vcard` target.
 *
 * Mayhem needs an ELF `cmd:`; Jazzer's native driver is one but it needs JAVA_HOME (it dlopen()s
 * libjvm.so from there) and a long classpath. This shim pins both at build time and execv()s the
 * driver, forwarding every libFuzzer flag Mayhem passes (-runs=, -max_total_time=, corpus dirs,
 * ...), so the target behaves exactly like a libFuzzer binary (`libfuzzer: true`).
 *
 * LAUNCHER_MODE 0 = fuzz target (/mayhem/fuzz-vcard)
 * LAUNCHER_MODE 2 = standalone reproducer (/mayhem/fuzz-vcard-standalone): prepends -runs=1 so
 *                   `fuzz-vcard-standalone <input>` executes the input once and exits.
 * No file I/O of its own; scratch (crash artifacts, JVM perf data) goes to cwd / $TMPDIR.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef JAZZER_DRIVER
#define JAZZER_DRIVER "/opt/toolchains/jazzer/jazzer"
#endif
#ifndef JAVA_HOME_DIR
#define JAVA_HOME_DIR "/opt/toolchains/jdk17"
#endif
#ifndef FUZZ_CP
#error "FUZZ_CP (the harness classpath) must be defined at compile time"
#endif
#ifndef FUZZ_TARGET
#define FUZZ_TARGET "VCardFuzz"
#endif
#ifndef LAUNCHER_MODE
#define LAUNCHER_MODE 0
#endif

static void set_jvm_env(void) {
    setenv("JAVA_HOME", JAVA_HOME_DIR, 1);
    const char *cur = getenv("LD_LIBRARY_PATH");
    char buf[8192];
    if (cur && *cur)
        snprintf(buf, sizeof(buf), "%s/lib/server:%s/lib:%s", JAVA_HOME_DIR, JAVA_HOME_DIR, cur);
    else
        snprintf(buf, sizeof(buf), "%s/lib/server:%s/lib", JAVA_HOME_DIR, JAVA_HOME_DIR);
    setenv("LD_LIBRARY_PATH", buf, 1);
}

int main(int argc, char **argv) {
    set_jvm_env();
    char **a = (char **)calloc((size_t)argc + 8, sizeof(char *));
    if (!a) { perror("calloc"); return 1; }
    int n = 0;
    a[n++] = (char *)JAZZER_DRIVER;
    a[n++] = (char *)"--cp=" FUZZ_CP;
    a[n++] = (char *)"--target_class=" FUZZ_TARGET;
    /* Only the harness + ez-vcard + its runtime deps get coverage instrumentation (the JDK never does). */
    a[n++] = (char *)"--instrumentation_includes=ezvcard.**:com.github.mangstadt.vinnie.**:VCardFuzz";
    a[n++] = (char *)"--jvm_args=-Xmx2048m:-Xss1024k:-XX\\:-UsePerfData";
#if LAUNCHER_MODE == 2
    a[n++] = (char *)"-runs=1";
#endif
    for (int i = 1; i < argc; i++) a[n++] = argv[i];
    a[n] = NULL;
    execv(JAZZER_DRIVER, a);
    perror("execv " JAZZER_DRIVER);
    return 127;
}
