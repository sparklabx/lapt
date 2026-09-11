#!/usr/bin/env bash
# Subprocess tests for bin/lapt, seam: `lapt fix <pkg>` only. Same fake
# apt-get/dpkg/dpkg-deb-on-PATH convention as test_bin_lapt_install.sh, minus
# the apt-cache fake -- fix never resolves a closure or looks up a fresh
# candidate, it only re-verifies and re-fetches at the version already
# recorded in .lapt/system-deps.
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

FAKEBIN=""
setup_fakes() {
  FAKEBIN=$(mktemp -d)
  export FIXTURE_DIR; FIXTURE_DIR=$(mktemp -d)
  mkdir -p "$FIXTURE_DIR"/{dpkg_status,deb_contents,extract}
  export HOME; HOME=$(mktemp -d)

  cat > "$FAKEBIN/dpkg" <<'EOF'
#!/usr/bin/env bash
case $1 in
  -s)
    v=$(cat "$FIXTURE_DIR/dpkg_status/$2" 2>/dev/null) || { echo "dpkg-query: package '$2' is not installed" >&2; exit 1; }
    echo "Package: $2"; echo "Status: install ok installed"; echo "Version: $v"
    ;;
  -x)
    key=$(basename "$2" .deb)
    mkdir -p "$3"
    cp -r "$FIXTURE_DIR/extract/$key/." "$3/"
    ;;
esac
EOF
  cat > "$FAKEBIN/dpkg-deb" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == -c ]]; then
  key=$(basename "$2" .deb)
  cat "$FIXTURE_DIR/deb_contents/$key"
fi
EOF
  cat > "$FAKEBIN/apt-get" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == download ]]; then
  : > "${2/=/_}.deb"
