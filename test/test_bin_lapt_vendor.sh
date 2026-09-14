#!/usr/bin/env bash
# Subprocess tests for bin/lapt, seam: `lapt vendor <pkg...>` only. No apt
# fakes needed -- vendor only ever reads opt/<pkg>/.lapt/version and prints an
# env script, fixture-able directly (same convention as
# test_bin_lapt_list.sh).
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
}
teardown_fixture() {
  rm -rf "$HOME"; unset HOME
}

# fixture helper: a package already installed at opt/<name> -- all vendor
# needs is that .lapt/version exists
fixture_installed_pkg() {
  local name=$1 version=$2
  local opt_dir="$HOME/.lapt/opt/$name"
  mkdir -p "$opt_dir/.lapt"
  printf 'version=%s\n' "$version" > "$opt_dir/.lapt/version"
}

# no packages named: usage error, nonzero exit
test_no_pkgs_named_errors() {
  setup_fixture
  local rc
  "$LAPT" vendor >/dev/null 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    printf 'FAIL: %s\n  expected nonzero exit, got 0\n' "no pkgs named errors"
    fail=1
  fi
  teardown_fixture
}

# single named package not installed: nonzero exit, nothing on stdout, error
# names the package and hints at install
test_single_missing_pkg_errors() {
  setup_fixture
  local out rc
  out=$("$LAPT" vendor foo 2>/dev/null)
  rc=$?
  if [[ $rc -eq 0 ]]; then
    printf 'FAIL: %s\n  expected nonzero exit, got 0\n' "missing pkg errors"
    fail=1
  fi
  assert_eq "nothing printed to stdout" "" "$out"

  local err
  err=$("$LAPT" vendor foo 2>&1 >/dev/null)
  case $err in
    *foo*) ;;
    *) printf 'FAIL: %s\n  expected error naming foo, got: %s\n' "missing pkg names itself" "$err"; fail=1 ;;
  esac

  teardown_fixture
}

# multiple named packages missing: all of them are reported together in one
# error, not just the first
test_multiple_missing_pkgs_reported_together() {
  setup_fixture
  fixture_installed_pkg baz 1.0

  local err rc
  err=$("$LAPT" vendor foo bar baz 2>&1 >/dev/null)
  rc=$?
  if [[ $rc -eq 0 ]]; then
    printf 'FAIL: %s\n  expected nonzero exit, got 0\n' "multiple missing pkgs errors"
    fail=1
  fi
  case $err in
    *foo*bar*|*bar*foo*) ;;
    *) printf 'FAIL: %s\n  expected error naming both foo and bar, got: %s\n' "both missing names reported" "$err"; fail=1 ;;
  esac
  case $err in
    *baz*) printf 'FAIL: %s\n  expected already-installed baz not named as missing, got: %s\n' "installed pkg not reported missing" "$err"; fail=1 ;;
  esac

  teardown_fixture
}

# every named package already installed: env script printed to stdout, one
# PATH/LD_LIBRARY_PATH/CPATH/PKG_CONFIG_PATH quad per package (via the
# dedup-guarded _lapt_pathadd helper, shared with `lapt init`'s env file),
# in argument order
test_success_prints_env_script_in_arg_order() {
  setup_fixture
  fixture_installed_pkg foo 1.0
  fixture_installed_pkg bar 2.0
  local foo_dir="$HOME/.lapt/opt/foo" bar_dir="$HOME/.lapt/opt/bar"

  local out rc
  out=$("$LAPT" vendor foo bar 2>&1)
  rc=$?

  assert_exit0 "success exits 0: $out" "$rc"
  assert_eq "vendor env script" \
"_lapt_pathadd() {
  local -n __lapt_var=\$2
  case \":\$__lapt_var:\" in
    *\":\$1:\"*) ;;
    *) __lapt_var=\"\$1:\$__lapt_var\${3:-}\" ;;
  esac
  export \"\$2\"
}
_lapt_pathadd \"$foo_dir/bin\" PATH
_lapt_pathadd \"$foo_dir/lib\" LD_LIBRARY_PATH
_lapt_pathadd \"$foo_dir/include\" CPATH
_lapt_pathadd \"$foo_dir/lib/pkgconfig\" PKG_CONFIG_PATH
_lapt_pathadd \"$bar_dir/bin\" PATH
_lapt_pathadd \"$bar_dir/lib\" LD_LIBRARY_PATH
_lapt_pathadd \"$bar_dir/include\" CPATH
_lapt_pathadd \"$bar_dir/lib/pkgconfig\" PKG_CONFIG_PATH
unset -f _lapt_pathadd" \
    "$out"

  teardown_fixture
}

# re-sourcing the printed script (e.g. persisted into a shell rc file and
# re-run by a nested shell) must not keep prepending duplicate entries --
# same _lapt_pathadd dedup idiom as `lapt init`'s env file
test_resourcing_output_is_idempotent() {
  setup_fixture
  fixture_installed_pkg foo 1.0
  local foo_dir="$HOME/.lapt/opt/foo"

  local script; script=$("$LAPT" vendor foo 2>/dev/null)

  local path_out cpath_out
  path_out=$(PATH="/usr/bin" bash -c 'eval "$1"; eval "$1"; echo "$PATH"' _ "$script")
  cpath_out=$(CPATH="" bash -c 'eval "$1"; eval "$1"; echo "$CPATH"' _ "$script")
  assert_eq "PATH entry not duplicated on re-source" "$foo_dir/bin:/usr/bin" "$path_out"
  assert_eq "CPATH entry not duplicated on re-source" "$foo_dir/include:" "$cpath_out"

  teardown_fixture
}

test_no_pkgs_named_errors
test_single_missing_pkg_errors
test_multiple_missing_pkgs_reported_together
test_success_prints_env_script_in_arg_order
test_resourcing_output_is_idempotent
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
