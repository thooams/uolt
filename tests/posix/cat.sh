#!/bin/sh
# POSIX behavior for uolt-cat: verbatim copy, stdin when no operand or "-",
# operand order preserved, -u accepted as a no-op, nonzero exit on unreadable.
set -u
BIN=${UOLT_CAT:-./build/uolt-cat}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

printf 'one\ntwo\n'   >"$tmp/a"
printf 'three\nfour\n' >"$tmp/b"

# Verbatim copy, no transformation.
"$BIN" "$tmp/a" >"$tmp/o"
cmp -s "$tmp/o" "$tmp/a" || { echo "FAIL posix: not verbatim"; fail=1; }

# Order is operand order, not sorted or merged.
printf 'one\ntwo\nthree\nfour\n' >"$tmp/want"
"$BIN" "$tmp/a" "$tmp/b" >"$tmp/o"
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL posix: operand order"; fail=1; }

# No operand -> stdin.
printf 'piped\n' | "$BIN" >"$tmp/o"
[ "$(cat "$tmp/o")" = "piped" ] || { echo "FAIL posix: no-operand stdin"; fail=1; }

# "-" -> stdin.
printf 'dash\n' | "$BIN" - >"$tmp/o"
[ "$(cat "$tmp/o")" = "dash" ] || { echo "FAIL posix: '-' stdin"; fail=1; }

# -u is a no-op (unbuffered): same result as without it.
"$BIN" -u "$tmp/a" >"$tmp/o"
cmp -s "$tmp/o" "$tmp/a" || { echo "FAIL posix: -u should be a no-op"; fail=1; }

# Unreadable operand -> nonzero exit.
"$BIN" "$tmp/does-not-exist" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL posix: unreadable file exit 0"; fail=1; }

# Binary-safe: NUL bytes and high bytes survive.
printf 'a\000b\377c' >"$tmp/bin"
"$BIN" "$tmp/bin" >"$tmp/o"
cmp -s "$tmp/o" "$tmp/bin" || { echo "FAIL posix: not binary-safe"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS posix/cat"
exit "$fail"
