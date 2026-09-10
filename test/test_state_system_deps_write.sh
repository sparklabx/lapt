#!/usr/bin/env bash
# Vertical-slice tests for lib/state.sh, seam: lapt::system_deps_write only.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/lib/state.sh"

fail=0
assert_eq() {
  local desc=$1 expected=$2 actual=$3
  if [[ $expected != "$actual" ]]; then
    printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' "$desc" "$expected" "$actual"
    fail=1
  fi
}

# writes "name version" rows verbatim, one per line, creating .lapt/ as needed
test_writes_rows_verbatim() {
  local opt; opt=$(mktemp -d)
  printf 'debconf 1.5.79\nlibfoo 2.0\n' | lapt::system_deps_write "$opt"

  assert_eq "system-deps content" \
    "$(printf 'debconf 1.5.79\nlibfoo 2.0')" \
    "$(cat "$opt/.lapt/system-deps")"

  rm -rf "$opt"
}

# a re-write (e.g. fix regenerating after re-verification) overwrites rather than appends
test_rewrite_overwrites_not_appends() {
  local opt; opt=$(mktemp -d)
  printf 'debconf 1.5.79\n' | lapt::system_deps_write "$opt"
  printf 'libfoo 2.0\n' | lapt::system_deps_write "$opt"

  assert_eq "system-deps content after rewrite" \
    "libfoo 2.0" \
    "$(cat "$opt/.lapt/system-deps")"

  rm -rf "$opt"
}

test_writes_rows_verbatim
test_rewrite_overwrites_not_appends
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
