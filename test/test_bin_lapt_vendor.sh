#!/usr/bin/env bash
# Subprocess tests for bin/lapt, seam: `lapt vendor <target-dir> <pkg...>` only.
# Same fake apt-cache/dpkg/dpkg-deb/apt-get-on-PATH convention as
# test_bin_lapt_install.sh.
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
  export LAPT_CACHE_ROOT="$HOME/.local/share/lapt/cache"

  cat > "$FAKEBIN/apt-cache" <<'EOF'
#!/usr/bin/env bash
case $1 in
  depends)
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
  unset FIXTURE_DIR HOME LAPT_CACHE_ROOT
}

# fixture helper: a library-only package (no closure deps), a lib/ file and a
# pkgconfig .pc file whose prefix/libdir/includedir need rewriting at apply time
fixture_lib_pkg() {
  local name=$1 version=$2
  printf '%s\n' "$name" > "$FIXTURE_DIR/closure/$name"
  printf '%s' "$version" > "$FIXTURE_DIR/candidate/$name"
  printf -- '-rw-r--r-- root/root 4 2024-01-01 00:00 ./usr/lib/lib%s.so.1\n-rw-r--r-- root/root 4 2024-01-01 00:00 ./usr/lib/pkgconfig/%s.pc\n' \
    "$name" "$name" > "$FIXTURE_DIR/deb_contents/${name}_${version}"
  mkdir -p "$FIXTURE_DIR/extract/${name}_${version}/usr/lib/pkgconfig"
  printf 'lib' > "$FIXTURE_DIR/extract/${name}_${version}/usr/lib/lib${name}.so.1"
  printf 'prefix=/usr\nlibdir=${prefix}/lib\nincludedir=${prefix}/include\n\nName: %s\n' "$name" \
    > "$FIXTURE_DIR/extract/${name}_${version}/usr/lib/pkgconfig/${name}.pc"
}

# named package already system-satisfied: skipped entirely, notice printed,
# nothing hardlinked, no target-dir left behind
test_system_satisfied_named_pkg_is_skipped() {
  setup_fakes
  printf '%s' "1.0" > "$FIXTURE_DIR/dpkg_status/foo"
  local target_dir="$HOME/vendor"

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" vendor "$target_dir" foo 2>&1)
  rc=$?

  assert_exit0 "skip-all exits 0" "$rc"
  case $out in
    *"already installed"*) ;;
    *) printf 'FAIL: %s\n  expected notice mentioning "already installed", got: %s\n' "system-satisfied notice" "$out"; fail=1 ;;
  esac
  if [[ -e "$target_dir" ]]; then
    printf 'FAIL: %s\n  expected no target-dir created, found one\n' "skip-all creates nothing"
    fail=1
  fi

  teardown_fakes
}

# happy path: single library-only pkg, no deps -- lib/ hardlinked, .pc
# rewritten to point at target-dir (rewrite_pc=1, unlike install's 0)
test_vendor_happy_path_no_deps() {
  setup_fakes
  fixture_lib_pkg foo 1.0
  local target_dir="$HOME/vendor"

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" vendor "$target_dir" foo 2>&1)
  rc=$?

  assert_exit0 "happy path exits 0: $out" "$rc"
  assert_eq "lib hardlinked into target-dir" "lib" "$(cat "$target_dir/lib/libfoo.so.1" 2>/dev/null)"
  assert_eq ".pc prefix rewritten to target-dir" "prefix=$target_dir" "$(sed -n '1p' "$target_dir/lib/pkgconfig/foo.pc" 2>/dev/null)"
  assert_eq ".pc libdir rewritten to target-dir/lib" "libdir=$target_dir/lib" "$(sed -n '2p' "$target_dir/lib/pkgconfig/foo.pc" 2>/dev/null)"
  if [[ -e "$HOME/.local/share/lapt/opt/foo" ]]; then
    printf 'FAIL: %s\n  expected no opt/foo, vendor never touches opt/\n' "vendor never writes opt/"
    fail=1
  fi

  teardown_fakes
}

