#!/bin/sh
# Unit test for uolt-table (extras): render whitespace-columned stdin as a
# Unicode box-drawing table. There is no reference tool that produces this exact
# format, so these are golden-output assertions rather than differential ones.
set -u
BIN=${UOLT_TABLE:-${BUILD:-./build}/uolt-table}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
fail=0

check() {
    label=$1; input=$2; expected=$3
    got=$(printf '%s' "$input" | "$BIN")
    if [ "$got" != "$expected" ]; then
        echo "FAIL unit: $label"
        printf 'expected:\n%s\ngot:\n%s\n' "$expected" "$got"
        fail=1
    fi
}

# Basic grid: three columns, widths driven by the widest cell in each.
check "basic" 'name size date
foo 1024 jul16
bar 42 jul15
' '┌──────┬──────┬───────┐
│ name │ size │ date  │
│ foo  │ 1024 │ jul16 │
│ bar  │ 42   │ jul15 │
└──────┴──────┴───────┘'

# Ragged rows: short rows get empty padded cells; the table is as wide as the
# widest row.
check "ragged" 'a bb ccc
x
p q r s t
' '┌───┬────┬─────┬───┬───┐
│ a │ bb │ ccc │   │   │
│ x │    │     │   │   │
│ p │ q  │ r   │ s │ t │
└───┴────┴─────┴───┴───┘'

# UTF-8: width is counted in code points, so accented Latin stays aligned
# (café / thé are 4 bytes but 4/3 display columns).
check "utf8" 'nom prix
café 3
thé 2
' '┌──────┬──────┐
│ nom  │ prix │
│ café │ 3    │
│ thé  │ 2    │
└──────┴──────┘'

# Blank and all-whitespace lines produce no row.
check "blank-lines" 'a b


c d
' '┌───┬───┐
│ a │ b │
│ c │ d │
└───┴───┘'

# Runs of blanks collapse; leading/trailing blanks are ignored.
check "extra-spaces" '  x    y
z w
' '┌───┬───┐
│ x │ y │
│ z │ w │
└───┴───┘'

# A final line without a trailing newline is still rendered.
check "no-trailing-newline" 'a b
c d' '┌───┬───┐
│ a │ b │
│ c │ d │
└───┴───┘'

# Empty input yields no output and exit 0.
out=$(printf '' | "$BIN"); rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] || { echo "FAIL unit: empty input"; fail=1; }

# Too many columns (> 1024): refuse with a nonzero exit rather than drop data.
line=$(awk 'BEGIN{for(i=0;i<1100;i++)printf "x ";print ""}')
printf '%s\n' "$line" | "$BIN" >/dev/null 2>&1
[ $? -ne 0 ] || { echo "FAIL unit: too many columns should error"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/table"
exit "$fail"
