#!/usr/bin/env bash
# Vertical-slice tests for lib/apt.sh, seam: lapt::pick_candidate only.
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

# fixture: candidate["name"]="candidate-version" (unset = unknown to apt-cache)
FAKEBIN=""
setup_fakes() {
  FAKEBIN=$(mktemp -d)
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
  chmod +x "$FAKEBIN/apt-cache"
  export FIXTURE_DIR=$(mktemp -d)
  mkdir -p "$FIXTURE_DIR/candidate"
}
fixture_candidate() { printf '%s' "$2" > "$FIXTURE_DIR/candidate/$1"; }
teardown_fakes() { rm -rf "$FAKEBIN" "$FIXTURE_DIR"; unset FIXTURE_DIR; }

# a single (non-group) name with a known candidate: picked
test_single_name_with_candidate_is_picked() {
  setup_fakes
  fixture_candidate libbar 2.0

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" lapt::pick_candidate libbar)
  rc=$?
  assert_eq "picks name+candidate" "libbar 2.0" "$out"
  assert_eq "exits 0" "0" "$rc"

  teardown_fakes
}

# a single name unknown to apt-cache: not picked, no output, nonzero exit
test_unknown_name_is_not_picked() {
  setup_fakes

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" lapt::pick_candidate nosuchpkg)
  rc=$?
  assert_eq "no output" "" "$out"
  if [[ $rc -eq 0 ]]; then
    printf 'FAIL: %s\n  expected nonzero exit, got 0\n' "unknown name exits nonzero"
    fail=1
  fi

  teardown_fakes
}

# OR-group: first alternative unknown to apt-cache, second has a candidate --
# the second is picked (ADR-0010 deterministic "first alternative with a
# candidate" rule; no installed/host state involved in this pick)
test_or_group_picks_first_alternative_with_a_candidate() {
  setup_fakes
  fixture_candidate cdebconf 1.5

  local out rc
  out=$(PATH="$FAKEBIN:$PATH" lapt::pick_candidate 'debconf|cdebconf')
  rc=$?
  assert_eq "picks first alternative that has a candidate" "cdebconf 1.5" "$out"
  assert_eq "exits 0" "0" "$rc"

  teardown_fakes
}

# OR-group where both alternatives have a candidate: the first in the group
# wins, regardless of anything else
test_or_group_prefers_first_listed_when_both_known() {
  setup_fakes
  fixture_candidate debconf 1.5
  fixture_candidate cdebconf 1.5

  local out
  out=$(PATH="$FAKEBIN:$PATH" lapt::pick_candidate 'debconf|cdebconf')
  assert_eq "first-listed alternative wins" "debconf 1.5" "$out"

  teardown_fakes
}

test_single_name_with_candidate_is_picked
test_unknown_name_is_not_picked
test_or_group_picks_first_alternative_with_a_candidate
test_or_group_prefers_first_listed_when_both_known
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