# a closure member that's system-satisfied is skipped (not fetched, not
# bundled), same as install's dependency skip -- no .lapt/system-deps
# equivalent exists for vendor, so nothing is recorded anywhere
test_system_satisfied_closure_member_is_skipped() {
  setup_fakes
  fixture_lib_pkg foo 1.0
  printf 'foo\n  Depends: libbar\nlibbar\n' > "$FIXTURE_DIR/closure/foo"
  printf '%s' "2.0" > "$FIXTURE_DIR/candidate/libbar"
  printf '%s' "2.0" > "$FIXTURE_DIR/dpkg_status/libbar"
  local target_dir="$HOME/vendor"

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" vendor "$target_dir" foo 2>&1)
  rc=$?

  assert_exit0 "system-satisfied closure member exits 0: $out" "$rc"
  if [[ -e "$HOME/.local/share/lapt/cache/libbar_2.0" ]]; then
    printf 'FAIL: %s\n  expected libbar never fetched/cached, found a cache entry\n' "system-satisfied member never fetched"
    fail=1
  fi

  teardown_fakes
}

# a closure member not system-satisfied is fetched and bundled into
# target-dir, flattened same as install
test_unsatisfied_closure_member_is_bundled() {
  setup_fakes
  fixture_lib_pkg foo 1.0
  printf 'foo\n  Depends: databar\ndatabar\n' > "$FIXTURE_DIR/closure/foo"
  printf '%s' "3.0" > "$FIXTURE_DIR/candidate/databar"
  printf -- '-rw-r--r-- root/root 4 2024-01-01 00:00 ./usr/include/databar.h\n' \
    > "$FIXTURE_DIR/deb_contents/databar_3.0"
  mkdir -p "$FIXTURE_DIR/extract/databar_3.0/usr/include"
  printf 'hdr' > "$FIXTURE_DIR/extract/databar_3.0/usr/include/databar.h"
  local target_dir="$HOME/vendor"

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" vendor "$target_dir" foo 2>&1)
  rc=$?

  assert_exit0 "unsatisfied closure member exits 0: $out" "$rc"
  assert_eq "header bundled and flattened" "hdr" "$(cat "$target_dir/include/databar.h" 2>/dev/null)"

  teardown_fakes
}

# two named packages sharing a closure member: the shared member is only
# bundled once, no false collision error (ADR-0003/0009)
test_shared_closure_member_across_named_pkgs_is_deduped() {
  setup_fakes
  fixture_lib_pkg foo 1.0
  fixture_lib_pkg baz 1.0
  printf 'foo\n  Depends: shared\nshared\n' > "$FIXTURE_DIR/closure/foo"
  printf 'baz\n  Depends: shared\nshared\n' > "$FIXTURE_DIR/closure/baz"
  printf '%s' "4.0" > "$FIXTURE_DIR/candidate/shared"
  printf -- '-rw-r--r-- root/root 4 2024-01-01 00:00 ./usr/include/shared.h\n' \
    > "$FIXTURE_DIR/deb_contents/shared_4.0"
  mkdir -p "$FIXTURE_DIR/extract/shared_4.0/usr/include"
  printf 'shared' > "$FIXTURE_DIR/extract/shared_4.0/usr/include/shared.h"
  local target_dir="$HOME/vendor"

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" vendor "$target_dir" foo baz 2>&1)
  rc=$?

  assert_exit0 "shared closure member across named pkgs exits 0: $out" "$rc"
  assert_eq "shared member bundled once" "shared" "$(cat "$target_dir/include/shared.h" 2>/dev/null)"
  assert_eq "both named pkgs' own libs bundled" "lib" "$(cat "$target_dir/lib/libbaz.so.1" 2>/dev/null)"

  teardown_fakes
}

# no packages named: usage error, nonzero exit
test_no_pkgs_named_errors() {
  setup_fakes
  local rc
  PATH="$FAKEBIN:$PATH" "$LAPT" vendor "$HOME/vendor" >/dev/null 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    printf 'FAIL: %s\n  expected nonzero exit, got 0\n' "no pkgs named errors"
    fail=1
  fi
  teardown_fakes
}

test_system_satisfied_named_pkg_is_skipped
test_vendor_happy_path_no_deps
test_system_satisfied_closure_member_is_skipped
test_unsatisfied_closure_member_is_bundled
test_shared_closure_member_across_named_pkgs_is_deduped
test_no_pkgs_named_errors
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