fi
EOF
  chmod +x "$FAKEBIN"/*
}
teardown_fakes() {
  rm -rf "$FAKEBIN" "$FIXTURE_DIR" "$HOME"
  unset FIXTURE_DIR HOME
}

test_fix_on_uninstalled_pkg_errors() {
  setup_fakes

  local rc
  PATH="$FAKEBIN:$PATH" "$LAPT" fix foo >/dev/null 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    printf 'FAIL: %s\n  expected nonzero exit, got 0\n' "fix on uninstalled pkg errors"
    fail=1
  fi

  teardown_fakes
}

# fixture helper: an opt/<pkg> as install would have left it, with a given
# .lapt/system-deps content (may be empty). Also seeds pkg's own cache entry
# (cache entries are never evicted except by an explicit `lapt prune`, so a
# real post-install opt/<pkg> always has one) -- cmd_fix reads it back via
# the same bundle_manifest(fresh-dir, "pkg:version:pkg") trick cmd_expose
# uses, to tell pkg's own bin/ files apart from a dependency's.
fixture_installed_pkg() {
  local pkg=$1 version=$2 system_deps=$3
  local opt_dir="$HOME/.lapt/opt/$pkg"
  mkdir -p "$opt_dir/bin" "$opt_dir/.lapt"
  printf 'real' > "$opt_dir/bin/$pkg"
  printf 'version=%s\ninstalled=2024-01-01T00:00:00Z\n' "$version" > "$opt_dir/.lapt/version"
  printf '%s' "$system_deps" > "$opt_dir/.lapt/system-deps"

  local cache_dir="$HOME/.lapt/cache/${pkg}_${version}"
  mkdir -p "$cache_dir/usr/bin"
  printf 'real' > "$cache_dir/usr/bin/$pkg"
}

test_fix_all_deps_still_satisfied_is_noop() {
  setup_fakes
  fixture_installed_pkg foo 1.0 "libbar 2.0"$'\n'
  printf '%s' "2.0" > "$FIXTURE_DIR/dpkg_status/libbar"
  local opt_dir="$HOME/.lapt/opt/foo"

  local rc
  PATH="$FAKEBIN:$PATH" "$LAPT" fix foo >/dev/null 2>&1
  rc=$?

  assert_exit0 "fix with nothing stale exits 0" "$rc"
  assert_eq "system-deps unchanged" "libbar 2.0" "$(cat "$opt_dir/.lapt/system-deps")"
  if [[ -e "$HOME/.lapt/cache/libbar_2.0" ]]; then
    printf 'FAIL: %s\n  expected libbar never fetched, found a cache entry\n' "still-satisfied dep is never fetched"
    fail=1
  fi

  teardown_fakes
}

# libbar was recorded as system-satisfied at 2.0, but the fake dpkg_status
# fixture has no libbar entry -- dpkg -s now fails, same as the package
# having been uninstalled since. fix must fetch it AT THE RECORDED VERSION
# (no apt-cache candidate lookup -- system-deps carries no fake for one),
# bundle it flattened into opt/foo/, and drop the line from system-deps.
test_fix_stale_dep_is_fetched_and_bundled() {
  setup_fakes
  fixture_installed_pkg foo 1.0 "libbar 2.0"$'\n'
  local opt_dir="$HOME/.lapt/opt/foo"
  printf -- '-rw-r--r-- root/root 4 2024-01-01 00:00 ./usr/lib/libbar.so.1\n' \
    > "$FIXTURE_DIR/deb_contents/libbar_2.0"
  mkdir -p "$FIXTURE_DIR/extract/libbar_2.0/usr/lib"
  printf 'lib' > "$FIXTURE_DIR/extract/libbar_2.0/usr/lib/libbar.so.1"

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" fix foo 2>&1)
  rc=$?

  assert_exit0 "fix with a stale dep exits 0: $out" "$rc"
  assert_eq "stale dep bundled and flattened" "lib" "$(cat "$opt_dir/lib/libbar.so.1" 2>/dev/null)"
  assert_eq "stale dep dropped from system-deps" "" "$(cat "$opt_dir/.lapt/system-deps" 2>/dev/null)"

  teardown_fakes
}

test_fix_mixed_only_stale_one_is_fetched() {
  setup_fakes
  fixture_installed_pkg foo 1.0 "libbar 2.0"$'\n'"databar 3.0"$'\n'
  printf '%s' "3.0" > "$FIXTURE_DIR/dpkg_status/databar"
  local opt_dir="$HOME/.lapt/opt/foo"
  printf -- '-rw-r--r-- root/root 4 2024-01-01 00:00 ./usr/lib/libbar.so.1\n' \
    > "$FIXTURE_DIR/deb_contents/libbar_2.0"
  mkdir -p "$FIXTURE_DIR/extract/libbar_2.0/usr/lib"
  printf 'lib' > "$FIXTURE_DIR/extract/libbar_2.0/usr/lib/libbar.so.1"

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" fix foo 2>&1)
  rc=$?

  assert_exit0 "mixed fix exits 0: $out" "$rc"
  assert_eq "stale dep bundled" "lib" "$(cat "$opt_dir/lib/libbar.so.1" 2>/dev/null)"
  assert_eq "still-satisfied dep survives in system-deps" "databar 3.0" "$(cat "$opt_dir/.lapt/system-deps")"
  if [[ -e "$HOME/.lapt/cache/databar_3.0" ]]; then
    printf 'FAIL: %s\n  expected still-satisfied databar never fetched, found a cache entry\n' "still-satisfied dep is never fetched"
    fail=1
  fi

  teardown_fakes
}

# the stale dep's cache entry ships a file at a path that collides with
# something already in opt/foo/ (here: the top-level package's own bin/foo) --
# bundle_manifest's existing collision check must fire against opt_dir's real
# on-disk content, not just among newly-added members, since fix operates on
# the real tree directly (ADR-0007's "Implementation note")
test_fix_stale_dep_collision_aborts() {
  setup_fakes
  fixture_installed_pkg foo 1.0 "clash 9.0"$'\n'
  local opt_dir="$HOME/.lapt/opt/foo"
  printf -- '-rwxr-xr-x root/root 4 2024-01-01 00:00 ./usr/bin/foo\n' \
    > "$FIXTURE_DIR/deb_contents/clash_9.0"
  mkdir -p "$FIXTURE_DIR/extract/clash_9.0/usr/bin"
  printf 'clash' > "$FIXTURE_DIR/extract/clash_9.0/usr/bin/foo"

  local rc
  PATH="$FAKEBIN:$PATH" "$LAPT" fix foo >/dev/null 2>&1
  rc=$?

  if [[ $rc -eq 0 ]]; then
    printf 'FAIL: %s\n  expected nonzero exit, got 0\n' "stale dep collision aborts"
    fail=1
  fi
  assert_eq "existing bin/foo untouched by the collision" "real" "$(cat "$opt_dir/bin/foo" 2>/dev/null)"

  teardown_fakes
}

# foo was installed fully system-satisfied: no wrapper at all, own bin/foo
# exposed straight (this is what fixture_installed_pkg already sets up: a
# plain, unwrapped bin/foo). Its one dep (libbar) goes stale and gets bundled
# by fix, contributing lib/ -- this newly triggers a wrapper, same shape as
# install's test_lib_dep_triggers_wrapper.
test_fix_newly_triggers_wrapper() {
  setup_fakes
  fixture_installed_pkg foo 1.0 "libbar 2.0"$'\n'
  local opt_dir="$HOME/.lapt/opt/foo"
  printf -- '-rw-r--r-- root/root 4 2024-01-01 00:00 ./usr/lib/libbar.so.1\n' \
    > "$FIXTURE_DIR/deb_contents/libbar_2.0"
  mkdir -p "$FIXTURE_DIR/extract/libbar_2.0/usr/lib"
  printf 'lib' > "$FIXTURE_DIR/extract/libbar_2.0/usr/lib/libbar.so.1"

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" fix foo 2>&1)
  rc=$?

  assert_exit0 "wrapper-triggering fix exits 0: $out" "$rc"
  assert_eq "real binary moved aside" "real" "$(cat "$opt_dir/bin/foo.real" 2>/dev/null)"
  assert_eq "wrapper written at the exposed path" \
    "$(printf '#!/bin/sh\nexport LD_LIBRARY_PATH="%s:$LD_LIBRARY_PATH"\nexec "%s" "$@"' "$opt_dir/lib" "$opt_dir/bin/foo.real")" \
    "$(cat "$opt_dir/bin/foo" 2>/dev/null)"

  teardown_fakes
}

# foo already had a wrapper at install time (fixture below hand-builds that
# shape: bin/foo is the wrapper, bin/foo.real is the real binary, lib/ already
# has one bundled runtime lib). A second, unrelated dep (databar, a plain
# usr/share file) goes stale and fix bundles it. The already-existing wrapper
# must be left completely alone -- wrap_top_level_bins unconditionally mv's
# bin/foo -> bin/foo.real, so calling it again here would clobber foo.real
# with the wrapper script itself.
test_fix_does_not_retouch_existing_wrapper() {
  setup_fakes
  fixture_installed_pkg foo 1.0 "databar 3.0"$'\n'
  local opt_dir="$HOME/.lapt/opt/foo"
  mkdir -p "$opt_dir/lib"
  printf 'lib' > "$opt_dir/lib/libbar.so.1"
  mv "$opt_dir/bin/foo" "$opt_dir/bin/foo.real"
  printf '#!/bin/sh\nexport LD_LIBRARY_PATH="%s:$LD_LIBRARY_PATH"\nexec "%s" "$@"' \
    "$opt_dir/lib" "$opt_dir/bin/foo.real" > "$opt_dir/bin/foo"
  chmod +x "$opt_dir/bin/foo"

  printf -- '-rw-r--r-- root/root 4 2024-01-01 00:00 ./usr/share/databar/data.txt\n' \
    > "$FIXTURE_DIR/deb_contents/databar_3.0"
  mkdir -p "$FIXTURE_DIR/extract/databar_3.0/usr/share/databar"
  printf 'data' > "$FIXTURE_DIR/extract/databar_3.0/usr/share/databar/data.txt"

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" fix foo 2>&1)
  rc=$?

  assert_exit0 "fix beside an existing wrapper exits 0: $out" "$rc"
  assert_eq "existing wrapper untouched" \
    "$(printf '#!/bin/sh\nexport LD_LIBRARY_PATH="%s:$LD_LIBRARY_PATH"\nexec "%s" "$@"' "$opt_dir/lib" "$opt_dir/bin/foo.real")" \
    "$(cat "$opt_dir/bin/foo" 2>/dev/null)"
  assert_eq "real binary still intact, not clobbered" "real" "$(cat "$opt_dir/bin/foo.real" 2>/dev/null)"
  assert_eq "new dep bundled alongside" "data" "$(cat "$opt_dir/share/databar/data.txt" 2>/dev/null)"

  teardown_fakes
}

test_fix_on_uninstalled_pkg_errors
test_fix_all_deps_still_satisfied_is_noop
test_fix_stale_dep_is_fetched_and_bundled
test_fix_mixed_only_stale_one_is_fetched
test_fix_stale_dep_collision_aborts
test_fix_newly_triggers_wrapper
test_fix_does_not_retouch_existing_wrapper
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
