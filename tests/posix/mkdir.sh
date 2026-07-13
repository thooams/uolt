#!/bin/sh
# POSIX behavior for uolt-mkdir: default mode honours the umask (0777 & ~umask),
# -p builds intermediate directories, "--" ends options.
set -u
BIN=${UOLT_MKDIR:-${BUILD:-./build}/uolt-mkdir}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# Default mode with umask 022 -> drwxr-xr-x.
( umask 022; "$BIN" "$tmp/m" )
mode=$(ls -ld "$tmp/m" | cut -c1-10)
[ "$mode" = "drwxr-xr-x" ] || { echo "FAIL posix: default mode [$mode]"; fail=1; }

# umask 077 -> drwx------.
( umask 077; "$BIN" "$tmp/n" )
mode=$(ls -ld "$tmp/n" | cut -c1-10)
[ "$mode" = "drwx------" ] || { echo "FAIL posix: umask 077 mode [$mode]"; fail=1; }

# -p with a deep chain, including a trailing slash and repeated slashes.
"$BIN" -p "$tmp/p//q/r/"; [ -d "$tmp/p/q/r" ] || { echo "FAIL posix: -p deep chain"; fail=1; }

# "--" ends options: a directory literally named -p.
"$BIN" -- "$tmp/-p"; [ -d "$tmp/-p" ] || { echo "FAIL posix: -- literal name"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS posix/mkdir"
exit "$fail"
