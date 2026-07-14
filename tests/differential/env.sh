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

# Running a command: the child sees the same (sorted, minus "_") environment.
u=$(env -i A=1 B=2 "$BIN" "$BIN" 2>/dev/null | grep -v '^_=' | sort)
r=$(env -i A=1 B=2 "$REF" "$REF" 2>/dev/null | grep -v '^_=' | sort)
[ "$u" = "$r" ] || { echo "FAIL diff: child env [$u] != [$r]"; fail=1; }

# -u removes a variable from the child's environment.
u=$(env -i KEEP=1 DROP=2 "$BIN" -u DROP "$BIN" 2>/dev/null | grep -v '^_=' | sort)
r=$(env -i KEEP=1 DROP=2 "$REF" -u DROP "$REF" 2>/dev/null | grep -v '^_=' | sort)
[ "$u" = "$r" ] || { echo "FAIL diff: -u child [$u] != [$r]"; fail=1; }

# Assignment overrides an inherited value.
u=$(env -i V=old "$BIN" V=new "$BIN" 2>/dev/null | grep '^V=' | sort)
r=$(env -i V=old "$REF" V=new "$REF" 2>/dev/null | grep '^V=' | sort)
[ "$u" = "$r" ] || { echo "FAIL diff: override [$u] != [$r]"; fail=1; }

# Command output and exit status match the system env.
[ "$("$BIN" echo hi)" = "$("$REF" echo hi)" ] || { echo "FAIL diff: run echo"; fail=1; }
"$BIN" false; urc=$?; "$REF" false; rrc=$?
[ "$urc" -eq "$rrc" ] || { echo "FAIL diff: exit status $urc vs $rrc"; fail=1; }
"$BIN" no_such_cmd_zzz >/dev/null 2>&1; urc=$?
"$REF" no_such_cmd_zzz >/dev/null 2>&1; rrc=$?
[ "$urc" -eq "$rrc" ] || { echo "FAIL diff: not-found exit $urc vs $rrc"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS differential/env (ref: $REF)"
exit "$fail"
