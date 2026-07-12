#!/bin/sh
# Differential test: uolt-pwd matches `/bin/pwd -P` (physical path) byte-for-byte
# from several directories.
set -u
BIN=${UOLT_PWD:-./build/uolt-pwd}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/bin/pwd; [ -x /usr/bin/pwd ] && REF=/usr/bin/pwd
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# A symlink-free set of dirs that exist on both Linux and macOS.
for d in / /tmp /usr "$tmp"; do
    [ -d "$d" ] || continue
    uo=$(cd "$d" && "$BIN"); urc=$?
    ro=$(cd "$d" && "$REF" -P); rrc=$?
    [ "$urc" -eq "$rrc" ] || { echo "FAIL diff [$d]: exit $urc vs $rrc"; fail=1; }
    [ "$uo" = "$ro" ]     || { echo "FAIL diff [$d]: [$uo] != [$ro]"; fail=1; }
done

[ "$fail" -eq 0 ] && echo "PASS differential/pwd (ref: $REF -P)"
exit "$fail"
