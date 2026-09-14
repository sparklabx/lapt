#!/usr/bin/env bash
# Vertical-slice tests for lib/cache.sh, seam: lapt::cache_ensure only.
# apt-get/dpkg-deb/dpkg are host/network state, so tests inject fake scripts
# ahead of the real ones on PATH, keyed by a plain FIXTURE_KEY env var the
# fakes read directly (test doubles, no need to mimic real filename shapes).
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/lib/cache.sh"

fail=0
assert_eq() {
  local desc=$1 expected=$2 actual=$3
  if [[ $expected != "$actual" ]]; then
    printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' "$desc" "$expected" "$actual"
    fail=1
  fi
}

FAKEBIN=""
setup_fakes() {
  FAKEBIN=$(mktemp -d)
  export LAPT_HOME; LAPT_HOME=$(mktemp -d)
  export FIXTURE_DIR; FIXTURE_DIR=$(mktemp -d)
  mkdir -p "$FIXTURE_DIR/extract"

  cat > "$FAKEBIN/apt-get" <<'EOF'
#!/usr/bin/env bash
[[ $1 == download ]] || exec /usr/bin/apt-get "$@"
: > pkg.deb
EOF
  cat > "$FAKEBIN/dpkg" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == -x ]]; then
  mkdir -p "$3"
  cp -r "$FIXTURE_DIR/extract/$FIXTURE_KEY/." "$3/"
  exit 0
fi
exec /usr/bin/dpkg "$@"
EOF
  chmod +x "$FAKEBIN/apt-get" "$FAKEBIN/dpkg"
}
teardown_fakes() {
  rm -rf "$FAKEBIN" "$LAPT_HOME" "$FIXTURE_DIR"
  unset LAPT_HOME FIXTURE_DIR FIXTURE_KEY
}

# entry already cached: no-op, existing content untouched, no external tools invoked
test_already_cached_is_noop() {
  setup_fakes
  local entry; entry=$(lapt::cache_entry_path foo 1.0)
  mkdir -p "$entry/usr/bin"
  printf 'already here' > "$entry/usr/bin/foo"

  local rc
  PATH="$FAKEBIN:$PATH" lapt::cache_ensure foo 1.0
  rc=$?
  assert_eq "no-op exits 0" "0" "$rc"
  assert_eq "existing content untouched" "already here" "$(cat "$entry/usr/bin/foo")"

  teardown_fakes
}

# fresh entry, all files under usr/: downloads, extracts into the cache entry path
test_fresh_entry_extracted() {
  setup_fakes
  export FIXTURE_KEY=foo_1.0
  printf -- '-rwxr-xr-x root/root 4 2024-01-01 00:00 ./usr/bin/foo\n' \
    > "$FIXTURE_DIR/deb_contents/$FIXTURE_KEY"
  mkdir -p "$FIXTURE_DIR/extract/$FIXTURE_KEY/usr/bin"
  printf 'real' > "$FIXTURE_DIR/extract/$FIXTURE_KEY/usr/bin/foo"

  local rc entry
  PATH="$FAKEBIN:$PATH" lapt::cache_ensure foo 1.0
  rc=$?
  entry=$(lapt::cache_entry_path foo 1.0)
  assert_eq "extract exits 0" "0" "$rc"
  assert_eq "extracted content present" "real" "$(cat "$entry/usr/bin/foo" 2>/dev/null)"

  teardown_fakes
}

# a file outside usr/ (e.g. /etc, /bin at root): fetched and extracted like
# any other package -- lapt no longer restricts installable packages to a
# usr/-only layout, so cache_ensure does no scope check at all any more.
test_file_outside_usr_is_extracted() {
  setup_fakes
  export FIXTURE_KEY=bad_1.0
  mkdir -p "$FIXTURE_DIR/extract/$FIXTURE_KEY/etc"
  printf 'x' > "$FIXTURE_DIR/extract/$FIXTURE_KEY/etc/foo"

  local rc entry
  PATH="$FAKEBIN:$PATH" lapt::cache_ensure bad 1.0
  rc=$?
  entry=$(lapt::cache_entry_path bad 1.0)
  assert_eq "extract exits 0" "0" "$rc"
  assert_eq "outside-usr content present verbatim" "x" "$(cat "$entry/etc/foo" 2>/dev/null)"

  teardown_fakes
}

test_already_cached_is_noop
test_fresh_entry_extracted
test_file_outside_usr_is_extracted
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
