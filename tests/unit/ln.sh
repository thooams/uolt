#!/bin/sh
# Unit test for uolt-ln: hard links, symbolic links (-s), force (-f), the
# implicit basename target, and error handling.
set -u
BIN=${UOLT_LN:-${BUILD:-./build}/uolt-ln}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
cd "$tmp" || exit 1
printf 'data\n' >src

# Hard link: same inode, same content.
"$BIN" src hard; { [ $? -eq 0 ] && [ hard -ef src ]; } || { echo "FAIL unit: hard link"; fail=1; }

# Symbolic link points at the source.
"$BIN" -s src sym
{ [ -L sym ] && [ "$(readlink sym)" = "src" ]; } || { echo "FAIL unit: symlink"; fail=1; }

# Existing target without -f is an error.
"$BIN" -s src sym 2>/dev/null; [ $? -ne 0 ] || { echo "FAIL unit: existing target exit 0"; fail=1; }

# -f replaces the existing target.
printf 'other\n' >src2
"$BIN" -sf src2 sym; { [ $? -eq 0 ] && [ "$(readlink sym)" = "src2" ]; } || { echo "FAIL unit: -f replace"; fail=1; }

# Implicit target = basename of the source, in the current directory.
mkdir sub; printf 'x\n' >sub/leaf
"$BIN" sub/leaf; { [ -f leaf ] && [ leaf -ef sub/leaf ]; } || { echo "FAIL unit: implicit basename"; fail=1; }

# Link into an existing directory: dst is a dir -> dir/basename(src).
mkdir intod; printf 'p\n' >pp
"$BIN" pp intod; { [ -f intod/pp ] && [ intod/pp -ef pp ]; } || { echo "FAIL unit: into-dir hard"; fail=1; }
printf '1' >i1; printf '2' >i2; "$BIN" i1 i2 intod
{ [ intod/i1 -ef i1 ] && [ intod/i2 -ef i2 ]; } || { echo "FAIL unit: multi into-dir"; fail=1; }
"$BIN" -s pp intod2 2>/dev/null; mkdir intos; "$BIN" -s pp intos
{ [ -L intos/pp ] && [ "$(readlink intos/pp)" = pp ]; } || { echo "FAIL unit: into-dir sym"; fail=1; }

# Hard link to a missing source is an error.
"$BIN" nope dest 2>/dev/null; [ $? -ne 0 ] || { echo "FAIL unit: missing source exit 0"; fail=1; }

# No operand -> error.
"$BIN" >/dev/null 2>&1; [ $? -ne 0 ] || { echo "FAIL unit: no operand exit 0"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/ln"
exit "$fail"
