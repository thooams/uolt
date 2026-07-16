#!/bin/sh
# Unit test for uolt-column (extras): align whitespace-columned stdin into a
# padded table, like `column -t`. Golden-output assertions (the differential test
# checks equality with the system `column`).
set -u
BIN=${UOLT_COLUMN:-${BUILD:-./build}/uolt-column}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
fail=0

check() {
    label=$1; input=$2; expected=$3
    got=$(printf '%s' "$input" | "$BIN")
    if [ "$got" != "$expected" ]; then
        echo "FAIL unit: $label"
        printf 'expected:\n%s\ngot:\n%s\n' "$expected" "$got" | sed 's/ /./g'
        fail=1
    fi
}

# Columns padded to the widest field, two blanks between columns, last column of
# each line not padded.
check "basic" 'name size date
foo 1024 jul16
bar 42 jul15
' 'name  size  date
foo   1024  jul16
bar   42    jul15'

# Ragged rows: a short line emits only the fields it has (no trailing cells);
# widths still come from the widest field per column.
check "ragged" 'a bb ccc
x
p q r
' 'a  bb  ccc
x
p  q   r'

# UTF-8: width is code points, so accented Latin stays aligned.
check "utf8" 'nom prix
café 3
thé 2
' 'nom   prix
café  3
thé   2'

# Blank / all-whitespace lines are dropped (like `column`).
check "blank-lines" 'a b

c d
' 'a  b
c  d'

# Runs of blanks collapse; leading/trailing blanks ignored.
check "extra-spaces" '  x    y
z w
' 'x  y
z  w'

# A single column is emitted unpadded.
check "one-column" 'alpha
bb
c
' 'alpha
bb
c'

# `-t` is accepted (column-compatible invocation) and changes nothing.
[ "$(printf 'a b\nx y\n' | "$BIN" -t)" = "$(printf 'a b\nx y\n' | "$BIN")" ] \
    || { echo "FAIL unit: -t accepted"; fail=1; }

# A final line without a trailing newline is still rendered.
[ "$(printf 'aa b\na bbbb' | "$BIN")" = "$(printf 'aa  b\na   bbbb')" ] \
    || { echo "FAIL unit: no trailing newline"; fail=1; }

# Empty input yields no output and exit 0.
out=$(printf '' | "$BIN"); rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] || { echo "FAIL unit: empty input"; fail=1; }

# Too many columns (> 1024): refuse with a nonzero exit rather than drop data.
line=$(awk 'BEGIN{for(i=0;i<1100;i++)printf "x ";print ""}')
printf '%s\n' "$line" | "$BIN" >/dev/null 2>&1
[ $? -ne 0 ] || { echo "FAIL unit: too many columns should error"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/column"
exit "$fail"
