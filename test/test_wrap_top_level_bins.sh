#!/usr/bin/env bash
# Vertical-slice tests for lib/wrap.sh, seam: lapt::wrap_top_level_bins only.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/lib/wrap.sh"

fail=0
assert_eq() {
  local desc=$1 expected=$2 actual=$3
  if [[ $expected != "$actual" ]]; then
    printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' "$desc" "$expected" "$actual"
    fail=1
  fi
}

# the top-level package's own bin/ file is moved aside to .real and replaced
# with a wrapper pointing at opt_dir (not work_dir)
test_own_bin_is_moved_aside_and_wrapped() {
  local work_dir; work_dir=$(mktemp -d)
  mkdir -p "$work_dir/bin"
  printf 'real' > "$work_dir/bin/foo"

  printf 'bin/foo\t/x\tfoo\n' | lapt::wrap_top_level_bins "$work_dir" "/opt/foo" "foo" "/opt/foo/lib" "/opt/foo/bin"

  assert_eq "real binary moved aside" "real" "$(cat "$work_dir/bin/foo.real" 2>/dev/null)"
  assert_eq "wrapper written at the original path" \
    "$(printf '#!/bin/sh\nexport LD_LIBRARY_PATH="/opt/foo/lib:$LD_LIBRARY_PATH"\nexport PATH="/opt/foo/bin:$PATH"\nexec "/opt/foo/bin/foo.real" "$@"')" \
    "$(cat "$work_dir/bin/foo" 2>/dev/null)"

  rm -rf "$work_dir"
}

# a bin/ file from a non-top-level origin is left untouched
test_foreign_bin_is_untouched() {
  local work_dir; work_dir=$(mktemp -d)
  mkdir -p "$work_dir/bin"
  printf 'real' > "$work_dir/bin/python3"

  printf 'bin/python3\t/x\tpython3\n' | lapt::wrap_top_level_bins "$work_dir" "/opt/foo" "foo" "" "/opt/foo/bin"

  assert_eq "foreign bin left in place" "real" "$(cat "$work_dir/bin/python3" 2>/dev/null)"
  if [[ -e "$work_dir/bin/python3.real" ]]; then
    printf 'FAIL: foreign bin must not be moved aside\n'
    fail=1
  fi

  rm -rf "$work_dir"
}

# multiple top-level bin/ files: each one is wrapped
test_multiple_own_bins_all_wrapped() {
  local work_dir; work_dir=$(mktemp -d)
  mkdir -p "$work_dir/bin"
  printf 'real1' > "$work_dir/bin/foo"
  printf 'real2' > "$work_dir/bin/bar"

  printf 'bin/foo\t/x\tfoo\nbin/bar\t/y\tfoo\n' | lapt::wrap_top_level_bins "$work_dir" "/opt/foo" "foo" "" ""

  assert_eq "foo moved aside" "real1" "$(cat "$work_dir/bin/foo.real" 2>/dev/null)"
  assert_eq "bar moved aside" "real2" "$(cat "$work_dir/bin/bar.real" 2>/dev/null)"

  rm -rf "$work_dir"
}

test_own_bin_is_moved_aside_and_wrapped
test_foreign_bin_is_untouched
test_multiple_own_bins_all_wrapped
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
