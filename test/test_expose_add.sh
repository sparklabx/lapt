#!/usr/bin/env bash
# Vertical-slice tests for lib/expose.sh, seam: lapt::expose_add only.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/lib/expose.sh"

fail=0
assert_eq() {
  local desc=$1 expected=$2 actual=$3
  if [[ $expected != "$actual" ]]; then
    printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' "$desc" "$expected" "$actual"
    fail=1
  fi
}

# a top-level package's own bin/ file is symlinked into dest_home and its rel path printed
test_top_level_bin_file_exposed() {
  local opt dest_home; opt=$(mktemp -d); dest_home=$(mktemp -d)
  mkdir -p "$opt/bin"; : > "$opt/bin/foo"

  local out
  out=$(printf 'bin/foo\t%s\tfoo\n' "$opt/bin/foo" | lapt::expose_add "$opt" "$dest_home" "foo")
  assert_eq "printed bare rel path" "bin/foo" "$out"
  assert_eq "symlink target" "$opt/bin/foo" "$(readlink -f "$dest_home/bin/foo")"

  rm -rf "$opt" "$dest_home"
}

# a dependency's own bin/ file (origin != top-level pkg) is not exposed
test_dependency_file_not_exposed() {
  local opt dest_home; opt=$(mktemp -d); dest_home=$(mktemp -d)
  mkdir -p "$opt/bin"; : > "$opt/bin/python3"

  local out
  out=$(printf 'bin/python3\t%s\tpython3\n' "$opt/bin/python3" | lapt::expose_add "$opt" "$dest_home" "foo")
  assert_eq "no rows printed" "" "$out"
  if [[ -e "$dest_home/bin/python3" ]]; then
    printf 'FAIL: dependency file must not be exposed\n'
    fail=1
  fi

  rm -rf "$opt" "$dest_home"
}

# a top-level package's non-exposable file (e.g. lib/) is not exposed, even though origin matches
test_non_exposable_category_not_exposed() {
  local opt dest_home; opt=$(mktemp -d); dest_home=$(mktemp -d)
  mkdir -p "$opt/lib"; : > "$opt/lib/libfoo.so.1"

  local out
  out=$(printf 'lib/libfoo.so.1\t%s\tfoo\n' "$opt/lib/libfoo.so.1" | lapt::expose_add "$opt" "$dest_home" "foo")
  assert_eq "no rows printed" "" "$out"

  rm -rf "$opt" "$dest_home"
}

# a nested man page path gets its parent dirs created under dest_home
test_nested_man_page_exposed() {
  local opt dest_home; opt=$(mktemp -d); dest_home=$(mktemp -d)
  mkdir -p "$opt/share/man/man1"; : > "$opt/share/man/man1/foo.1"

  local out
  out=$(printf 'share/man/man1/foo.1\t%s\tfoo\n' "$opt/share/man/man1/foo.1" | lapt::expose_add "$opt" "$dest_home" "foo")
  assert_eq "printed bare rel path" "share/man/man1/foo.1" "$out"
  assert_eq "symlink target" "$opt/share/man/man1/foo.1" "$(readlink -f "$dest_home/share/man/man1/foo.1")"

  rm -rf "$opt" "$dest_home"
}

# a pre-existing file already at the dest path: ln -s fails, nothing is
# printed for the row (it was never linked, so there's nothing to record),
# and the call reports failure
# (real case: a stale/foreign file already occupies the exposure path)
test_collision_at_dest_is_not_exposed_and_fails() {
  local opt dest_home; opt=$(mktemp -d); dest_home=$(mktemp -d)
  mkdir -p "$opt/bin" "$dest_home/bin"; : > "$opt/bin/foo"; : > "$dest_home/bin/foo"

  local out rc
  out=$(printf 'bin/foo\t%s\tfoo\n' "$opt/bin/foo" | lapt::expose_add "$opt" "$dest_home" "foo" 2>/dev/null)
  rc=$?
  assert_eq "no row printed" "" "$out"
  if [[ $rc -eq 0 ]]; then
    printf 'FAIL: %s\n  expected nonzero exit, got 0\n' "collision at dest exits nonzero"
    fail=1
  fi

  rm -rf "$opt" "$dest_home"
}

# a collision on one row doesn't stop other rows from being exposed
test_collision_on_one_row_does_not_block_others() {
  local opt dest_home; opt=$(mktemp -d); dest_home=$(mktemp -d)
  mkdir -p "$opt/bin" "$dest_home/bin"
  : > "$opt/bin/clash"; : > "$dest_home/bin/clash"
  : > "$opt/bin/ok"

  local out rc
  out=$(printf 'bin/clash\t%s\tfoo\nbin/ok\t%s\tfoo\n' "$opt/bin/clash" "$opt/bin/ok" | lapt::expose_add "$opt" "$dest_home" "foo" 2>/dev/null)
  rc=$?
  assert_eq "only the exposed row is printed" "bin/ok" "$out"
  if [[ $rc -eq 0 ]]; then
    printf 'FAIL: %s\n  expected nonzero exit, got 0\n' "overall call still exits nonzero"
    fail=1
  fi
  assert_eq "non-colliding row still gets its symlink" "$opt/bin/ok" "$(readlink -f "$dest_home/bin/ok")"

  rm -rf "$opt" "$dest_home"
}

# re-running against a row that's already correctly exposed (e.g. re-running
# `lapt expose <pkg>` after other collisions were fixed) must not choke on
# "File exists" for the row that already succeeded -- it's recognized from
# disk (the symlink already points at opt_dir/rel) and left alone
test_already_correctly_exposed_row_is_left_alone() {
  local opt dest_home; opt=$(mktemp -d); dest_home=$(mktemp -d)
  mkdir -p "$opt/bin"; : > "$opt/bin/foo"
  mkdir -p "$dest_home/bin"; ln -s "$opt/bin/foo" "$dest_home/bin/foo"

  local out rc
  out=$(printf 'bin/foo\t%s\tfoo\n' "$opt/bin/foo" | lapt::expose_add "$opt" "$dest_home" "foo")
  rc=$?
  assert_eq "still reported as exposed" "bin/foo" "$out"
  assert_eq "exits 0" "0" "$rc"
  assert_eq "symlink target unchanged" "$opt/bin/foo" "$(readlink -f "$dest_home/bin/foo")"

  rm -rf "$opt" "$dest_home"
}

test_top_level_bin_file_exposed
test_dependency_file_not_exposed
test_non_exposable_category_not_exposed
test_nested_man_page_exposed
test_collision_at_dest_is_not_exposed_and_fails
test_collision_on_one_row_does_not_block_others
test_already_correctly_exposed_row_is_left_alone
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
