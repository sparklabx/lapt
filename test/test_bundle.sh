#!/usr/bin/env bash
# Vertical-slice tests for lib/bundle.sh, seam: lapt::bundle_manifest only.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/lib/cache.sh"
. "$ROOT/lib/bundle.sh"

fail=0
assert_eq() {
  local desc=$1 expected=$2 actual=$3
  if [[ $expected != "$actual" ]]; then
    printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' "$desc" "$expected" "$actual"
    fail=1
  fi
}

setup_cache() {
  export LAPT_CACHE_ROOT
  LAPT_CACHE_ROOT=$(mktemp -d)
}

# one member, one file, empty dest-dir: usr/ is stripped, no multiarch dir involved
test_single_file_strips_usr() {
  setup_cache
  local dest; dest=$(mktemp -d)
  mkdir -p "$LAPT_CACHE_ROOT/foo_1.0/usr/bin"
  : > "$LAPT_CACHE_ROOT/foo_1.0/usr/bin/foo"

  local out
  out=$(lapt::bundle_manifest "$dest" "foo"$'\t'"1.0"$'\t'"foo")
  assert_eq "single file manifest row" \
    "bin/foo	$LAPT_CACHE_ROOT/foo_1.0/usr/bin/foo	foo" \
    "$out"

  rm -rf "$LAPT_CACHE_ROOT" "$dest"
}

# a Debian epoch version (e.g. bison's 2:3.8.2+dfsg-1+b1) contains a colon --
# the spec format must not use colon as its own field separator, or the
# epoch's colon corrupts the split (name/version/origin is tab-delimited
# specifically so this can't happen)
test_epoch_version_with_colon_is_preserved() {
  setup_cache
  local dest; dest=$(mktemp -d)
  mkdir -p "$LAPT_CACHE_ROOT/foo_2:3.8.2+dfsg-1+b1/usr/bin"
  : > "$LAPT_CACHE_ROOT/foo_2:3.8.2+dfsg-1+b1/usr/bin/foo"

  local out
  out=$(lapt::bundle_manifest "$dest" "foo"$'\t'"2:3.8.2+dfsg-1+b1"$'\t'"foo")
  assert_eq "epoch version's colon does not corrupt the cache path" \
    "bin/foo	$LAPT_CACHE_ROOT/foo_2:3.8.2+dfsg-1+b1/usr/bin/foo	foo" \
    "$out"

  rm -rf "$LAPT_CACHE_ROOT" "$dest"
}

# multiarch triplet dir directly under lib/ is stripped along with usr/
test_multiarch_triplet_under_lib_stripped() {
  setup_cache
  local dest; dest=$(mktemp -d)
  mkdir -p "$LAPT_CACHE_ROOT/foo_1.0/usr/lib/x86_64-linux-gnu"
  : > "$LAPT_CACHE_ROOT/foo_1.0/usr/lib/x86_64-linux-gnu/libfoo.so.1"

  local out
  out=$(lapt::bundle_manifest "$dest" "foo"$'\t'"1.0"$'\t'"foo")
  assert_eq "multiarch lib manifest row" \
    "lib/libfoo.so.1	$LAPT_CACHE_ROOT/foo_1.0/usr/lib/x86_64-linux-gnu/libfoo.so.1	foo" \
    "$out"

  rm -rf "$LAPT_CACHE_ROOT" "$dest"
}

# two members, distinct dest paths: both rows present, no collision
test_two_members_no_collision() {
  setup_cache
  local dest; dest=$(mktemp -d)
  mkdir -p "$LAPT_CACHE_ROOT/foo_1.0/usr/bin" "$LAPT_CACHE_ROOT/bar_2.0/usr/bin"
  : > "$LAPT_CACHE_ROOT/foo_1.0/usr/bin/foo"
  : > "$LAPT_CACHE_ROOT/bar_2.0/usr/bin/bar"

  local out
  out=$(lapt::bundle_manifest "$dest" "foo"$'\t'"1.0"$'\t'"foo" "bar"$'\t'"2.0"$'\t'"bar" | sort)
  local expected
  expected=$(printf '%s\n%s' \
    "bin/bar	$LAPT_CACHE_ROOT/bar_2.0/usr/bin/bar	bar" \
    "bin/foo	$LAPT_CACHE_ROOT/foo_1.0/usr/bin/foo	foo" | sort)
  assert_eq "two members manifest rows" "$expected" "$out"

  rm -rf "$LAPT_CACHE_ROOT" "$dest"
}

