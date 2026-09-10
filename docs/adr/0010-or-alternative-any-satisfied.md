# OR-alternative dependencies: any-satisfied skip, deterministic pick otherwise

apt dependency lines can list several alternatives (`A | B | C`) instead of a
single package — e.g. `debconf (>= 0.5) | debconf-2.0`, present in the
closure of a large fraction of Debian packages. `resolve_closure` needs a
rule for these. Two designs were on the table:

- **Option A**: apt-only. Always pick the first alternative that has an
  `apt-cache` candidate; `resolve_closure` never touches `dpkg`, fully
  deterministic.
- **Option B**: dpkg-aware. Prefer whichever alternative is already
  installed, decided inside `resolve_closure` itself.

Option B was initially rejected for tying closure resolution — meant to stay
a pure, fixture-testable parser over `apt-cache` output — to live `dpkg`
state. But Option A alone has a real cost: whenever the *non-first*
alternative happens to be the one already on the host, Option A still fetches
and bundles the first one anyway — a wasted download for exactly the kind of
case ADR-0007 exists to eliminate for ordinary dependencies.

**Verified against real apt** rather than assumed: `apt-get install
--print-uris -s aide` on this host (where `debconf` and `systemd` are both
already installed) does not fetch anything for `aide`'s `debconf (>= 0.5) |
debconf-2.0` or `systemd | systemd-standalone-sysusers | systemd-sysusers`
dependency lines — apt treats an OR-group as satisfied the moment *any* one
alternative is already installed, and only falls back to order/priority
tie-breaking when none is.

## Decision

Neither option outright — the any-satisfied check moves to where the
dpkg-touching seam already lives, instead of into `resolve_closure`:

- `resolve_closure` keeps Option A's purity: apt-only, deterministic, no
  `dpkg` call inside it. It stops collapsing an OR-line to a single package
  name and returns the whole alternative list as one closure member (see
  **OR-alternative**, CONTEXT.md).
- The existing system-satisfied check (ADR-0007 — the one seam allowed to
  touch `dpkg`) generalizes from "is this one name installed and
  version-satisfying" to "is *any* name in this group installed and
  version-satisfying." If so, skip the whole group — nothing fetched for it,
  same as apt's own behavior above.
- Only if *none* of a group's alternatives is system-satisfied does anything
  get picked concretely to fetch and bundle: deterministically, the first
  alternative with an `apt-cache` candidate (Option A's rule) — used only as
  the fallback, not the default path.

This keeps `resolve_closure` fixture-testable with a fixed input and a fixed
output, independent of what's installed on the machine running the test —
the same requirement that led to Option A in the first place — while still
getting the real efficiency apt itself gets, without adding a second place
that pokes `dpkg`.

Downstream of the system-satisfied filter, nothing changes: `.lapt/system-deps`
still records one `<name> <version>` per skipped entry, never a group, and
`bundle_manifest`/`bundle_apply` still only ever see concrete package names —
the group shape is fully resolved away before either is called.

**Scope**: applies identically under `vendor` (ADR-0009) — same
`is_system_satisfied` check, same any-of generalization, same deterministic
fallback pick. No separate rule needed there.
