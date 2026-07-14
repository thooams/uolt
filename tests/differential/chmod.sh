#!/bin/sh
# Differential test: uolt-chmod agrees with the system chmod on the resulting
# permission bits and exit status, for octal modes.
set -u
BIN=${UOLT_CHMOD:-${BUILD:-./build}/uolt-chmod}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/bin/chmod; [ -x /usr/bin/chmod ] && REF=/usr/bin/chmod
fail=0
perm() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

compare() {
    mode=$1
    ua=$(mktemp -d); ra=$(mktemp -d)
    touch "$ua/f" "$ra/f"
    "$BIN" "$mode" "$ua/f" >/dev/null 2>&1; urc=$?
    "$REF" "$mode" "$ra/f" >/dev/null 2>&1; rrc=$?
    [ "$urc" -eq "$rrc" ] || { echo "FAIL diff [$mode]: exit $urc vs ref $rrc"; fail=1; }
    [ "$(perm "$ua/f")" = "$(perm "$ra/f")" ] || { echo "FAIL diff [$mode]: perm $(perm "$ua/f") vs $(perm "$ra/f")"; fail=1; }
    rm -rf "$ua" "$ra"
}

for m in 644 755 600 640 444 700 0755 0644 4755 2755 1777; do
    compare "$m"
done

# Symbolic modes: seed a known octal, then apply the symbolic op with each tool.
symcompare() {
    seed=$1; sym=$2
    ua=$(mktemp -d); ra=$(mktemp -d)
    touch "$ua/f" "$ra/f"; chmod "$seed" "$ua/f" "$ra/f"
    "$BIN" "$sym" "$ua/f" >/dev/null 2>&1; urc=$?
    "$REF" "$sym" "$ra/f" >/dev/null 2>&1; rrc=$?
    [ "$urc" -eq "$rrc" ] || { echo "FAIL diff sym [$seed $sym]: exit $urc vs $rrc"; fail=1; }
    [ "$(perm "$ua/f")" = "$(perm "$ra/f")" ] || { echo "FAIL diff sym [$seed $sym]: $(perm "$ua/f") vs $(perm "$ra/f")"; fail=1; }
    rm -rf "$ua" "$ra"
}
for seed in 644 600 755 640 444; do
    for sym in u+x go-w a=r +w u-w g+rw o-rwx ugo+r a+x u+x,g-w a-x; do
        symcompare "$seed" "$sym"
    done
done
# X on a directory
ua=$(mktemp -d); ra=$(mktemp -d); mkdir "$ua/d" "$ra/d"; chmod 644 "$ua/d" "$ra/d"
"$BIN" a+X "$ua/d" >/dev/null 2>&1; "$REF" a+X "$ra/d" >/dev/null 2>&1
[ "$(perm "$ua/d")" = "$(perm "$ra/d")" ] || { echo "FAIL diff sym [dir a+X]"; fail=1; }
rm -rf "$ua" "$ra"

# Missing file: both error.
"$BIN" 644 /nonexistent/xyz >/dev/null 2>&1; urc=$?
"$REF" 644 /nonexistent/xyz >/dev/null 2>&1; rrc=$?
[ "$urc" -eq "$rrc" ] || { echo "FAIL diff [missing]: exit $urc vs $rrc"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS differential/chmod (ref: $REF)"
exit "$fail"
