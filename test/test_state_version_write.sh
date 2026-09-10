#!/usr/bin/env bash
# Vertical-slice tests for lib/state.sh, seam: lapt::version_write only.
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

# writes version= line verbatim and an installed= line matching UTC ISO8601, creating .lapt/ as needed
test_writes_version_and_installed_lines() {
  local opt; opt=$(mktemp -d)
  lapt::version_write "$opt" "1.2.3"

  local version_line installed_line
  version_line=$(sed -n '1p' "$opt/.lapt/version")
  installed_line=$(sed -n '2p' "$opt/.lapt/version")
  assert_eq "version line" "version=1.2.3" "$version_line"
  if [[ ! $installed_line =~ ^installed=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    printf 'FAIL: installed line format\n  actual: %q\n' "$installed_line"
    fail=1
  fi

  rm -rf "$opt"
}

# a re-write (e.g. fix regenerating) overwrites rather than appends
test_rewrite_overwrites_not_appends() {
  local opt; opt=$(mktemp -d)
  lapt::version_write "$opt" "1.0.0"
  lapt::version_write "$opt" "2.0.0"

  local lines
  lines=$(wc -l < "$opt/.lapt/version")
  assert_eq "still exactly two lines" "2" "$lines"
  assert_eq "version line updated" "version=2.0.0" "$(sed -n '1p' "$opt/.lapt/version")"

  rm -rf "$opt"
}

test_writes_version_and_installed_lines
test_rewrite_overwrites_not_appends
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
