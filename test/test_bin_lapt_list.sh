#!/usr/bin/env bash
# Subprocess tests for bin/lapt, seam: `lapt list` only. No apt fakes needed --
# list only ever reads opt/*/.lapt/version, fixture-able directly.
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

test_list_on_empty_opt_is_silent() {
  export HOME; HOME=$(mktemp -d)

  local out rc
  out=$("$LAPT" list 2>&1)
  rc=$?

  assert_eq "list exits 0 on empty opt" "0" "$rc"
  assert_eq "list prints nothing on empty opt" "" "$out"

  rm -rf "$HOME"; unset HOME
}

test_list_prints_name_and_version_per_pkg() {
  export HOME; HOME=$(mktemp -d)
  local opt_root="$HOME/.local/share/lapt/opt"
  mkdir -p "$opt_root/curl/.lapt" "$opt_root/ripgrep/.lapt"
  printf 'version=8.5.0\ninstalled=2024-01-01T00:00:00Z\n' > "$opt_root/curl/.lapt/version"
  printf 'version=14.1.0\ninstalled=2024-01-02T00:00:00Z\n' > "$opt_root/ripgrep/.lapt/version"

  local out
  out=$("$LAPT" list 2>&1)

  assert_eq "list output" "curl 8.5.0
ripgrep 14.1.0" "$out"

  rm -rf "$HOME"; unset HOME
}

test_list_strips_debian_point_release_suffix() {
  export HOME; HOME=$(mktemp -d)
  local opt_root="$HOME/.local/share/lapt/opt"
  mkdir -p "$opt_root/curl/.lapt"
  printf 'version=8.5.0-2+deb12u1\ninstalled=2024-01-01T00:00:00Z\n' > "$opt_root/curl/.lapt/version"

  local out
  out=$("$LAPT" list 2>&1)

  assert_eq "point-release suffix stripped from display" "curl 8.5.0-2" "$out"

  rm -rf "$HOME"; unset HOME
}

test_list_skips_incomplete_opt_dirs() {
  # a .tmp.XXXXXX scratch dir from an in-flight install, or any opt/<pkg> with
  # no .lapt/version yet, isn't an installed package -- don't list it
  export HOME; HOME=$(mktemp -d)
  local opt_root="$HOME/.local/share/lapt/opt"
  mkdir -p "$opt_root/.tmp.abc123"

  local out
  out=$("$LAPT" list 2>&1)

  assert_eq "incomplete opt dir not listed" "" "$out"

  rm -rf "$HOME"; unset HOME
}

test_list_on_empty_opt_is_silent
test_list_prints_name_and_version_per_pkg
test_list_strips_debian_point_release_suffix
test_list_skips_incomplete_opt_dirs
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
