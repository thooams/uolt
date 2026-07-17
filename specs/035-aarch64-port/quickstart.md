# Quickstart: Build & Test the aarch64 Port

## Native aarch64 Linux host (RPi, Graviton, ARM VM)

```sh
make                 # ARCH auto-detected as arm64 from uname -m; builds ./build/uolt-*
make test            # full suite (unit/POSIX/differential/fuzz/trace) against system tools
file build/uolt-echo # -> ELF 64-bit LSB executable, ARM aarch64, statically linked
ldd  build/uolt-echo # -> "not a dynamic executable"
```

Expect: same behavior as x86_64, byte-for-byte differential parity, fully static, sized within the
per-arch discipline (exact bytes differ from x86_64 by encoding).

## Cross-build on an x86_64 host (what CI does, via qemu-user)

```sh
# One-time: register binfmt so aarch64 binaries run transparently under qemu
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

# Build + test inside the arm64 container image (Dockerfile gains qemu-user-static)
docker buildx build --platform linux/arm64 -t uolt-arm64 -f docker/linux-toolchain.Dockerfile .
docker run --rm --platform linux/arm64 -v "$PWD":/w -w /w uolt-arm64 sh -c 'make && make test'
```

Or explicit cross-compile without a container (clang is a cross-compiler):

```sh
make ARCH=arm64      # forces the arm64 source dirs + -target aarch64-linux-gnu
qemu-aarch64-static build/uolt-echo hello   # run one binary under emulation
```

## Thin-slice acceptance (Phase B gate, SC-006)

```sh
make ARCH=arm64
for t in true false echo; do
  qemu-aarch64-static build/uolt-$t; echo "exit=$?"
done
# echo parity:
diff <(qemu-aarch64-static build/uolt-echo -n a b c) <(printf '%s' 'a b c')
```

## Verifying no regression on x86_64 (SC-005)

```sh
make ARCH=x86_64 && make test     # existing x86_64 suite stays green after the migration
```

## Trace-layer note under qemu

`strace` under `qemu-user` does not faithfully trace the emulated guest. Run the Principle XI
syscall-trace assertion (no `brk`, only expected calls) on a native aarch64 host when available;
under qemu it is environment-skipped with a recorded reason (mirrors the macOS dtruss-under-SIP
skip). The no-heap guarantee is also enforced structurally (`.bss` discarded, mmap-only).
