#!/usr/bin/env bash
# Vertical-slice tests for lib/cache.sh, seam: lapt::cache_referenced only.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/lib/cache.sh"

fail=0

# every file under the entry has link count 1 (nothing outside points at it): unreferenced, exit 1
test_no_extra_links_is_unreferenced() {
  local entry; entry=$(mktemp -d)
  : > "$entry/foo"

  if lapt::cache_referenced "$entry"; then
    printf 'FAIL: %s\n  expected exit 1 (unreferenced), got 0\n' "no extra links is unreferenced"
    fail=1
  fi

  rm -rf "$entry"
}

# a file inside the entry is hardlinked elsewhere (link count 2): referenced, exit 0
test_hardlinked_file_is_referenced() {
  local entry outside; entry=$(mktemp -d); outside=$(mktemp -d)
  : > "$entry/foo"
  ln "$entry/foo" "$outside/foo"

  if ! lapt::cache_referenced "$entry"; then
    printf 'FAIL: %s\n  expected exit 0 (referenced), got nonzero\n' "hardlinked file is referenced"
    fail=1
  fi

  rm -rf "$entry" "$outside"
}

test_no_extra_links_is_unreferenced
test_hardlinked_file_is_referenced
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
