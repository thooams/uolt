#!/bin/sh
# Fuzz test: random text (letters, digits, spaces, tabs, newlines) must never
# crash uolt-wc; its counts must match the reference wc (LC_ALL=C, byte-based)
# after whitespace normalization, and the exit code must agree.
set -u
BIN=${UOLT_WC:-${BUILD:-./build}/uolt-wc}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/wc; [ -x /bin/wc ] && REF=/bin/wc
ITER=${UOLT_FUZZ_ITER:-200}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
norm() { tr -s ' ' | sed 's/^ *//;s/ *$//'; }

i=0
while [ "$i" -lt "$ITER" ]; do
    # Random size, alphabet includes the blanks wc splits on.
    sz=$(( (i * 53) % 4096 ))
    LC_ALL=C tr -dc 'abcXYZ012 \t\n' </dev/urandom \
        | dd bs=1 count="$sz" 2>/dev/null >"$tmp/f"

    # Cycle through the option variants.
    case $(( i % 4 )) in
        0) opt= ;;
        1) opt=-l ;;
        2) opt=-w ;;
        3) opt=-c ;;
    esac

    u=$("$BIN" $opt "$tmp/f" 2>/dev/null | norm);         urc=$?
    s=$(LC_ALL=C "$REF" $opt "$tmp/f" 2>/dev/null | norm); src=$?
    if [ "$urc" -ne "$src" ] || [ "$u" != "$s" ]; then
        echo "FAIL fuzz: iter $i opt='$opt' [$u] != [$s] (exit $urc/$src)"; fail=1; break
    fi
    i=$((i + 1))
done

[ "$fail" -eq 0 ] && echo "PASS fuzz/wc ($ITER iters)"
exit "$fail"
