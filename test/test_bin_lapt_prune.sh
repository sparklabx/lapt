#!/usr/bin/env bash
# Subprocess tests for bin/lapt, seam: `lapt prune` only. No apt fakes needed --
# prune only ever inspects link counts under cache/, fixture-able directly.
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

test_prune_on_empty_cache_is_silent() {
  export HOME; HOME=$(mktemp -d)

  local out rc
  out=$("$LAPT" prune 2>&1)
  rc=$?

  assert_eq "prune exits 0 on empty cache" "0" "$rc"
  assert_eq "prune prints nothing on empty cache" "" "$out"

  rm -rf "$HOME"; unset HOME
}

test_prune_removes_unreferenced_entry() {
  export HOME; HOME=$(mktemp -d)
  local cache_dir="$HOME/.local/share/lapt/cache/curl_8.5.0"
  mkdir -p "$cache_dir/usr/bin"
  : > "$cache_dir/usr/bin/curl"

  local out
  out=$("$LAPT" prune 2>&1)

  assert_eq "unreferenced entry pruned, printed" "lapt: pruned curl_8.5.0" "$out"
  [[ -d $cache_dir ]] && { echo "FAIL: unreferenced entry still on disk"; fail=1; }

  rm -rf "$HOME"; unset HOME
}

test_prune_keeps_referenced_entry() {
  export HOME; HOME=$(mktemp -d)
  local cache_dir="$HOME/.local/share/lapt/cache/curl_8.5.0"
  local opt_dir="$HOME/.local/share/lapt/opt/curl/bin"
  mkdir -p "$cache_dir/usr/bin" "$opt_dir"
  : > "$cache_dir/usr/bin/curl"
  ln "$cache_dir/usr/bin/curl" "$opt_dir/curl"

  local out
  out=$("$LAPT" prune 2>&1)

  assert_eq "referenced entry left alone, nothing printed" "" "$out"
  [[ -d $cache_dir ]] || { echo "FAIL: referenced entry was removed"; fail=1; }

  rm -rf "$HOME"; unset HOME
}

test_prune_mixed_only_unreferenced_removed() {
  export HOME; HOME=$(mktemp -d)
  local ref_dir="$HOME/.local/share/lapt/cache/curl_8.5.0"
  local unref_dir="$HOME/.local/share/lapt/cache/libfoo_1.2.3"
  local opt_dir="$HOME/.local/share/lapt/opt/curl/bin"
  mkdir -p "$ref_dir/usr/bin" "$unref_dir/usr/lib" "$opt_dir"
  : > "$ref_dir/usr/bin/curl"
  ln "$ref_dir/usr/bin/curl" "$opt_dir/curl"
  : > "$unref_dir/usr/lib/libfoo.so"

  local out
  out=$("$LAPT" prune 2>&1)

  assert_eq "only unreferenced entry pruned" "lapt: pruned libfoo_1.2.3" "$out"
  [[ -d $ref_dir ]] || { echo "FAIL: referenced entry was removed"; fail=1; }
  [[ -d $unref_dir ]] && { echo "FAIL: unreferenced entry still on disk"; fail=1; }

  rm -rf "$HOME"; unset HOME
}

test_prune_on_empty_cache_is_silent
test_prune_removes_unreferenced_entry
test_prune_keeps_referenced_entry
test_prune_mixed_only_unreferenced_removed
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
