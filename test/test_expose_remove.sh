#!/usr/bin/env bash
# Vertical-slice tests for lib/expose.sh, seam: lapt::expose_remove only.
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

# a symlink resolving into this package's own opt_dir is unlinked
test_own_symlink_removed() {
  local opt dest_home; opt=$(mktemp -d); dest_home=$(mktemp -d)
  mkdir -p "$opt/bin"; : > "$opt/bin/foo"
  mkdir -p "$dest_home/bin"; ln -s "$opt/bin/foo" "$dest_home/bin/foo"

  printf 'bin/foo\n' | lapt::expose_remove "$opt" "$dest_home"

  if [[ -e "$dest_home/bin/foo" || -L "$dest_home/bin/foo" ]]; then
    printf 'FAIL: %s\n  expected symlink removed, still present\n' "own symlink removed"
    fail=1
  fi

  rm -rf "$opt" "$dest_home"
}

# a symlink that now resolves into a different package's opt_dir (claimed by a later install) is left alone
test_reclaimed_symlink_left_alone() {
  local opt other dest_home; opt=$(mktemp -d); other=$(mktemp -d); dest_home=$(mktemp -d)
  mkdir -p "$other/bin"; : > "$other/bin/foo"
  mkdir -p "$dest_home/bin"; ln -s "$other/bin/foo" "$dest_home/bin/foo"

  printf 'bin/foo\n' | lapt::expose_remove "$opt" "$dest_home"

  assert_eq "reclaimed symlink still points at other pkg" \
    "$other/bin/foo" "$(readlink -f "$dest_home/bin/foo")"

  rm -rf "$opt" "$other" "$dest_home"
}

test_own_symlink_removed
test_reclaimed_symlink_left_alone
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
