# Prebuilt Linux x86_64 toolchain image for fast local build+test of UOLT.
# Build once (layers cache), then `scripts/linux-test.sh` reuses it so each run
# skips the apt-get step and completes in seconds.
FROM ubuntu:24.04

RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends \
        clang binutils strace make coreutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /w
