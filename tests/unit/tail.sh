#!/bin/sh
# Unit test for uolt-tail: last N lines (default 10) of files or stdin, the
# "-n +N" start-at-line form, multi-file "==> name <==" headers, and a nonzero
# exit (with continued processing) when a file cannot be opened.
set -u
BIN=${UOLT_TAIL:-${BUILD:-./build}/uolt-tail}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# 12-line file so the default (10) truncates.
i=1; : >"$tmp/a"; while [ "$i" -le 12 ]; do echo "line$i" >>"$tmp/a"; i=$((i+1)); done
printf 'x\ny\n' >"$tmp/b"

# Default: last 10 lines (line3..line12).
"$BIN" "$tmp/a" >"$tmp/o"; rc=$?
[ "$rc" -eq 0 ]                        || { echo "FAIL unit: default exit $rc"; fail=1; }
[ "$(wc -l <"$tmp/o")" -eq 10 ]        || { echo "FAIL unit: default not 10 lines"; fail=1; }
[ "$(head -1 "$tmp/o")" = "line3" ]    || { echo "FAIL unit: wrong first tail line"; fail=1; }
[ "$(tail -1 "$tmp/o")" = "line12" ]   || { echo "FAIL unit: wrong last line"; fail=1; }

# -n3: last three.
"$BIN" -n3 "$tmp/a" >"$tmp/o"
printf 'line10\nline11\nline12\n' >"$tmp/want"
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL unit: -n3 wrong"; fail=1; }

# -n +10: from line 10 to end.
"$BIN" -n +10 "$tmp/a" >"$tmp/o"
printf 'line10\nline11\nline12\n' >"$tmp/want"
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL unit: -n +10 wrong"; fail=1; }

# More lines requested than present: whole file.
"$BIN" -n100 "$tmp/b" >"$tmp/o"
cmp -s "$tmp/o" "$tmp/b" || { echo "FAIL unit: short file not whole"; fail=1; }

# No trailing newline preserved.
printf 'p\nq' >"$tmp/c"
"$BIN" -n1 "$tmp/c" >"$tmp/o"
printf 'q' >"$tmp/want"
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL unit: partial last line"; fail=1; }

# stdin (pipe path), last 2.
printf 'a\nb\nc\nd\n' | "$BIN" -n2 >"$tmp/o"
printf 'c\nd\n' >"$tmp/want"
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL unit: stdin -n2"; fail=1; }

# -c: last N bytes (seek and pipe paths).
printf '0123456789' >"$tmp/c10"
[ "$("$BIN" -c3 "$tmp/c10")" = "789" ]      || { echo "FAIL unit: -c3 file"; fail=1; }
[ "$(printf '0123456789' | "$BIN" -c4)" = "6789" ] || { echo "FAIL unit: -c pipe"; fail=1; }
[ "$("$BIN" -c +4 "$tmp/c10")" = "3456789" ] || { echo "FAIL unit: -c +N"; fail=1; }
[ "$("$BIN" -c 999 "$tmp/c10")" = "0123456789" ] || { echo "FAIL unit: -c beyond size"; fail=1; }

# Multiple files -> headers + blank-line separator.
"$BIN" -n1 "$tmp/a" "$tmp/b" >"$tmp/o"
printf '==> %s <==\nline12\n\n==> %s <==\ny\n' "$tmp/a" "$tmp/b" >"$tmp/want"
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL unit: multi-file header layout"; fail=1; }

# Missing file: nonzero exit, stderr diagnostic (no header), later file still shown.
"$BIN" -n1 "$tmp/nope" "$tmp/b" >"$tmp/o" 2>"$tmp/e"; rc=$?
[ "$rc" -ne 0 ]        || { echo "FAIL unit: missing exit 0"; fail=1; }
[ -s "$tmp/e" ]        || { echo "FAIL unit: no stderr diagnostic"; fail=1; }
grep -q '^y$' "$tmp/o" || { echo "FAIL unit: good file dropped after error"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/tail"
exit "$fail"
