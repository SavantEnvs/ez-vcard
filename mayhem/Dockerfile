# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile — JVM target (Maven + Jazzer). Builds ON TOP of the org C/C++ base
# (clang builds the ELF launcher shims) and adds a pinned JDK 17 + Maven + Jazzer under
# /opt/toolchains, plus a $HOME-independent Maven local repository (/opt/toolchains/maven-repo)
# that the FIRST (online) mayhem/build.sh run populates and every later run resolves OFFLINE
# (SPEC §6.2 item 8 / §6.5). Every fetch is pinned by sha256.
#
# Build (from the repo root, on the `mayhem` branch):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       [--build-arg SOURCE_DATE_EPOCH=$(date +%s)] -t ez-vcard-commit:test .

FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); never an ENV — an empty value breaks clang.
ARG SOURCE_DATE_EPOCH
# Sanitizer override: undefaulted so the base ENV (ASan+UBSan, halting) flows through unless passed.
ARG SANITIZER_FLAGS
ARG MAYHEM_JOBS=

# ── JDK 17 + Maven + Jazzer @ FIXED, $HOME-independent prefixes (pinned by sha256) ─────────────
ARG JDK_URL=https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.16%2B8/OpenJDK17U-jdk_x64_linux_hotspot_17.0.16_8.tar.gz
ARG JDK_SHA256=166774efcf0f722f2ee18eba0039de2d685b350ee14d7b69e6f83437dafd2af1
ARG MAVEN_URL=https://archive.apache.org/dist/maven/maven-3/3.8.6/binaries/apache-maven-3.8.6-bin.tar.gz
ARG MAVEN_SHA256=c7047a48deb626abf26f71ab3643d296db9b1e67f1faa7d988637deac876b5a9
ARG JAZZER_URL=https://github.com/CodeIntelligenceTesting/jazzer/releases/download/v0.26.0/jazzer-linux-x86-64.tar.gz
ARG JAZZER_SHA256=816b29fe8796e12ac0c8194dc47d4c245a21df6b00376e7ab42120ec985e3a42

ENV JAVA_HOME=/opt/toolchains/jdk17 \
    MAVEN_HOME=/opt/toolchains/maven \
    JAZZER_HOME=/opt/toolchains/jazzer \
    MAVEN_REPO=/opt/toolchains/maven-repo \
    PATH=/opt/toolchains/jdk17/bin:/opt/toolchains/maven/bin:${PATH}

USER root
RUN install -d /opt/toolchains/jdk17 /opt/toolchains/maven /opt/toolchains/jazzer /opt/toolchains/maven-repo \
 && curl -fsSL "$JDK_URL" -o /tmp/jdk17.tgz \
 && echo "${JDK_SHA256}  /tmp/jdk17.tgz" | sha256sum -c - \
 && tar -xz --strip-components=1 -f /tmp/jdk17.tgz -C /opt/toolchains/jdk17 && rm -f /tmp/jdk17.tgz \
 && rm -rf /opt/toolchains/jdk17/jmods /opt/toolchains/jdk17/lib/src.zip \
 && curl -fsSL "$MAVEN_URL" -o /tmp/maven.tgz \
 && echo "${MAVEN_SHA256}  /tmp/maven.tgz" | sha256sum -c - \
 && tar -xz --strip-components=1 -f /tmp/maven.tgz -C /opt/toolchains/maven && rm -f /tmp/maven.tgz \
 && curl -fsSL "$JAZZER_URL" -o /tmp/jazzer.tgz \
 && echo "${JAZZER_SHA256}  /tmp/jazzer.tgz" | sha256sum -c - \
 && tar -xzf /tmp/jazzer.tgz -C /opt/toolchains/jazzer && rm -f /tmp/jazzer.tgz \
 && chown -R 2000:2000 /opt/toolchains/maven-repo

# Source enters from the build CONTEXT (the CI checkout): the FULL repo (incl. .git) lands in /mayhem.
USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# First (online) run: populates /opt/toolchains/maven-repo, builds the project, harness, launchers.
RUN bash mayhem/build.sh

# The project's functional oracle (JUnit suite + known-answer probe); a failing suite fails the image.
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
