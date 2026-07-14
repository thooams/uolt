#!/bin/sh
# Unit test for uolt-head: first N lines (default 10) of files or stdin, the
# "==> name <==" headers for multiple operands, and a nonzero exit (but continued
# processing) when a file cannot be opened.
set -u
BIN=${UOLT_HEAD:-${BUILD:-./build}/uolt-head}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# 12-line file so the default (10) actually truncates.
i=1; : >"$tmp/a"; while [ "$i" -le 12 ]; do echo "line$i" >>"$tmp/a"; i=$((i+1)); done
printf 'x\ny\n' >"$tmp/b"

# Default: first 10 lines.
"$BIN" "$tmp/a" >"$tmp/o"; rc=$?
[ "$rc" -eq 0 ]                     || { echo "FAIL unit: default exit $rc"; fail=1; }
[ "$(wc -l <"$tmp/o")" -eq 10 ]     || { echo "FAIL unit: default not 10 lines"; fail=1; }
[ "$(head -1 "$tmp/o")" = "line1" ] || { echo "FAIL unit: wrong first line"; fail=1; }

# -n3.
"$BIN" -n3 "$tmp/a" >"$tmp/o"
[ "$(wc -l <"$tmp/o")" -eq 3 ] || { echo "FAIL unit: -n3 not 3 lines"; fail=1; }

# -n 2 (separate argument).
"$BIN" -n 2 "$tmp/a" >"$tmp/o"
[ "$(wc -l <"$tmp/o")" -eq 2 ] || { echo "FAIL unit: -n 2 not 2 lines"; fail=1; }

# Fewer lines than requested: whole file.
"$BIN" -n100 "$tmp/b" >"$tmp/o"
cmp -s "$tmp/o" "$tmp/b" || { echo "FAIL unit: short file not copied whole"; fail=1; }

# No trailing newline is preserved (final partial line counts).
printf 'p\nq' >"$tmp/c"
"$BIN" -n5 "$tmp/c" >"$tmp/o"
cmp -s "$tmp/o" "$tmp/c" || { echo "FAIL unit: partial last line mishandled"; fail=1; }

# stdin (no operand).
printf 'a\nb\nc\n' | "$BIN" -n2 >"$tmp/o"
printf 'a\nb\n' >"$tmp/want"
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL unit: stdin -n2"; fail=1; }

# -c: first N bytes (may split a line).
"$BIN" -c3 "$tmp/a" >"$tmp/o"
[ "$(cat "$tmp/o")" = "lin" ] || { echo "FAIL unit: -c3"; fail=1; }
"$BIN" -c 100 "$tmp/b" >"$tmp/o"
cmp -s "$tmp/o" "$tmp/b" || { echo "FAIL unit: -c beyond size"; fail=1; }
[ "$(printf 'abcdef' | "$BIN" -c4)" = "abcd" ] || { echo "FAIL unit: -c stdin"; fail=1; }

# Multiple files -> headers + blank-line separator.
"$BIN" -n1 "$tmp/a" "$tmp/b" >"$tmp/o"
printf '==> %s <==\nline1\n\n==> %s <==\nx\n' "$tmp/a" "$tmp/b" >"$tmp/want"
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL unit: multi-file header layout"; fail=1; }

# Missing file: nonzero exit, stderr diagnostic, later good file still emitted
# (and no header for the failed one).
"$BIN" -n1 "$tmp/nope" "$tmp/b" >"$tmp/o" 2>"$tmp/e"; rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL unit: missing file exit 0"; fail=1; }
[ -s "$tmp/e" ] || { echo "FAIL unit: no stderr diagnostic"; fail=1; }
grep -q 'line1' "$tmp/o" 2>/dev/null && { echo "FAIL unit: emitted failed file"; fail=1; }
grep -q '^x$' "$tmp/o"   || { echo "FAIL unit: good file dropped after error"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/head"
exit "$fail"
