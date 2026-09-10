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
  assert_eq "printed rel path" "bin/foo" "$out"
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
  assert_eq "printed rel path" "share/man/man1/foo.1" "$out"
  assert_eq "symlink target" "$opt/share/man/man1/foo.1" "$(readlink -f "$dest_home/share/man/man1/foo.1")"

  rm -rf "$opt" "$dest_home"
}

test_top_level_bin_file_exposed
test_dependency_file_not_exposed
test_non_exposable_category_not_exposed
test_nested_man_page_exposed
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
