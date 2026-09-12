#!/usr/bin/env bash
# Subprocess tests for bin/lapt, seam: `lapt install <pkg>` only.
# bin/lapt is a real executable (not sourced), so the seam is running it as a
# subprocess against a temp $HOME, with fake apt-get/apt-cache/dpkg/dpkg-deb
# injected ahead of the real ones on PATH -- same FIXTURE_DIR-per-name(/version)
# keying convention as test_cache_ensure.sh and test_apt_is_system_satisfied.sh,
# just merged into one set of fakes since cmd_install exercises all of them.
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
  mkdir -p "$FIXTURE_DIR"/{closure,dpkg_status,candidate,deb_contents,extract}
  export HOME; HOME=$(mktemp -d)

  cat > "$FAKEBIN/apt-cache" <<'EOF'
#!/usr/bin/env bash
case $1 in
  depends)
    # depends --recurse --no-recommends ... <pkg> -- last arg is the pkg name
    cat "$FIXTURE_DIR/closure/${*: -1}" 2>/dev/null
    ;;
  policy)
    v=$(cat "$FIXTURE_DIR/candidate/$2" 2>/dev/null) || exit 0
    echo "$2:"
    echo "  Candidate: $v"
    ;;
esac
EOF
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
  --compare-versions)
    exec /usr/bin/dpkg "$@"
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
  unset FIXTURE_DIR HOME FIXTURE_KEY
}

# fixture helper: a package with no dependencies (closure output = just its own
# name, no Depends: lines) and its own usr/bin/<name>, so it's cache_ensure-able
fixture_leaf_pkg() {
  local name=$1 version=$2
  printf '%s\n' "$name" > "$FIXTURE_DIR/closure/$name"
  printf '%s' "$version" > "$FIXTURE_DIR/candidate/$name"
  printf -- '-rwxr-xr-x root/root 4 2024-01-01 00:00 ./usr/bin/%s\n' "$name" \
    > "$FIXTURE_DIR/deb_contents/${name}_${version}"
  mkdir -p "$FIXTURE_DIR/extract/${name}_${version}/usr/bin"
  printf 'real' > "$FIXTURE_DIR/extract/${name}_${version}/usr/bin/$name"
}

# opt/<pkg> already exists: no-op, exit 0, existing tree untouched
test_already_installed_is_noop() {
  setup_fakes
  local opt_dir="$HOME/.lapt/opt/foo"
  mkdir -p "$opt_dir"
  printf 'untouched' > "$opt_dir/marker"

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" install foo 2>&1)
  rc=$?
  assert_exit0 "already-installed no-op exits 0" "$rc"
  assert_eq "existing opt/ untouched" "untouched" "$(cat "$opt_dir/marker")"
  case $out in
    *"already installed"*) ;;
    *) printf 'FAIL: %s\n  expected notice mentioning "already installed", got: %s\n' "already-installed notice" "$out"; fail=1 ;;
  esac

  teardown_fakes
}

# pkg not opt-installed but already present via the system package manager:
# no-op notice, exit 0, nothing created under opt/
test_system_installed_is_noop() {
  setup_fakes
  printf '%s' "9.0" > "$FIXTURE_DIR/dpkg_status/foo"

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" install foo 2>&1)
  rc=$?
  assert_exit0 "system-installed no-op exits 0" "$rc"
  if [[ -e "$HOME/.lapt/opt/foo" ]]; then
    printf 'FAIL: %s\n  expected no opt/foo, found one\n' "system-installed creates nothing"
    fail=1
  fi
  case $out in
    *"already installed"*) ;;
    *) printf 'FAIL: %s\n  expected notice mentioning "already installed", got: %s\n' "system-installed notice" "$out"; fail=1 ;;
  esac

  teardown_fakes
}

