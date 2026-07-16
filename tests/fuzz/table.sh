#!/bin/sh
# Fuzz test for uolt-table. There is no reference tool that renders this exact
# box-drawing format, so instead of a byte-for-byte differential this asserts two
# invariants under random input:
#
#   A. Robustness: arbitrary bytes (newlines, tabs, NULs, invalid UTF-8) must
#      never crash the tool - it exits 0 or 1, never via a signal (rc >= 128).
#      When it does print, the output must be a well-formed frame: it starts with
#      the top-left corner and ends with a newline.
#   B. Structure: for a randomly-shaped but well-formed grid of R rows x C columns
#      of simple tokens, the output is exactly R+2 lines (top border, R data rows,
#      bottom border), the first is a top border, the last a bottom border, and
#      every data row begins with a vertical bar.
set -u
BIN=${UOLT_TABLE:-${BUILD:-./build}/uolt-table}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
ITER=${UOLT_FUZZ_ITER:-200}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# The box-drawing bytes we assert on (UTF-8).
TL=$(printf '\342\224\214')   # ┌
BL=$(printf '\342\224\224')   # └
V=$(printf '\342\224\202')    # │

# ---- A. random-bytes robustness ----
i=0
while [ "$i" -lt "$ITER" ]; do
    sz=$(( (i * 53 + 7) % 4096 ))
    dd if=/dev/urandom of="$tmp/in" bs=1 count="$sz" 2>/dev/null
    "$BIN" <"$tmp/in" >"$tmp/out" 2>/dev/null; rc=$?
    if [ "$rc" -ge 128 ]; then
        echo "FAIL fuzz: crashed (rc=$rc) on random input at iter $i"; fail=1; break
    fi
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
        echo "FAIL fuzz: unexpected exit $rc at iter $i"; fail=1; break
    fi
    if [ "$rc" -eq 0 ] && [ -s "$tmp/out" ]; then
        first3=$(dd if="$tmp/out" bs=1 count=3 2>/dev/null)
        [ "$first3" = "$TL" ] || { echo "FAIL fuzz: output not a table at iter $i"; fail=1; break; }
        last=$(tail -c1 "$tmp/out"); [ -z "$last" ] || { echo "FAIL fuzz: no trailing newline at iter $i"; fail=1; break; }
    fi
    i=$((i + 1))
done

# ---- B. well-formed grid structure ----
i=0
while [ "$i" -lt "$ITER" ] && [ "$fail" -eq 0 ]; do
    rows=$(( (i % 20) + 1 ))
    cols=$(( (i % 8) + 1 ))
    awk -v R="$rows" -v C="$cols" -v seed="$i" 'BEGIN{
        srand(seed);
        for (r=0; r<R; r++){
            line="";
            for (c=0; c<C; c++){
                n=int(rand()*6)+1; tok="";
                for (k=0; k<n; k++) tok=tok sprintf("%c", 97+int(rand()*26));
                line=(c==0)?tok:line" "tok;
            }
            print line;
        }
    }' >"$tmp/grid"
    "$BIN" <"$tmp/grid" >"$tmp/out" 2>/dev/null; rc=$?
    [ "$rc" -eq 0 ] || { echo "FAIL fuzz: grid exit $rc at iter $i"; fail=1; break; }
    nlines=$(wc -l <"$tmp/out")
    exp=$(( rows + 2 ))
    [ "$nlines" -eq "$exp" ] || { echo "FAIL fuzz: $nlines lines, expected $exp at iter $i"; fail=1; break; }
    head -1 "$tmp/out" | grep -q "^$TL" || { echo "FAIL fuzz: bad top border at iter $i"; fail=1; break; }
    tail -1 "$tmp/out" | grep -q "^$BL" || { echo "FAIL fuzz: bad bottom border at iter $i"; fail=1; break; }
    # every data row (all but first and last line) starts with │
    body=$(sed -n "2,$((exp-1))p" "$tmp/out")
    if printf '%s\n' "$body" | grep -qv "^$V"; then
        echo "FAIL fuzz: a data row does not start with a bar at iter $i"; fail=1; break
    fi
    i=$((i + 1))
done

[ "$fail" -eq 0 ] && echo "PASS fuzz/table ($ITER iters)"
exit "$fail"
