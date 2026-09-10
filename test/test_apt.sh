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

# real `apt-cache depends --recurse ...` output for `readline-common`: its only
# dependency is a real (non-virtual) OR-alternative `dpkg | install-info`, and
# both alternatives have their own further dependencies in the same stream.
# The closure must contain the opaque group and nothing pulled in from either
# alternative's own subtree -- which one is chosen is not resolve_closure's job.
test_or_group_is_opaque_and_not_recursed_into() {
  local input='readline-common
 |Depends: dpkg
  Depends: install-info
dpkg
  PreDepends: libbz2-1.0
  PreDepends: libc6
  Depends: tar
install-info
  Depends: libc6
libbz2-1.0
  Depends: libc6
libc6
  Depends: libgcc-s1
tar
  PreDepends: libacl1
  PreDepends: libc6
libacl1
  Depends: libc6
libgcc-s1
  Depends: gcc-12-base
gcc-12-base'

  local expected='dpkg|install-info'
  local actual
  actual=$(printf '%s\n' "$input" | lapt::resolve_closure)
  assert_eq "OR-group is the sole, opaque closure member" "$expected" "$actual"
}

test_linear_closure_excludes_self_and_dedups
test_or_group_is_opaque_and_not_recursed_into
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