# top-level package has no own usr/bin (only usr/lib + a pkgconfig file):
# install succeeds anyway (ADR-0012 drops the old hard-abort), and the .pc
# file is rewritten to point at opt/<pkg> (rewrite_pc is now unconditional
# for install, same mechanism vendor already used)
test_library_only_install_succeeds_and_rewrites_pc() {
  setup_fakes
  printf '%s\n' "foo" > "$FIXTURE_DIR/closure/foo"
  printf '%s' "1.0" > "$FIXTURE_DIR/candidate/foo"
  printf -- '-rw-r--r-- root/root 4 2024-01-01 00:00 ./usr/lib/libfoo.so.1\n-rw-r--r-- root/root 4 2024-01-01 00:00 ./usr/lib/pkgconfig/foo.pc\n' \
    > "$FIXTURE_DIR/deb_contents/foo_1.0"
  mkdir -p "$FIXTURE_DIR/extract/foo_1.0/usr/lib/pkgconfig"
  printf 'lib' > "$FIXTURE_DIR/extract/foo_1.0/usr/lib/libfoo.so.1"
  printf 'prefix=/usr\nlibdir=${prefix}/lib\nincludedir=${prefix}/include\n\nName: foo\n' \
    > "$FIXTURE_DIR/extract/foo_1.0/usr/lib/pkgconfig/foo.pc"

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" install foo 2>&1)
  rc=$?
  local opt_dir="$HOME/.lapt/opt/foo"

  assert_exit0 "library-only install exits 0: $out" "$rc"
  assert_eq "lib hardlinked into opt/" "lib" "$(cat "$opt_dir/lib/libfoo.so.1" 2>/dev/null)"
  assert_eq ".pc prefix rewritten to opt_dir" "prefix=$opt_dir" "$(sed -n '1p' "$opt_dir/lib/pkgconfig/foo.pc" 2>/dev/null)"
  assert_eq ".pc libdir rewritten to opt_dir/lib" "libdir=$opt_dir/lib" "$(sed -n '2p' "$opt_dir/lib/pkgconfig/foo.pc" 2>/dev/null)"
  assert_eq "version recorded" "version=1.0" "$(sed -n '1p' "$opt_dir/.lapt/version" 2>/dev/null)"

  teardown_fakes
}

# happy path: single pkg, empty closure (no deps), own usr/bin, no wrapper
# needed (no lib/, no foreign bin/) -- full assemble
test_install_happy_path_no_deps() {
  setup_fakes
  fixture_leaf_pkg foo 1.0

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" install foo 2>&1)
  rc=$?
  local opt_dir="$HOME/.lapt/opt/foo"

  assert_exit0 "happy path exits 0" "$rc"
  assert_eq "binary hardlinked into opt/" "real" "$(cat "$opt_dir/bin/foo" 2>/dev/null)"
  assert_eq "no wrapper generated" "" "$(find "$opt_dir" -name '*.wrap' 2>/dev/null)"
  assert_eq "version recorded" "version=1.0" "$(sed -n '1p' "$opt_dir/.lapt/version" 2>/dev/null)"
  assert_eq "exposure list records bin/foo as exposed" "bin/foo" "$(cat "$opt_dir/.lapt/exposed" 2>/dev/null)"
  assert_eq "symlink exposed into LAPT_HOME/bin" "$opt_dir/bin/foo" "$(readlink -f "$HOME/.lapt/bin/foo" 2>/dev/null)"

  teardown_fakes
}

# non-top-level dep already system-satisfied: skipped entirely (not fetched,
# not bundled into opt/), recorded to .lapt/system-deps
test_system_satisfied_dep_is_skipped() {
  setup_fakes
  fixture_leaf_pkg foo 1.0
  printf 'foo\n  Depends: libbar\nlibbar\n' > "$FIXTURE_DIR/closure/foo"
  printf '%s' "2.0" > "$FIXTURE_DIR/candidate/libbar"
  printf '%s' "2.0" > "$FIXTURE_DIR/dpkg_status/libbar"

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" install foo 2>&1)
  rc=$?
  local opt_dir="$HOME/.lapt/opt/foo"

  assert_exit0 "system-satisfied dep install exits 0" "$rc"
  if [[ -e "$HOME/.lapt/cache/libbar_2.0" ]]; then
    printf 'FAIL: %s\n  expected libbar never fetched/cached, found a cache entry\n' "system-satisfied dep is never fetched"
    fail=1
  fi
  assert_eq "system-satisfied dep recorded" "libbar 2.0" "$(cat "$opt_dir/.lapt/system-deps" 2>/dev/null)"

  teardown_fakes
}

# non-top-level dep not system-satisfied (not installed anywhere): fetched
# and bundled into opt/<pkg>/, flattened (usr/ stripped), NOT recorded to
# .lapt/system-deps (it's actually bundled, not skipped). This dep only
# contributes a share/ file -- no lib/, no foreign bin/ -- so no wrapper is
# triggered (wrapper generation is a later slice).
test_unsatisfied_dep_is_fetched_and_bundled() {
  setup_fakes
  fixture_leaf_pkg foo 1.0
  printf 'foo\n  Depends: databar\ndatabar\n' > "$FIXTURE_DIR/closure/foo"
  printf '%s' "3.0" > "$FIXTURE_DIR/candidate/databar"
  printf -- '-rw-r--r-- root/root 4 2024-01-01 00:00 ./usr/share/databar/data.txt\n' \
    > "$FIXTURE_DIR/deb_contents/databar_3.0"
  mkdir -p "$FIXTURE_DIR/extract/databar_3.0/usr/share/databar"
  printf 'data' > "$FIXTURE_DIR/extract/databar_3.0/usr/share/databar/data.txt"

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" install foo 2>&1)
  rc=$?
  local opt_dir="$HOME/.lapt/opt/foo"

  assert_exit0 "unsatisfied dep install exits 0: $out" "$rc"
  assert_eq "dep content bundled and flattened" "data" "$(cat "$opt_dir/share/databar/data.txt" 2>/dev/null)"
  assert_eq "bundled dep not recorded as system-satisfied" "" "$(cat "$opt_dir/.lapt/system-deps" 2>/dev/null)"

  teardown_fakes
}

