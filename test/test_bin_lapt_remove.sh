#!/usr/bin/env bash
# Subprocess tests for bin/lapt, seam: `lapt remove <pkg>` only. No apt fakes
# needed -- remove only ever touches opt_dir/.lapt state and exposed symlinks,
# both fixture-able directly without a fake install.
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
assert_exit0() {
  local desc=$1 rc=$2
  [[ $rc -eq 0 ]] || { printf 'FAIL: %s\n  expected exit 0, got %s\n' "$desc" "$rc"; fail=1; }
}

HOME_DIR=""
setup_fixture() {
  export HOME; HOME=$(mktemp -d)
  local opt_dir="$HOME/.lapt/opt/foo"
  mkdir -p "$opt_dir/bin" "$opt_dir/.lapt" "$HOME/.lapt/bin"
  : > "$opt_dir/bin/foo"
  ln -s "$opt_dir/bin/foo" "$HOME/.lapt/bin/foo"
  printf 'version=1.0\ninstalled=2024-01-01T00:00:00Z\n' > "$opt_dir/.lapt/version"
  printf 'bin/foo\n' > "$opt_dir/.lapt/exposed"
}
teardown_fixture() {
  rm -rf "$HOME"
  unset HOME
}

test_remove_on_uninstalled_pkg_errors() {
  export HOME; HOME=$(mktemp -d)

  local rc
  "$LAPT" remove foo >/dev/null 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    printf 'FAIL: %s\n  expected nonzero exit, got 0\n' "remove on uninstalled pkg errors"
    fail=1
  fi

  rm -rf "$HOME"; unset HOME
}

test_remove_deletes_opt_dir_and_unlinks_exposed_files() {
  setup_fixture
  local opt_dir="$HOME/.lapt/opt/foo"

  local out rc
  out=$("$LAPT" remove foo 2>&1)
  rc=$?

  assert_exit0 "remove exits 0" "$rc"
  if [[ -e $opt_dir ]]; then
    printf 'FAIL: %s\n  opt_dir still exists: %s\n' "opt_dir removed" "$opt_dir"
    fail=1
  fi
  if [[ -e "$HOME/.lapt/bin/foo" || -L "$HOME/.lapt/bin/foo" ]]; then
    printf 'FAIL: %s\n  exposed symlink still exists\n' "exposed symlink removed"
    fail=1
  fi

  teardown_fixture
}

# an exposed symlink that was reclaimed by a later, unrelated package must not
# be unlinked by this package's remove -- same guard expose_remove already
# provides, exercised here through cmd_remove
test_remove_does_not_touch_reclaimed_symlink() {
  setup_fixture
  local opt_dir="$HOME/.lapt/opt/foo"
  local other_dir="$HOME/.lapt/opt/other"
  mkdir -p "$other_dir/bin"; : > "$other_dir/bin/foo"
  rm -f "$HOME/.lapt/bin/foo"
  ln -s "$other_dir/bin/foo" "$HOME/.lapt/bin/foo"

  "$LAPT" remove foo >/dev/null 2>&1

  assert_eq "reclaimed symlink left alone" "$other_dir/bin/foo" "$(readlink -f "$HOME/.lapt/bin/foo" 2>/dev/null)"

  teardown_fixture
}

test_remove_on_uninstalled_pkg_errors
test_remove_deletes_opt_dir_and_unlinks_exposed_files
test_remove_does_not_touch_reclaimed_symlink
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
