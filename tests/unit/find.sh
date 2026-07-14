#!/bin/sh
# Unit test for uolt-find: recursive path listing (default "."), with -type f/d.
# Order is filesystem-defined, so results are compared as sorted sets.
set -u
BIN=${UOLT_FIND:-${BUILD:-./build}/uolt-find}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
cd "$tmp" || exit 1

mkdir -p a/b; touch a/f1 a/b/f2 top; ln -s top slink

# Default "." lists everything, including the starting directory.
got=$("$BIN" . | sort | tr '\n' ',')
[ "$got" = ".,./a,./a/b,./a/b/f2,./a/f1,./slink,./top," ] || { echo "FAIL unit: full walk [$got]"; fail=1; }

# A named starting point.
got=$("$BIN" a | sort | tr '\n' ',')
[ "$got" = "a,a/b,a/b/f2,a/f1," ] || { echo "FAIL unit: named start [$got]"; fail=1; }

# -type f: regular files only (symlinks excluded).
got=$("$BIN" . -type f | sort | tr '\n' ',')
[ "$got" = "./a/b/f2,./a/f1,./top," ] || { echo "FAIL unit: -type f [$got]"; fail=1; }

# -type d: directories only.
got=$("$BIN" . -type d | sort | tr '\n' ',')
[ "$got" = ".,./a,./a/b," ] || { echo "FAIL unit: -type d [$got]"; fail=1; }

# -type l: symbolic links only.
got=$("$BIN" . -type l | sort | tr '\n' ',')
[ "$got" = "./slink," ] || { echo "FAIL unit: -type l [$got]"; fail=1; }

# -maxdepth 0: only the starting points.
got=$("$BIN" . -maxdepth 0)
[ "$got" = "." ] || { echo "FAIL unit: -maxdepth 0 [$got]"; fail=1; }

# -maxdepth 1: starting point plus direct children, no grandchildren.
got=$("$BIN" . -maxdepth 1 | sort | tr '\n' ',')
[ "$got" = ".,./a,./slink,./top," ] || { echo "FAIL unit: -maxdepth 1 [$got]"; fail=1; }

# -maxdepth combined with -type.
got=$("$BIN" . -maxdepth 2 -type f | sort | tr '\n' ',')
[ "$got" = "./a/f1,./top," ] || { echo "FAIL unit: -maxdepth 2 -type f [$got]"; fail=1; }

# A single file operand prints just itself.
got=$("$BIN" top)
[ "$got" = "top" ] || { echo "FAIL unit: file operand [$got]"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/find"
exit "$fail"