# non-top-level dep contributes a runtime lib/: a wrapper is generated at
# opt/<pkg>/bin/<pkg> (the exposed path), the real binary moves to
# opt/<pkg>/bin/<pkg>.real, and the wrapper prepends LD_LIBRARY_PATH
test_lib_dep_triggers_wrapper() {
  setup_fakes
  fixture_leaf_pkg foo 1.0
  printf 'foo\n  Depends: libbar\nlibbar\n' > "$FIXTURE_DIR/closure/foo"
  printf '%s' "3.0" > "$FIXTURE_DIR/candidate/libbar"
  printf -- '-rw-r--r-- root/root 4 2024-01-01 00:00 ./usr/lib/libbar.so.1\n' \
    > "$FIXTURE_DIR/deb_contents/libbar_3.0"
  mkdir -p "$FIXTURE_DIR/extract/libbar_3.0/usr/lib"
  printf 'lib' > "$FIXTURE_DIR/extract/libbar_3.0/usr/lib/libbar.so.1"

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" install foo 2>&1)
  rc=$?
  local opt_dir="$HOME/.lapt/opt/foo"

  assert_exit0 "wrapper-needed install exits 0: $out" "$rc"
  assert_eq "real binary moved aside" "real" "$(cat "$opt_dir/bin/foo.real" 2>/dev/null)"
  assert_eq "wrapper written at the exposed path" \
    "$(printf '#!/bin/sh\nexport LD_LIBRARY_PATH="%s:$LD_LIBRARY_PATH"\nexec "%s" "$@"' "$opt_dir/lib" "$opt_dir/bin/foo.real")" \
    "$(cat "$opt_dir/bin/foo" 2>/dev/null)"
  assert_eq "exposed symlink resolves through the wrapper" "$opt_dir/bin/foo" "$(readlink -f "$HOME/.lapt/bin/foo" 2>/dev/null)"

  teardown_fakes
}

# non-top-level dep contributes its own bin/ (a foreign executable, not the
# top-level package's): triggers a wrapper that prepends PATH instead of
# LD_LIBRARY_PATH, so the top-level binary can still exec its dependency's
# tool internally (ADR-0004)
test_foreign_bin_dep_triggers_wrapper() {
  setup_fakes
  fixture_leaf_pkg foo 1.0
  printf 'foo\n  Depends: helper\nhelper\n' > "$FIXTURE_DIR/closure/foo"
  printf '%s' "5.0" > "$FIXTURE_DIR/candidate/helper"
  printf -- '-rwxr-xr-x root/root 4 2024-01-01 00:00 ./usr/bin/helper\n' \
    > "$FIXTURE_DIR/deb_contents/helper_5.0"
  mkdir -p "$FIXTURE_DIR/extract/helper_5.0/usr/bin"
  printf 'helper' > "$FIXTURE_DIR/extract/helper_5.0/usr/bin/helper"

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" install foo 2>&1)
  rc=$?
  local opt_dir="$HOME/.lapt/opt/foo"

  assert_exit0 "foreign-bin install exits 0: $out" "$rc"
  assert_eq "dependency's own binary bundled, not exposed" "helper" "$(cat "$opt_dir/bin/helper" 2>/dev/null)"
  assert_eq "wrapper prepends PATH, not LD_LIBRARY_PATH" \
    "$(printf '#!/bin/sh\nexport PATH="%s:$PATH"\nexec "%s" "$@"' "$opt_dir/bin" "$opt_dir/bin/foo.real")" \
    "$(cat "$opt_dir/bin/foo" 2>/dev/null)"
  if [[ -e "$HOME/.lapt/bin/helper" ]]; then
    printf 'FAIL: %s\n  expected dependency binary never exposed, found a symlink\n' "dependency binary stays unexposed"
    fail=1
  fi

  teardown_fakes
}

