#!/bin/sh
# Differential test: uolt-uniq matches the system uniq. -c is compared with
# whitespace normalized (the count field width is implementation-defined).
set -u
BIN=${UOLT_UNIQ:-${BUILD:-./build}/uolt-uniq}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/uniq; [ -x /bin/uniq ] && REF=/bin/uniq
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
norm() { tr -s ' ' | sed 's/^ *//;s/ *$//'; }

printf 'a\na\nb\nc\nc\nc\nb\nb\nd\na\n' >"$tmp/in"

compare() {
    desc=$1; shift
    u=$("$BIN" "$@" <"$tmp/in" 2>/dev/null | norm)
    r=$("$REF" "$@" <"$tmp/in" 2>/dev/null | norm)
    [ "$u" = "$r" ] || { echo "FAIL diff [$desc]: [$u] != [$r]"; fail=1; }
}

printf 'A\na\nB\nb\nb\nC\na\nA\n' >"$tmp/ci"
compare "default"
compare "-c"       -c
compare "-d"       -d
compare "-u"       -u
compare "-i"       -i
compare "-ic"      -ic
compare "-id"      -id
# -i against a mixed-case file
u=$("$BIN" -i "$tmp/ci" | norm); r=$("$REF" -i "$tmp/ci" | norm)
[ "$u" = "$r" ] || { echo "FAIL diff [-i mixed]: [$u] != [$r]"; fail=1; }

# -f (skip fields) and -s (skip chars) against structured input.
printf '1 apple\n2 apple\n3 grape\n4 grape\n5 apple\n' >"$tmp/fld"
printf 'xxred\nyyred\nzzblue\nqqblue\nwwred\n' >"$tmp/chr"
comparef() {
    desc=$1; file=$2; shift 2
    u=$("$BIN" "$@" <"$file" 2>/dev/null | norm)
    r=$("$REF" "$@" <"$file" 2>/dev/null | norm)
    [ "$u" = "$r" ] || { echo "FAIL diff [$desc]: [$u] != [$r]"; fail=1; }
}
comparef "-f1"      "$tmp/fld" -f1
comparef "-f 1"     "$tmp/fld" -f 1
comparef "-c -f1"   "$tmp/fld" -c -f1
comparef "-d -f1"   "$tmp/fld" -d -f1
comparef "-u -f1"   "$tmp/fld" -u -f1
comparef "-s2"      "$tmp/chr" -s2
comparef "-s 2"     "$tmp/chr" -s 2
comparef "-c -s2"   "$tmp/chr" -c -s2
printf '  a x\n  a y\nb x\n' >"$tmp/blk"
comparef "-f1 blanks" "$tmp/blk" -f1

# Fuzz over random adjacent-duplicate streams.
i=0
while [ "$i" -lt 40 ]; do
    : >"$tmp/f"
    k=0
    while [ "$k" -lt 30 ]; do
        c=$(printf '%s' "$(( (i + k) % 4 ))")
        r=$(( (i * 3 + k) % 3 + 1 ))
        j=0; while [ "$j" -lt "$r" ]; do echo "line$c" >>"$tmp/f"; j=$((j+1)); done
        k=$((k + 1))
    done
    for o in "" -c -d -u; do
        u=$("$BIN" $o "$tmp/f" | norm); r=$("$REF" $o "$tmp/f" | norm)
        [ "$u" = "$r" ] || { echo "FAIL diff fuzz [$o] iter $i"; fail=1; break 2; }
    done
    i=$((i + 1))
done

[ "$fail" -eq 0 ] && echo "PASS differential/uniq (ref: $REF)"
exit "$fail"
