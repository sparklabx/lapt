#!/usr/bin/env bash
# Vertical-slice tests for lib/wrap.sh, seam: lapt::write_wrapper only.
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

# neither lib_dir nor bin_dir given: just the exec line, and the script is executable
test_no_dirs_just_exec() {
  local dir; dir=$(mktemp -d)
  lapt::write_wrapper "$dir/w" "/opt/pkg/bin/pkg" "" ""

  assert_eq "wrapper content" \
    "$(printf '#!/bin/sh\nexec "/opt/pkg/bin/pkg" "$@"')" \
    "$(cat "$dir/w")"
  if [[ ! -x "$dir/w" ]]; then
    printf 'FAIL: wrapper must be executable\n'
    fail=1
  fi

  rm -rf "$dir"
}

# lib_dir given: LD_LIBRARY_PATH export line included
test_lib_dir_adds_ld_library_path() {
  local dir; dir=$(mktemp -d)
  lapt::write_wrapper "$dir/w" "/opt/pkg/bin/pkg" "/opt/pkg/lib" ""

  assert_eq "wrapper content" \
    "$(printf '#!/bin/sh\nexport LD_LIBRARY_PATH="/opt/pkg/lib:$LD_LIBRARY_PATH"\nexec "/opt/pkg/bin/pkg" "$@"')" \
    "$(cat "$dir/w")"

  rm -rf "$dir"
}

# bin_dir given: PATH export line included
test_bin_dir_adds_path() {
  local dir; dir=$(mktemp -d)
  lapt::write_wrapper "$dir/w" "/opt/pkg/bin/pkg" "" "/opt/pkg/bin"

  assert_eq "wrapper content" \
    "$(printf '#!/bin/sh\nexport PATH="/opt/pkg/bin:$PATH"\nexec "/opt/pkg/bin/pkg" "$@"')" \
    "$(cat "$dir/w")"

  rm -rf "$dir"
}

# both given: both export lines, lib then bin
test_both_dirs_both_lines() {
  local dir; dir=$(mktemp -d)
  lapt::write_wrapper "$dir/w" "/opt/pkg/bin/pkg" "/opt/pkg/lib" "/opt/pkg/bin"

  assert_eq "wrapper content" \
    "$(printf '#!/bin/sh\nexport LD_LIBRARY_PATH="/opt/pkg/lib:$LD_LIBRARY_PATH"\nexport PATH="/opt/pkg/bin:$PATH"\nexec "/opt/pkg/bin/pkg" "$@"')" \
    "$(cat "$dir/w")"

  rm -rf "$dir"
}

test_no_dirs_just_exec
test_lib_dir_adds_ld_library_path
test_bin_dir_adds_path
test_both_dirs_both_lines
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
