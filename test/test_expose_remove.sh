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
  local lapt_home opt; lapt_home=$(mktemp -d); opt="$lapt_home/opt/foo"
  mkdir -p "$opt/bin"; : > "$opt/bin/foo"
  mkdir -p "$lapt_home/bin"; ln -s "$opt/bin/foo" "$lapt_home/bin/foo"

  printf 'bin/foo\n' | LAPT_HOME="$lapt_home" lapt::expose_remove "foo"

  if [[ -e "$lapt_home/bin/foo" || -L "$lapt_home/bin/foo" ]]; then
    printf 'FAIL: %s\n  expected symlink removed, still present\n' "own symlink removed"
    fail=1
  fi

  rm -rf "$lapt_home"
}

# a symlink that now resolves into a different package's opt_dir (claimed by a later install) is left alone
test_reclaimed_symlink_left_alone() {
  local lapt_home other; lapt_home=$(mktemp -d); other="$lapt_home/opt/other"
  mkdir -p "$other/bin"; : > "$other/bin/foo"
  mkdir -p "$lapt_home/bin"; ln -s "$other/bin/foo" "$lapt_home/bin/foo"

  printf 'bin/foo\n' | LAPT_HOME="$lapt_home" lapt::expose_remove "foo"

  assert_eq "reclaimed symlink still points at other pkg" \
    "$other/bin/foo" "$(readlink -f "$lapt_home/bin/foo")"

  rm -rf "$lapt_home"
}

# a package's own file is itself a symlink to a sibling file (e.g. Debian's
# make ships bin/gmake -> make) -- removal must compare against the literal,
# unresolved symlink target, not where it eventually resolves to, or the
# exposed alias is wrongly treated as foreign and left orphaned
test_own_symlink_alias_removed() {
  local lapt_home opt; lapt_home=$(mktemp -d); opt="$lapt_home/opt/foo"
  mkdir -p "$opt/bin"; : > "$opt/bin/foo"; ln -s foo "$opt/bin/gfoo"
  mkdir -p "$lapt_home/bin"; ln -s "$opt/bin/gfoo" "$lapt_home/bin/gfoo"

  printf 'bin/gfoo\n' | LAPT_HOME="$lapt_home" lapt::expose_remove "foo"

  if [[ -e "$lapt_home/bin/gfoo" || -L "$lapt_home/bin/gfoo" ]]; then
    printf 'FAIL: %s\n  expected symlink-alias removed, still present\n' "own symlink-alias removed"
    fail=1
  fi

  rm -rf "$lapt_home"
}

test_own_symlink_removed
test_reclaimed_symlink_left_alone
test_own_symlink_alias_removed
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
