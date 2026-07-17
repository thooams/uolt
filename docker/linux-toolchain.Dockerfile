# Prebuilt Linux x86_64 toolchain image for fast local build+test of UOLT.
# Build once (layers cache), then `scripts/linux-test.sh` reuses it so each run
# skips the apt-get step and completes in seconds.
#
# It also cross-builds and runs the aarch64 (arm64) port from this x86_64 host:
#   - lld: multi-target linker (the image's GNU ld is x86_64-only) used via
#     -fuse-ld=lld for aarch64 links.
#   - binutils-aarch64-linux-gnu: provides aarch64-linux-gnu-strip (the host
#     strip cannot process aarch64 ELF).
#   - qemu-user-static + binfmt-support: run the resulting aarch64 binaries
#     transparently (./uolt-x ... executes under qemu-aarch64). Registration of
#     the binfmt handler is documented in quickstart.md; invoking the emulator
#     explicitly (qemu-aarch64-static ./uolt-x) always works inside the container.
FROM ubuntu:24.04

RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends \
        clang lld binutils binutils-aarch64-linux-gnu \
        qemu-user-static binfmt-support \
        strace make coreutils hyperfine bsdextrautils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /w
