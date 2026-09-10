#!/usr/bin/env bash
# Vertical-slice tests for lib/bundle.sh, seam: lapt::bundle_apply only.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/lib/cache.sh"
. "$ROOT/lib/bundle.sh"

fail=0
assert_eq() {
  local desc=$1 expected=$2 actual=$3
  if [[ $expected != "$actual" ]]; then
    printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' "$desc" "$expected" "$actual"
    fail=1
  fi
}

# a plain file row is hardlinked into dest-dir (same inode, not a copy)
test_plain_file_is_hardlinked() {
  local cache dest; cache=$(mktemp -d); dest=$(mktemp -d)
  : > "$cache/foo"
  printf 'bin/foo\t%s\tfoo\n' "$cache/foo" | lapt::bundle_apply "$dest" 0

  local src_inode dest_inode
  src_inode=$(stat -c %i "$cache/foo")
  dest_inode=$(stat -c %i "$dest/bin/foo" 2>/dev/null || echo missing)
  assert_eq "hardlinked file shares inode" "$src_inode" "$dest_inode"

  rm -rf "$cache" "$dest"
}

# a nested dest path gets its parent dirs created
test_nested_dest_path_creates_dirs() {
  local cache dest; cache=$(mktemp -d); dest=$(mktemp -d)
  : > "$cache/libfoo.so.1"
  printf 'lib/sub/libfoo.so.1\t%s\tfoo\n' "$cache/libfoo.so.1" | lapt::bundle_apply "$dest" 0

  local src_inode dest_inode
  src_inode=$(stat -c %i "$cache/libfoo.so.1")
  dest_inode=$(stat -c %i "$dest/lib/sub/libfoo.so.1" 2>/dev/null || echo missing)
  assert_eq "nested hardlinked file shares inode" "$src_inode" "$dest_inode"

  rm -rf "$cache" "$dest"
}

# a row already marked "existing" (from bundle_manifest's dest-dir scan) is skipped, not re-linked
test_existing_row_is_skipped() {
  local cache dest; cache=$(mktemp -d); dest=$(mktemp -d)
  mkdir -p "$dest/bin"
  : > "$dest/bin/already-there"
  local before_inode
  before_inode=$(stat -c %i "$dest/bin/already-there")

  printf 'bin/already-there\t%s\texisting\n' "$dest/bin/already-there" | lapt::bundle_apply "$dest" 0
  local rc=$?

  assert_eq "existing row does not error" "0" "$rc"
  local after_inode
  after_inode=$(stat -c %i "$dest/bin/already-there")
  assert_eq "existing row's file is untouched" "$before_inode" "$after_inode"

  rm -rf "$cache" "$dest"
}

# rewrite-pc=1: a .pc file is copied (independent inode) with prefix/libdir/includedir rewritten
test_pc_file_copied_and_rewritten_when_flagged() {
  local cache dest; cache=$(mktemp -d); dest=$(mktemp -d)
  cat > "$cache/foo.pc" <<'EOF'
prefix=/usr
libdir=${prefix}/lib/x86_64-linux-gnu
includedir=${prefix}/include
Name: foo
Version: 1.0
Libs: -L${libdir} -lfoo
Cflags: -I${includedir}
EOF
  printf 'pkgconfig/foo.pc\t%s\tfoo\n' "$cache/foo.pc" | lapt::bundle_apply "$dest" 1

  local src_inode dest_inode
  src_inode=$(stat -c %i "$cache/foo.pc")
  dest_inode=$(stat -c %i "$dest/pkgconfig/foo.pc" 2>/dev/null || echo missing)
  if [[ $src_inode == "$dest_inode" ]]; then
    printf 'FAIL: %s\n  expected a copy (different inode), got same inode\n' "pc file is copied not hardlinked"
    fail=1
  fi

  local expected actual
  expected=$(printf 'prefix=%s\nlibdir=%s/lib\nincludedir=%s/include' "$dest" "$dest" "$dest")
  actual=$(grep -E '^(prefix|libdir|includedir)=' "$dest/pkgconfig/foo.pc")
  assert_eq "pc prefix/libdir/includedir rewritten" "$expected" "$actual"

  rm -rf "$cache" "$dest"
}

# rewrite-pc=0: a .pc file is hardlinked as-is, same as any other file (assemble path)
test_pc_file_hardlinked_when_not_flagged() {
  local cache dest; cache=$(mktemp -d); dest=$(mktemp -d)
  : > "$cache/foo.pc"
  printf 'pkgconfig/foo.pc\t%s\tfoo\n' "$cache/foo.pc" | lapt::bundle_apply "$dest" 0

  local src_inode dest_inode
  src_inode=$(stat -c %i "$cache/foo.pc")
  dest_inode=$(stat -c %i "$dest/pkgconfig/foo.pc" 2>/dev/null || echo missing)
  assert_eq "pc file hardlinked when rewrite-pc=0" "$src_inode" "$dest_inode"

  rm -rf "$cache" "$dest"
}

test_plain_file_is_hardlinked
test_nested_dest_path_creates_dirs
test_existing_row_is_skipped
test_pc_file_copied_and_rewritten_when_flagged
test_pc_file_hardlinked_when_not_flagged
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
