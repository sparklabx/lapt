#!/usr/bin/env bash
# Vertical-slice tests for lib/apt.sh, seam: lapt::resolve_closure only.
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

# real `apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts
# --no-breaks --no-replaces --no-enhances libnewt0.52` output on Debian bookworm:
# a linear/tree closure with no OR-alternatives and no virtual packages.
test_linear_closure_excludes_self_and_dedups() {
  local input='libnewt0.52
  Depends: libc6
  Depends: libslang2
libc6
  Depends: libgcc-s1
libslang2
  Depends: libc6
libgcc-s1
  Depends: gcc-12-base
  Depends: libc6
gcc-12-base'

  local expected=$'libc6\nlibslang2\nlibgcc-s1\ngcc-12-base'
  local actual
  actual=$(printf '%s\n' "$input" | lapt::resolve_closure)
  assert_eq "linear closure, self excluded, deduped, first-seen order" "$expected" "$actual"
}

test_linear_closure_excludes_self_and_dedups
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
