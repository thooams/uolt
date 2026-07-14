#!/bin/sh
# Differential test: uolt-grep matches `grep -F` (fixed-string) on stdout and
# exit status. The reference uses -F because uolt-grep is a fixed-string matcher.
set -u
BIN=${UOLT_GREP:-${BUILD:-./build}/uolt-grep}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/grep; [ -x /bin/grep ] && REF=/bin/grep
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
cd "$tmp" || exit 1

printf 'apple\nbanana\ncherry pie\nAPPLE\napple sauce\n' >f
printf 'grape\nApple\nxyz\n' >g
printf 'apple\nan apple a day\npineapple\napple-pie\nAPPLE\nappletree\n' >w

compare() {
    desc=$1; shift
    "$BIN" "$@" >u.out 2>/dev/null; urc=$?
    "$REF" -F "$@" >r.out 2>/dev/null; rrc=$?
    [ "$urc" -eq "$rrc" ] || { echo "FAIL diff [$desc]: exit $urc vs ref $rrc"; fail=1; }
    cmp -s u.out r.out || { echo "FAIL diff [$desc]: output differs"; fail=1; }
}

compare "basic"     apple f
compare "-i"        -i apple f
compare "-v"        -v apple f
compare "-iv"       -iv apple f
compare "no-match"  zzz f
compare "multi"     apple f g
compare "-i multi"  -i apple f g
compare "substring" pp f
compare "space pat" "cherry pie" f
compare "-n"        -n apple f
compare "-c"        -c apple f
compare "-c none"   -c zzz f
compare "-in"       -in apple f
compare "-vn"       -vn apple f
compare "-n multi"  -n apple f g
compare "-c multi"  -c a f g

# -w word-boundary match
compare "-w"        -w apple w
compare "-iw"       -iw apple w
compare "-vw"       -vw apple w
compare "-wn"       -wn apple w
compare "-wc"       -wc apple w
# -x whole-line match
compare "-x"        -x apple w
compare "-ix"       -ix apple w
compare "-vx"       -vx apple w
compare "-xn"       -xn apple w
compare "-x space"  -x "cherry pie" f
compare "-xc"       -xc apple w

# stdin
"$BIN" an <f >u.out 2>/dev/null; urc=$?
"$REF" -F an <f >r.out 2>/dev/null; rrc=$?
{ [ "$urc" -eq "$rrc" ] && cmp -s u.out r.out; } || { echo "FAIL diff [stdin]"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS differential/grep (ref: $REF -F)"
exit "$fail"
