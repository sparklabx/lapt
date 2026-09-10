#!/usr/bin/env bash
# Vertical-slice tests for lib/apt.sh, seam: lapt::is_system_satisfied only.
# dpkg -s and apt-cache policy are host state, so tests inject fake `dpkg`/
# `apt-cache` scripts ahead of the real ones on PATH; `--compare-versions`
# passes through to the real dpkg (pure, deterministic, no package-db read).
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/lib/apt.sh"

fail=0
assert_eq() {
  local desc=$1 expected=$2 actual=$3
  if [[ $expected != "$actual" ]]; then
    printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' "$desc" "$expected" "$actual"
    fail=1
  fi
}

# fixture: dpkg_status["name"]="installed-version" (unset = not installed),
# candidate["name"]="candidate-version" (unset = unknown to apt-cache)
FAKEBIN=""
declare -gA DPKG_STATUS CANDIDATE
setup_fakes() {
  DPKG_STATUS=() CANDIDATE=()
  FAKEBIN=$(mktemp -d)
  cat > "$FAKEBIN/dpkg" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == -s ]]; then
  v=$(cat "$FIXTURE_DIR/dpkg_status/$2" 2>/dev/null) || { echo "dpkg-query: package '$2' is not installed" >&2; exit 1; }
  echo "Package: $2"
  echo "Status: install ok installed"
  echo "Version: $v"
  exit 0
fi
exec /usr/bin/dpkg "$@"
EOF
  cat > "$FAKEBIN/apt-cache" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == policy ]]; then
  v=$(cat "$FIXTURE_DIR/candidate/$2" 2>/dev/null) || exit 0
  echo "$2:"
  echo "  Candidate: $v"
  exit 0
fi
exec /usr/bin/apt-cache "$@"
EOF
  chmod +x "$FAKEBIN/dpkg" "$FAKEBIN/apt-cache"
  export FIXTURE_DIR=$(mktemp -d)
  mkdir -p "$FIXTURE_DIR/dpkg_status" "$FIXTURE_DIR/candidate"
}
fixture_installed() { printf '%s' "$2" > "$FIXTURE_DIR/dpkg_status/$1"; }
fixture_candidate() { printf '%s' "$2" > "$FIXTURE_DIR/candidate/$1"; }
teardown_fakes() { rm -rf "$FAKEBIN" "$FIXTURE_DIR"; unset FIXTURE_DIR; }

# a single (non-group) name, installed at exactly the apt candidate version: satisfied
test_single_name_satisfied_prints_name_and_version() {
  setup_fakes
  fixture_installed libfoo 2.0
  fixture_candidate libfoo 2.0

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" lapt::is_system_satisfied libfoo)
  rc=$?
  assert_eq "satisfied prints name+version" "libfoo 2.0" "$out"
  assert_eq "satisfied exits 0" "0" "$rc"

  teardown_fakes
}

# not installed at all: not satisfied, no output, nonzero exit
test_not_installed_is_unsatisfied() {
  setup_fakes
  fixture_candidate libfoo 2.0

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" lapt::is_system_satisfied libfoo)
  rc=$?
  assert_eq "not installed: no output" "" "$out"
  if [[ $rc -eq 0 ]]; then
    printf 'FAIL: %s\n  expected nonzero exit, got 0\n' "not installed exits nonzero"
    fail=1
  fi

  teardown_fakes
}

# installed, but older than apt's current candidate: not satisfied (ADR-0007
# efficiency choice, Option 2 -- see conversation: proxy for a real version
# floor we have no per-edge constraint for)
test_installed_older_than_candidate_is_unsatisfied() {
  setup_fakes
  fixture_installed libfoo 1.0
  fixture_candidate libfoo 2.0

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" lapt::is_system_satisfied libfoo)
  rc=$?
  assert_eq "stale installed version: no output" "" "$out"
  if [[ $rc -eq 0 ]]; then
    printf 'FAIL: %s\n  expected nonzero exit, got 0\n' "stale version exits nonzero"
    fail=1
  fi

  teardown_fakes
}

# OR-group: first alternative not installed, second is installed and
# satisfying -- group counts as satisfied via the second (ADR-0010 any-of rule)
test_or_group_satisfied_by_non_first_alternative() {
  setup_fakes
  fixture_candidate debconf 1.5
  fixture_installed cdebconf 1.5
  fixture_candidate cdebconf 1.5

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" lapt::is_system_satisfied 'debconf|cdebconf')
  rc=$?
  assert_eq "non-first alternative satisfies the group" "cdebconf 1.5" "$out"
  assert_eq "group-satisfied exits 0" "0" "$rc"

  teardown_fakes
}

test_single_name_satisfied_prints_name_and_version
test_not_installed_is_unsatisfied
test_installed_older_than_candidate_is_unsatisfied
test_or_group_satisfied_by_non_first_alternative
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
