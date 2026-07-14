#!/bin/sh
# Differential test: uolt-env prints the same environment as the system env
# (compared sorted, since order is not guaranteed), under an identical process
# environment.
set -u
BIN=${UOLT_ENV:-${BUILD:-./build}/uolt-env}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/env; [ -x /bin/env ] && REF=/bin/env
fail=0

# Exclude "_" (the shell sets it to the path of the program being run, so it
# legitimately differs between the two binaries).
u=$(X1=a X2=b LONG_NAME="with spaces" "$BIN" 2>/dev/null | grep -v '^_=' | sort)
r=$(X1=a X2=b LONG_NAME="with spaces" "$REF" 2>/dev/null | grep -v '^_=' | sort)
[ "$u" = "$r" ] || { echo "FAIL diff: environment differs"; fail=1; }

# A minimal, fully-controlled environment (env -i clears it first).
u=$(env -i ONLY=one "$BIN" 2>/dev/null | grep -v '^_=' | sort)
r=$(env -i ONLY=one "$REF" 2>/dev/null | grep -v '^_=' | sort)
[ "$u" = "$r" ] || { echo "FAIL diff: cleared environment [$u] != [$r]"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS differential/env (ref: $REF)"
exit "$fail"
