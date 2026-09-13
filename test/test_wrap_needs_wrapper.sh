#!/usr/bin/env bash
# Vertical-slice tests for lib/wrap.sh, seam: lapt::needs_wrapper only.
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

# only the top-level package's own bin/ file, no lib/, no foreign bin/: no wrapper needed
test_own_bin_only_not_needed() {
  local out
  out=$(printf 'bin/mytool\t/x\tmytool\n' | lapt::needs_wrapper "mytool")
  assert_eq "no wrapper needed" "" "$out"
}

# a private lib/ file from any origin triggers LD_LIBRARY_PATH
test_lib_file_triggers_lib() {
  local out
  out=$(printf 'bin/mytool\t/x\tmytool\nlib/libpython3.so\t/y\tpython3\n' | lapt::needs_wrapper "mytool")
  assert_eq "lib triggers lib token" "lib" "$out"
}

# a bin/ file from a non-top-level origin triggers PATH
test_foreign_bin_triggers_bin() {
  local out
  out=$(printf 'bin/mytool\t/x\tmytool\nbin/python3\t/y\tpython3\n' | lapt::needs_wrapper "mytool")
  assert_eq "foreign bin triggers bin token" "bin" "$out"
}

# both triggers present: both tokens printed, lib then bin
test_both_triggers_both_tokens() {
  local out
  out=$(printf 'bin/mytool\t/x\tmytool\nbin/python3\t/y\tpython3\nlib/libpython3.so\t/z\tpython3\n' | lapt::needs_wrapper "mytool")
  assert_eq "both tokens printed" "$(printf 'lib\nbin')" "$out"
}

# a pkgenv/<pkg> entry forces a wrapper even with no lib/ and no foreign
# bin/ -- the "file" case (bundles no lib/, only its own usr/bin/file)
test_pkgenv_entry_forces_wrapper() {
  local out
  out=$(printf 'bin/file\t/x\tfile\n' | lapt::needs_wrapper "file")
  assert_eq "pkgenv presence forces a wrapper token" "pkgenv" "$out"
}

# no pkgenv/<pkg> entry: unaffected, same as before
test_no_pkgenv_entry_no_extra_token() {
  local out
  out=$(printf 'bin/mytool\t/x\tmytool\n' | lapt::needs_wrapper "mytool")
  assert_eq "no pkgenv entry adds nothing" "" "$out"
}

test_own_bin_only_not_needed
test_lib_file_triggers_lib
test_foreign_bin_triggers_bin
test_both_triggers_both_tokens
test_pkgenv_entry_forces_wrapper
test_no_pkgenv_entry_no_extra_token
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
