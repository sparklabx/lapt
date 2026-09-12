#!/usr/bin/env bash
# Subprocess tests for bin/lapt, seam: bare invocation, `--help`, and the
# unknown-subcommand error path. All exercise usage() output only, no fixtures.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAPT="$ROOT/bin/lapt"

fail=0
assert_eq() {
  local desc=$1 expected=$2 actual=$3
  if [[ $expected != "$actual" ]]; then
    printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' "$desc" "$expected" "$actual"
    fail=1
  fi
}

test_bare_invocation_prints_usage() {
  export HOME; HOME=$(mktemp -d)

  local out rc
  out=$("$LAPT" 2>&1)
  rc=$?

  assert_eq "bare invocation exits 0" "0" "$rc"
  [[ $out == usage:* || $out == lapt* ]]
  assert_eq "bare invocation prints usage" "0" "$?"

  rm -rf "$HOME"; unset HOME
}

test_help_flag_prints_usage() {
  export HOME; HOME=$(mktemp -d)

  local out rc
  out=$("$LAPT" --help 2>&1)
  rc=$?

  assert_eq "--help exits 0" "0" "$rc"
  [[ $out == *"usage: lapt <command>"* ]]
  assert_eq "--help prints usage line" "0" "$?"

  rm -rf "$HOME"; unset HOME
}

test_unknown_subcommand_errors_with_usage() {
  export HOME; HOME=$(mktemp -d)

  local out rc
  out=$("$LAPT" bogus 2>&1)
  rc=$?

  assert_eq "unknown subcommand exits 1" "1" "$rc"
  [[ $out == *"unknown subcommand: bogus"* ]]
  assert_eq "error names the bad subcommand" "0" "$?"
  [[ $out == *"usage: lapt <command>"* ]]
  assert_eq "error is followed by usage list" "0" "$?"

  rm -rf "$HOME"; unset HOME
}

test_bare_invocation_prints_usage
test_help_flag_prints_usage
test_unknown_subcommand_errors_with_usage
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
