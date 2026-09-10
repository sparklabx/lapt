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

# real `apt-cache depends --recurse ucf` output: the OR-group's terminal
# alternative is a virtual package `<debconf-2.0>`, whose real providers
# (cdebconf, debconf) are listed indented right below it. The virtual name
# itself is not a fetchable package and must be replaced by its providers,
# not kept alongside them; `debconf` (already the first alternative) dedups
# against itself appearing again as a provider.
test_virtual_alternative_replaced_by_its_providers() {
  local input='ucf
 |Depends: debconf
  Depends: <debconf-2.0>
    cdebconf
    debconf
  Depends: sensible-utils
debconf
cdebconf
  Depends: libc6
sensible-utils
libc6'

  local expected=$'debconf|cdebconf\nsensible-utils'
  local actual
  actual=$(printf '%s\n' "$input" | lapt::resolve_closure)
  assert_eq "virtual alternative replaced by its real providers, deduped" "$expected" "$actual"
}

# real `apt-cache depends --recurse` output includes cases where a plain
# (non-virtual, non-piped) dependency name also has an alternative provider
# listed via indentation -- e.g. libpulse0's `Depends: libsystemd0` followed
# by `libelogind0` (no angle brackets: libsystemd0 is a real, fetchable
# package). Unlike a virtual placeholder, the original name must be kept,
# not dropped -- either one satisfies it. libelogind0's own further
# dependency (libcap2, present in the same stream) must not leak into the
# closure, since the OR-group it's now part of is never recursed into.
test_real_name_with_alternative_provider_is_kept_and_extended() {
  local input='libpulse0
  Depends: libc6
  Depends: libsystemd0
    libelogind0
  Depends: libx11-6
libc6
libelogind0
  Depends: libcap2
libx11-6
libcap2'

  local expected=$'libc6\nlibsystemd0|libelogind0\nlibx11-6'
  local actual
  actual=$(printf '%s\n' "$input" | lapt::resolve_closure)
  assert_eq "real name kept, provider appended as alternative, not recursed into" "$expected" "$actual"
}

test_linear_closure_excludes_self_and_dedups
test_or_group_is_opaque_and_not_recursed_into
test_virtual_alternative_replaced_by_its_providers
test_real_name_with_alternative_provider_is_kept_and_extended
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
