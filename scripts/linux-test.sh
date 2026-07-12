#!/bin/sh
# Fast local Linux x86_64 build+test for UOLT, using a prebuilt toolchain image
# (see docker/linux-toolchain.Dockerfile) in a container. Requires a running
# Docker engine (e.g. colima). Mirrors what CI runs, but locally and for free.
#
#   scripts/linux-test.sh          # build + full test suite + size report
#
set -eu

IMAGE=uolt-linux-toolchain
ROOT=$(cd "$(dirname "$0")/.." && pwd)

# Build the toolchain image if missing (cached after the first time).
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "[linux-test] building toolchain image (one-time) ..."
    docker build --platform linux/amd64 -t "$IMAGE" -f "$ROOT/docker/linux-toolchain.Dockerfile" "$ROOT"
fi

docker run --rm --platform linux/amd64 -v "$ROOT":/w -w /w "$IMAGE" sh -c '
    set -e
    make clean >/dev/null
    make >/dev/null
    echo "--- size (bytes) ---"
    wc -c build/uolt-* | grep -v total
    echo "--- linkage ---"
    ldd build/uolt-true 2>/dev/null || echo "static (not a dynamic executable)"
    echo "--- tests ---"
    make test 2>&1 | grep -E "PASS|FAIL|SKIP"
'
