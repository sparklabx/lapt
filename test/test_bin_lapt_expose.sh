#!/usr/bin/env bash
# Subprocess tests for bin/lapt, seam: `lapt expose <pkg>` only.
# Same fake-apt-tooling harness as test_bin_lapt_install.sh (cmd_expose only
# needs apt-cache/dpkg-deb, to rebuild the manifest from the cache entry, but
# an install always has to happen first to get an installed pkg to expose).
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

fixture_leaf_pkg() {
  local name=$1 version=$2
  printf '%s\n' "$name" > "$FIXTURE_DIR/closure/$name"
  printf '%s' "$version" > "$FIXTURE_DIR/candidate/$name"
  printf -- '-rwxr-xr-x root/root 4 2024-01-01 00:00 ./usr/bin/%s\n' "$name" \
    > "$FIXTURE_DIR/deb_contents/${name}_${version}"
  mkdir -p "$FIXTURE_DIR/extract/${name}_${version}/usr/bin"
  printf 'real' > "$FIXTURE_DIR/extract/${name}_${version}/usr/bin/$name"
}

# not installed at all: hard error, exit nonzero
test_expose_on_uninstalled_pkg_errors() {
  setup_fakes

  local rc
  PATH="$FAKEBIN:$PATH" "$LAPT" expose foo >/dev/null 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    printf 'FAIL: %s\n  expected nonzero exit, got 0\n' "expose on uninstalled pkg errors"
    fail=1
  fi

  teardown_fakes
}

# a collision at install time leaves bin/foo unexposed (=0); once the user
# clears the collision, `lapt expose foo` finishes exposing it and updates
# .lapt/exposed accordingly
test_expose_retries_after_user_clears_collision() {
  setup_fakes
  fixture_leaf_pkg foo 1.0
  mkdir -p "$HOME/.lapt/bin"
  : > "$HOME/.lapt/bin/foo"

  PATH="$FAKEBIN:$PATH" "$LAPT" install foo >/dev/null 2>&1
  local opt_dir="$HOME/.lapt/opt/foo"
  assert_eq "not yet exposed (collision, nothing recorded)" "" "$(cat "$opt_dir/.lapt/exposed" 2>/dev/null)"

  rm -f "$HOME/.lapt/bin/foo"
  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" expose foo 2>&1)
  rc=$?

  assert_exit0 "expose retry exits 0" "$rc"
  assert_eq "now exposed" "bin/foo" "$(cat "$opt_dir/.lapt/exposed" 2>/dev/null)"
  assert_eq "symlink now created" "$opt_dir/bin/foo" "$(readlink -f "$HOME/.lapt/bin/foo" 2>/dev/null)"

  teardown_fakes
}

# re-running expose on a pkg that's already fully exposed is a harmless no-op
test_expose_on_already_exposed_pkg_is_noop() {
  setup_fakes
  fixture_leaf_pkg foo 1.0
  PATH="$FAKEBIN:$PATH" "$LAPT" install foo >/dev/null 2>&1
  local opt_dir="$HOME/.lapt/opt/foo"

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" "$LAPT" expose foo 2>&1)
  rc=$?

  assert_exit0 "re-expose already-good pkg exits 0" "$rc"
  assert_eq "still exposed" "bin/foo" "$(cat "$opt_dir/.lapt/exposed" 2>/dev/null)"
  assert_eq "symlink unchanged" "$opt_dir/bin/foo" "$(readlink -f "$HOME/.lapt/bin/foo" 2>/dev/null)"

  teardown_fakes
}

test_expose_on_uninstalled_pkg_errors
test_expose_retries_after_user_clears_collision
test_expose_on_already_exposed_pkg_is_noop
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
