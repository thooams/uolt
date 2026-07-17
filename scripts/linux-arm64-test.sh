#!/bin/sh
# Local Linux aarch64 (ARM64) cross build+test for UOLT, mirroring what CI runs
# but locally on an x86_64 host. Uses the prebuilt toolchain image (which carries
# lld, aarch64-linux-gnu-strip, and qemu-user-static) to cross-build every tool
# for arm64, then runs the full existing test suite with each tool executed under
# qemu.
#
# Why explicit qemu wrappers instead of binfmt: on a native Linux CI runner the
# registered binfmt handler executes aarch64 binaries reliably. On Docker Desktop
# for macOS (a nested VM) the binfmt qemu path segfaults intermittently (~0.5%),
# while invoking qemu-aarch64-static explicitly is 100% stable. So for a
# deterministic LOCAL oracle we point each script's per-tool UOLT_<TOOL> override
# at a one-line wrapper that execs qemu-aarch64-static <binary>. CI uses binfmt.
#
#   scripts/linux-arm64-test.sh              # build + full test suite
#   scripts/linux-arm64-test.sh true echo    # build all, run only these tools' tests
#
set -eu

IMAGE=uolt-linux-toolchain
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ONLY="$*"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "[arm64-test] building toolchain image (one-time) ..."
    docker build --platform linux/amd64 -t "$IMAGE" -f "$ROOT/docker/linux-toolchain.Dockerfile" "$ROOT"
fi

docker run --rm --platform linux/amd64 -v "$ROOT":/w -w /w -e BUILD=build-arm64 -e ONLY="$ONLY" "$IMAGE" sh -c '
    set -e
    make clean >/dev/null 2>&1 || true
    rm -rf build-arm64
    if [ -n "${ONLY:-}" ]; then
        # Build only the requested tools (the rest may not be ported yet).
        for t in $ONLY; do make ARCH=arm64 "build-arm64/uolt-$t" >/dev/null; done
    else
        make ARCH=arm64 >/dev/null
    fi

    # Generate one qemu launcher per built binary and export UOLT_<TOOL> so every
    # test script (BIN=${UOLT_<TOOL>:-...}) runs the aarch64 ELF under qemu.
    mkdir -p build-arm64/run
    for b in build-arm64/uolt-*; do
        name=$(basename "$b")
        [ "$name" = "run" ] && continue
        w="build-arm64/run/$name"
        printf "#!/bin/sh\nexec qemu-aarch64-static /w/%s \"\$@\"\n" "$b" > "$w"
        chmod +x "$w"
        tool=$(printf "%s" "${name#uolt-}" | tr "[:lower:]-" "[:upper:]_")
        export "UOLT_$tool=/w/$w"
    done
    export UOLT_TEST_ALIAS=/w/build-arm64/run/uolt-test

    # env is environment-exact: running it through the /bin/sh qemu wrapper would
    # leak the shell'\''s own PWD/SHLVL/_ into the child environment and fail its
    # differential test. Point it at the binary directly (binfmt/qemu-user), the
    # same path CI uses for every tool.
    export UOLT_ENV=/w/build-arm64/uolt-env

    echo "--- size (bytes, aarch64) ---"
    wc -c build-arm64/uolt-* 2>/dev/null | grep -v -e total -e "build-arm64/run"
    echo "--- linkage ---"
    aarch64-linux-gnu-readelf -d build-arm64/uolt-true 2>/dev/null | grep -q NEEDED && echo "DYNAMIC (unexpected)" || echo "static (no dynamic dependencies)"

    # Enumerate the test scripts ourselves (rather than `make test`) so we can
    # skip the trace layer under qemu: strace observes the qemu-user emulator, not
    # the guest, so its "no unexpected I/O / no heap" assertions are meaningless
    # here (research D8, T059). The no-heap guarantee stays structural (the link
    # script discards .bss; tools use stack/mmap only). Native runs would include
    # trace. We do not abort on a single failure so the full picture is reported.
    if [ -n "${ONLY:-}" ]; then
        SCRIPTS=""
        for t in $ONLY; do
            for f in tests/*/"$t".sh tests/*/"$t"_*.sh; do [ -f "$f" ] && SCRIPTS="$SCRIPTS $f"; done
        done
    else
        SCRIPTS=$(ls tests/*/*.sh)
    fi

    echo "--- tests ---"
    fails=0
    for f in $SCRIPTS; do
        case "$f" in
            tests/trace/*) echo "SKIP $(echo "$f" | sed "s#tests/##;s#\.sh##") (qemu-user: strace observes the emulator, not the guest)"; continue;;
        esac
        if ! sh "$f" >/tmp/tout 2>&1; then fails=$((fails + 1)); fi
        grep -E "PASS|FAIL|SKIP" /tmp/tout || cat /tmp/tout
    done
    echo "--- $fails failing script(s) ---"
    [ "$fails" -eq 0 ]
'