# two members claiming the same dest path: hard-abort, nonzero exit, nothing usable on stdout
test_collision_between_members_aborts() {
  setup_cache
  local dest; dest=$(mktemp -d)
  mkdir -p "$LAPT_CACHE_ROOT/foo_1.0/usr/bin" "$LAPT_CACHE_ROOT/bar_2.0/usr/bin"
  : > "$LAPT_CACHE_ROOT/foo_1.0/usr/bin/clash"
  : > "$LAPT_CACHE_ROOT/bar_2.0/usr/bin/clash"

  local out rc
  out=$(lapt::bundle_manifest "$dest" "foo"$'\t'"1.0"$'\t'"foo" "bar"$'\t'"2.0"$'\t'"bar" 2>/dev/null)
  rc=$?
  if [[ $rc -eq 0 ]]; then
    printf 'FAIL: %s\n  expected nonzero exit, got 0\n' "collision aborts"
    fail=1
  fi
  assert_eq "collision produces no stdout rows" "" "$out"

  rm -rf "$LAPT_CACHE_ROOT" "$dest"
}

# pre-existing dest-dir file is included as an "existing" row (fix's append case)
test_existing_dest_file_is_a_row() {
  setup_cache
  local dest; dest=$(mktemp -d)
  mkdir -p "$dest/bin"
  : > "$dest/bin/already-there"
  mkdir -p "$LAPT_CACHE_ROOT/foo_1.0/usr/bin"
  : > "$LAPT_CACHE_ROOT/foo_1.0/usr/bin/foo"

  local out
  out=$(lapt::bundle_manifest "$dest" "foo"$'\t'"1.0"$'\t'"foo" | sort)
  local expected
  expected=$(printf '%s\n%s' \
    "bin/already-there	$dest/bin/already-there	existing" \
    "bin/foo	$LAPT_CACHE_ROOT/foo_1.0/usr/bin/foo	foo" | sort)
  assert_eq "existing dest file becomes a row" "$expected" "$out"

  rm -rf "$LAPT_CACHE_ROOT" "$dest"
}

# a new member claiming a path an existing dest-dir file already occupies: hard-abort (ADR-0007)
test_collision_against_existing_dest_file_aborts() {
  setup_cache
  local dest; dest=$(mktemp -d)
  mkdir -p "$dest/bin"
  : > "$dest/bin/clash"
  mkdir -p "$LAPT_CACHE_ROOT/foo_1.0/usr/bin"
  : > "$LAPT_CACHE_ROOT/foo_1.0/usr/bin/clash"

  local out rc
  out=$(lapt::bundle_manifest "$dest" "foo"$'\t'"1.0"$'\t'"foo" 2>/dev/null)
  rc=$?
  if [[ $rc -eq 0 ]]; then
    printf 'FAIL: %s\n  expected nonzero exit, got 0\n' "collision against existing aborts"
    fail=1
  fi
  assert_eq "collision against existing produces no stdout rows" "" "$out"

  rm -rf "$LAPT_CACHE_ROOT" "$dest"
}

# a symlink in the cache entry (e.g. a shared library's SONAME symlink) is
# included as a row, not just regular files -- real curl install exposed
# this: libcurl.so.4 -> libcurl.so.4.8.0 is what the dynamic linker actually
# looks up, and it was silently dropped
test_symlink_in_cache_entry_is_a_row() {
  setup_cache
  local dest; dest=$(mktemp -d)
  mkdir -p "$LAPT_CACHE_ROOT/foo_1.0/usr/lib"
  : > "$LAPT_CACHE_ROOT/foo_1.0/usr/lib/libfoo.so.1.0.0"
  ln -s libfoo.so.1.0.0 "$LAPT_CACHE_ROOT/foo_1.0/usr/lib/libfoo.so.1"

  local out
  out=$(lapt::bundle_manifest "$dest" "foo"$'\t'"1.0"$'\t'"foo" | sort)
  assert_eq "both the real file and its symlink are rows" \
    "$(printf '%s\n' \
      "lib/libfoo.so.1	$LAPT_CACHE_ROOT/foo_1.0/usr/lib/libfoo.so.1	foo" \
      "lib/libfoo.so.1.0.0	$LAPT_CACHE_ROOT/foo_1.0/usr/lib/libfoo.so.1.0.0	foo" \
      | sort)" \
    "$out"

  rm -rf "$LAPT_CACHE_ROOT" "$dest"
}

test_single_file_strips_usr
test_epoch_version_with_colon_is_preserved
test_multiarch_triplet_under_lib_stripped
test_two_members_no_collision
test_collision_between_members_aborts
test_existing_dest_file_is_a_row
test_collision_against_existing_dest_file_aborts
test_symlink_in_cache_entry_is_a_row
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
