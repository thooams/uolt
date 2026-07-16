#!/bin/sh
# Differential test for uolt-column: its stdout must match the system `column -t`
# byte-for-byte. `column` is util-linux on Linux (package bsdextrautils) and BSD
# on macOS; both agree on the -t table basics that uolt-column implements. SKIPs
# cleanly when no `column` is installed.
set -u
BIN=${UOLT_COLUMN:-${BUILD:-./build}/uolt-column}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac

REF=$(command -v column 2>/dev/null || true)
[ -n "$REF" ] || { echo "SKIP differential/column: no system 'column'"; exit 0; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

cmp_case() {
    label=$1; input=$2
    printf '%s' "$input" >"$tmp/in"
    "$BIN"      <"$tmp/in" >"$tmp/uo" 2>/dev/null
    "$REF" -t   <"$tmp/in" >"$tmp/ro" 2>/dev/null
    if ! cmp -s "$tmp/uo" "$tmp/ro"; then
        echo "FAIL differential: $label"
        printf 'uolt:\n%s\nref:\n%s\n' "$(cat "$tmp/uo")" "$(cat "$tmp/ro")" | sed 's/ /./g'
        fail=1
    fi
}

cmp_case "basic"        'name size date
foo 1024 jul16
bar 42 jul15
'
cmp_case "extra-spaces" '  x    y
z w
'
cmp_case "one-column"   'alpha
bb
c
'
cmp_case "tabs"         'a	bb	c
xxx	y	zz
'
# NB: only RECTANGULAR inputs (every line the same field count) are differential-
# tested, because that is where BSD and util-linux `column -t` agree. On ragged
# input they diverge: util-linux pads short lines with trailing blanks, BSD (and
# uolt-column) do not. Likewise multibyte width is locale-dependent - UTF-8-locale
# `column` and BSD count code points (matching uolt-column), util-linux under the
# C locale differs. Those two behaviors are pinned by the unit test's golden
# output instead. Generated grids below are rectangular by construction.
# NB: a final line WITHOUT a trailing newline is intentionally not compared here.
# BSD `column` drops it while util-linux renders it - a BSD/GNU divergence outside
# the agreed behavior. uolt-column renders it (see the unit test); only inputs
# with a trailing newline are differential-tested, where the two references agree.

# Random grids: same input to both, must agree.
i=0
while [ "$i" -lt 100 ]; do
    rows=$(( (i % 15) + 1 ))
    cols=$(( (i % 6) + 1 ))
    awk -v R="$rows" -v C="$cols" -v seed="$i" 'BEGIN{
        srand(seed);
        for (r=0; r<R; r++){
            line="";
            for (c=0; c<C; c++){
                n=int(rand()*7)+1; tok="";
                for (k=0; k<n; k++) tok=tok sprintf("%c", 97+int(rand()*26));
                line=(c==0)?tok:line" "tok;
            }
            print line;
        }
    }' >"$tmp/in"
    "$BIN"    <"$tmp/in" >"$tmp/uo" 2>/dev/null
    "$REF" -t <"$tmp/in" >"$tmp/ro" 2>/dev/null
    if ! cmp -s "$tmp/uo" "$tmp/ro"; then
        echo "FAIL differential: random grid at iter $i"
        printf 'uolt:\n%s\nref:\n%s\n' "$(cat "$tmp/uo")" "$(cat "$tmp/ro")" | sed 's/ /./g'
        fail=1; break
    fi
    i=$((i + 1))
done

[ "$fail" -eq 0 ] && echo "PASS differential/column"
exit "$fail"