# a failure partway through assemble (here: a bundle collision between the
# top-level package's own bin/foo and a dependency shipping the same path)
# must not leave opt/<pkg> behind at all -- otherwise the already-installed
# check would treat the botched install as permanently done, with no way to
# retry. No leftover scratch dir either.
test_partial_failure_leaves_no_opt_dir() {
  setup_fakes
  fixture_leaf_pkg foo 1.0
  printf 'foo\n  Depends: clash\nclash\n' > "$FIXTURE_DIR/closure/foo"
  printf '%s' "9.0" > "$FIXTURE_DIR/candidate/clash"
  printf -- '-rwxr-xr-x root/root 4 2024-01-01 00:00 ./usr/bin/foo\n' \
    > "$FIXTURE_DIR/deb_contents/clash_9.0"
  mkdir -p "$FIXTURE_DIR/extract/clash_9.0/usr/bin"
  printf 'clash' > "$FIXTURE_DIR/extract/clash_9.0/usr/bin/foo"

  local rc
  PATH="$FAKEBIN:$PATH" "$LAPT" install foo >/dev/null 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    printf 'FAIL: %s\n  expected nonzero exit, got 0\n' "collision aborts"
    fail=1
  fi
  if [[ -e "$HOME/.lapt/opt/foo" ]]; then
    printf 'FAIL: %s\n  expected no opt/foo left behind, found one\n' "partial failure leaves no opt dir"
    fail=1
  fi
  if compgen -G "$HOME/.lapt/opt/.tmp.*" >/dev/null 2>&1; then
    printf 'FAIL: %s\n  expected no leftover scratch dir\n' "partial failure leaves no scratch dir"
    fail=1
  fi

  teardown_fakes
}

# exposure runs after the mv, so a collision there (something already sitting
# at the exposed path, e.g. a stale symlink from a prior botched install)
# must NOT unwind or fail the install -- opt/<pkg> is already a complete,
# valid, removable package by that point. install exits 0, warns, and points
# at `lapt expose <pkg>` to retry once the collision is cleared.
test_exposure_collision_after_mv_keeps_opt_dir() {
  setup_fakes
  fixture_leaf_pkg foo 1.0
  mkdir -p "$HOME/.lapt/bin"
  : > "$HOME/.lapt/bin/foo"

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" install foo 2>&1)
  rc=$?
  local opt_dir="$HOME/.lapt/opt/foo"

  assert_exit0 "exposure collision does not fail the install" "$rc"
  assert_eq "package content still installed" "real" "$(cat "$opt_dir/bin/foo" 2>/dev/null)"
  assert_eq "version still recorded" "version=1.0" "$(sed -n '1p' "$opt_dir/.lapt/version" 2>/dev/null)"
  assert_eq "collided row never recorded (nothing was linked)" "" "$(cat "$opt_dir/.lapt/exposed" 2>/dev/null)"
  case $out in
    *"lapt expose foo"*) ;;
    *) printf 'FAIL: %s\n  expected notice mentioning "lapt expose foo", got: %s\n' "retry hint" "$out"; fail=1 ;;
  esac

  teardown_fakes
}

# multiple packages named, all succeed: each gets its own opt/<pkg>, exit 0
test_multiple_pkgs_all_succeed() {
  setup_fakes
  fixture_leaf_pkg foo 1.0
  fixture_leaf_pkg bar 2.0

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" install foo bar 2>&1)
  rc=$?

  assert_exit0 "multi-pkg success exits 0: $out" "$rc"
  assert_eq "foo installed" "real" "$(cat "$HOME/.lapt/opt/foo/bin/foo" 2>/dev/null)"
  assert_eq "bar installed" "real" "$(cat "$HOME/.lapt/opt/bar/bin/bar" 2>/dev/null)"

  teardown_fakes
}

# one of several named packages has no apt candidate: the others still get
# installed (best-effort), but the overall exit is nonzero and the failure
# names the broken package
test_multiple_pkgs_partial_failure_still_installs_rest() {
  setup_fakes
  fixture_leaf_pkg foo 1.0
  fixture_leaf_pkg bar 2.0
  # no candidate fixture for "broken" -> apt-cache policy prints nothing

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" install foo broken bar 2>&1)
  rc=$?

  if [[ $rc -eq 0 ]]; then
    printf 'FAIL: %s\n  expected nonzero exit, got 0\n' "partial failure is reported nonzero"
    fail=1
  fi
  assert_eq "foo still installed" "real" "$(cat "$HOME/.lapt/opt/foo/bin/foo" 2>/dev/null)"
  assert_eq "bar still installed" "real" "$(cat "$HOME/.lapt/opt/bar/bin/bar" 2>/dev/null)"
  case $out in
    *broken*) ;;
    *) printf 'FAIL: %s\n  expected failure output naming broken, got: %s\n' "failed pkg named in output" "$out"; fail=1 ;;
  esac

  teardown_fakes
}

test_already_installed_is_noop
test_system_installed_is_noop
test_library_only_install_succeeds_and_rewrites_pc
test_install_happy_path_no_deps
test_system_satisfied_dep_is_skipped
test_unsatisfied_dep_is_fetched_and_bundled
test_lib_dep_triggers_wrapper
test_foreign_bin_dep_triggers_wrapper
test_partial_failure_leaves_no_opt_dir
test_exposure_collision_after_mv_keeps_opt_dir
test_multiple_pkgs_all_succeed
test_multiple_pkgs_partial_failure_still_installs_rest
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
