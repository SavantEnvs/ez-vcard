/*
 * mayhem/java_launcher.c — ELF shim that runs one Java main class on a build-time-pinned classpath.
 *
 * Compiled twice by mayhem/build.sh:
 *   /mayhem/ez-vcard-tests  MAIN_CLASS=JUnitSuiteRunner  — the upstream JUnit 4 suite (test.sh oracle)
 *   /mayhem/ez-vcard-probe  MAIN_CLASS=VCardProbe        — the known-answer probe (test.sh oracle)
 * test.sh drives these ELFs (never `java` directly) so the oracle path is a project binary under
 * /mayhem: neutering it (exit 0, no output) makes every assertion in test.sh fail.
 * Forwards argv[1..] to the Java main. The --add-opens set is what the JDK 17 run of the suite needs
 * for mockito-all 1.10.19 (cglib) / equalsverifier 1.7.6 reflection.
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#ifndef JAVA_BIN
#define JAVA_BIN "/opt/toolchains/jdk17/bin/java"
#endif
#ifndef CLASSPATH
#error "CLASSPATH must be defined at compile time"
#endif
#ifndef MAIN_CLASS
#error "MAIN_CLASS must be defined at compile time"
#endif

int main(int argc, char **argv) {
    char **a = (char **)calloc((size_t)argc + 24, sizeof(char *));
    if (!a) { perror("calloc"); return 1; }
    int n = 0;
    a[n++] = (char *)JAVA_BIN;
    a[n++] = (char *)"-Xmx1024m";
    a[n++] = (char *)"-XX:-UsePerfData";
    a[n++] = (char *)"-Dfile.encoding=UTF-8";
    a[n++] = (char *)"-Duser.timezone=UTC";
    a[n++] = (char *)"--add-opens"; a[n++] = (char *)"java.base/java.lang=ALL-UNNAMED";
    a[n++] = (char *)"--add-opens"; a[n++] = (char *)"java.base/java.lang.reflect=ALL-UNNAMED";
    a[n++] = (char *)"--add-opens"; a[n++] = (char *)"java.base/java.util=ALL-UNNAMED";
    a[n++] = (char *)"--add-opens"; a[n++] = (char *)"java.base/java.io=ALL-UNNAMED";
    a[n++] = (char *)"--add-opens"; a[n++] = (char *)"java.base/java.net=ALL-UNNAMED";
    a[n++] = (char *)"--add-opens"; a[n++] = (char *)"java.base/java.text=ALL-UNNAMED";
    a[n++] = (char *)"--add-opens"; a[n++] = (char *)"java.base/java.time=ALL-UNNAMED";
    a[n++] = (char *)"-cp"; a[n++] = (char *)CLASSPATH;
    a[n++] = (char *)MAIN_CLASS;
    for (int i = 1; i < argc; i++) a[n++] = argv[i];
    a[n] = NULL;
    execv(JAVA_BIN, a);
    perror("execv " JAVA_BIN);
    return 127;
}
