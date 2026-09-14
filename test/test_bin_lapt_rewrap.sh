#!/usr/bin/env bash
# Subprocess tests for bin/lapt, seam: `lapt rewrap <pkg>` only. rewrap never
# fetches -- it only reads opt_dir and pkg's own cache entry, both already
# on disk, so no fake apt-get/dpkg/dpkg-deb is needed.
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

setup_home() {
  export HOME; HOME=$(mktemp -d)
}
teardown_home() {
  rm -rf "$HOME"
  unset HOME
}

test_rewrap_on_uninstalled_pkg_errors() {
  setup_home

  local rc
  "$LAPT" rewrap foo >/dev/null 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    printf 'FAIL: %s\n  expected nonzero exit, got 0\n' "rewrap on uninstalled pkg errors"
    fail=1
  fi

  teardown_home
}

# "file" was installed before pkgenv/file existed (or pkgenv/file was just
# added): opt/file/bin/file is still plain, unwrapped, but the bundle
# already has share/misc/magic.mgc (the real Debian package ships
# share/misc/magic itself as a dangling symlink -- share/misc/magic.mgc is
# the actual compiled artifact pkgenv/file resolves against). rewrap wraps
# it for the first time and exports MAGIC, resolved to that already-bundled
# path.
test_rewrap_first_time_wraps_via_pkgenv() {
  setup_home
  local opt_dir="$HOME/.lapt/opt/file"
  mkdir -p "$opt_dir/bin" "$opt_dir/share/misc" "$opt_dir/.lapt"
  printf 'real' > "$opt_dir/bin/file"
  printf 'magic' > "$opt_dir/share/misc/magic.mgc"
  printf 'version=1.0\ninstalled=2024-01-01T00:00:00Z\n' > "$opt_dir/.lapt/version"

  local cache_dir="$HOME/.lapt/cache/file_1.0"
  mkdir -p "$cache_dir/usr/bin"
  printf 'real' > "$cache_dir/usr/bin/file"

  local out rc
  out=$("$LAPT" rewrap file 2>&1)
  rc=$?

  assert_exit0 "first-time rewrap exits 0: $out" "$rc"
  assert_eq "real binary moved aside" "real" "$(cat "$opt_dir/bin/file.real" 2>/dev/null)"
  assert_eq "wrapper exports MAGIC" \
    "$(printf '#!/bin/sh\nexport MAGIC="%s/share/misc/magic.mgc"\nexec "%s" "$@"' "$opt_dir" "$opt_dir/bin/file.real")" \
    "$(cat "$opt_dir/bin/file" 2>/dev/null)"

  teardown_home
}

# "git" was already wrapped at install time (it bundles its own lib/git-core,
# which alone triggers a wrapper). rewrap must refresh the wrapper's content
# in place -- adding the GIT_EXEC_PATH export pkgenv/git now declares --
# without touching bin/git.real.
test_rewrap_already_wrapped_refreshes_in_place() {
  setup_home
  local opt_dir="$HOME/.lapt/opt/git"
  mkdir -p "$opt_dir/lib/git-core" "$opt_dir/bin" "$opt_dir/.lapt"
  printf 'real' > "$opt_dir/bin/git.real"
  printf 'helper' > "$opt_dir/lib/git-core/git-upload-pack"
  # stale wrapper, as if written before pkgenv/git existed: LD_LIBRARY_PATH
  # only, no GIT_EXEC_PATH
  printf '#!/bin/sh\nexport LD_LIBRARY_PATH="%s:$LD_LIBRARY_PATH"\nexec "%s" "$@"' \
    "$opt_dir/lib" "$opt_dir/bin/git.real" > "$opt_dir/bin/git"
  chmod +x "$opt_dir/bin/git"
  printf 'version=1.0\ninstalled=2024-01-01T00:00:00Z\n' > "$opt_dir/.lapt/version"

  local cache_dir="$HOME/.lapt/cache/git_1.0"
  mkdir -p "$cache_dir/usr/bin"
  printf 'real' > "$cache_dir/usr/bin/git"

  local out rc
  out=$("$LAPT" rewrap git 2>&1)
  rc=$?

  assert_exit0 "refresh rewrap exits 0: $out" "$rc"
  assert_eq "real binary untouched" "real" "$(cat "$opt_dir/bin/git.real" 2>/dev/null)"
  assert_eq "wrapper refreshed with GIT_EXEC_PATH" \
    "$(printf '#!/bin/sh\nexport LD_LIBRARY_PATH="%s:$LD_LIBRARY_PATH"\nexport GIT_EXEC_PATH="%s/lib/git-core"\nexec "%s" "$@"' \
      "$opt_dir/lib" "$opt_dir" "$opt_dir/bin/git.real")" \
    "$(cat "$opt_dir/bin/git" 2>/dev/null)"

  teardown_home
}

test_rewrap_on_uninstalled_pkg_errors
test_rewrap_first_time_wraps_via_pkgenv
test_rewrap_already_wrapped_refreshes_in_place
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
