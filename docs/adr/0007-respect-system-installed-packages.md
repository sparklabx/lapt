# Respect system-installed packages

`assemble` currently bundles every closure member unconditionally, even
when the host already has a working, correctly-versioned copy via its own
system package manager (a very common case — `libc6` and friends are
installed on essentially every Debian/Ubuntu host, and plenty of users
already have the top-level package itself installed system-wide too).
Hardlinking from the cache means this isn't really a disk-*duplication*
problem (the same cache entry backs every `opt/<pkg>` that needs it), but
it is a wasted download-and-cache-extraction problem: there's no reason to
ever fetch and cache something the system already provides.

**Detection, shared by both cases below**: check by package name against
`dpkg`, not by filesystem probing. `dpkg-query`/`dpkg -s` (read-only — see
`CONTEXT.md`'s framing, this was never actually prohibited) tells you
whether that exact package name is installed and at what version;
`dpkg --compare-versions` checks it against the version constraint the
closure resolution already carries. Checking for a same-named file under
`/usr/lib` or `$PATH` was rejected — it can't distinguish the right
package/version from a same-named unrelated one (e.g. a `pyenv`-installed
`python3` on `PATH` isn't the apt `python3` package).

## Top-level package: notify and skip entirely

Checked after the existing "already lapt-installed" no-op check
(`opt/<pkg>` exists — cheap filesystem stat, runs first, unchanged). If
`<pkg>` itself is already installed via the system package manager: print a
notice and exit 0. No fetch, no cache work, no `opt/<pkg>` created —
nothing to assemble, and nothing to track, since there's no `opt/<pkg>` for
a record to belong to. If the system package is later removed, a
subsequent `lapt install <pkg>` just proceeds normally (the pre-check finds
nothing installed and falls through). No flag to force a lapt-managed copy
alongside an existing system install — consistent with the no-getopts CLI
convention; not solved, since nothing so far has asked for it.

## Dependencies: skip, track, repair via `lapt fix`

For every **non-top-level** closure member (the top-level package is always
bundled once the check above passes — that's the point of running `lapt
install` at all): if it's already satisfied by the host, skip fetching and
bundling it entirely. Nothing from that closure member is hardlinked into
`opt/<pkg>/`. This composes with existing wrapper-generation logic without
changes: the trigger already looks at what's actually present in
`opt/<pkg>/`, and the dynamic linker / `PATH` already fall through to the
host's own default search paths for anything not bundled or not in
`LD_LIBRARY_PATH`/the wrapper's prepended `PATH`.

Skipped dependencies are recorded to `opt/<pkg>/.lapt/system-deps` — a flat
file, one `<name> <version-relied-on>` per line, same style as the other
files under `opt/<pkg>/.lapt/` (no manifest format, no jq). This is what
makes the skip decision auditable and repairable later, rather than an
untracked landmine.

`lapt fix <pkg>` (new subcommand) re-verifies every entry in
`.lapt/system-deps` against current `dpkg` state. Anything no longer
installed or no longer version-satisfying gets fetched and bundled into
`opt/<pkg>/` now — a partial re-assemble, including regenerating the
`.wrap` wrapper if bundling newly triggers it (a package that was entirely
system-satisfied has no wrapper at all until `fix` needs one). `install` on
an already-installed package stays the existing no-op; repair is a
separate, explicit action, not folded into re-running `install`. `lapt
list` is unaffected — it stays a pure `opt/*/.lapt/version` read, it does
not proactively re-check `.lapt/system-deps` against `dpkg` on every
invocation; staleness is only surfaced when `fix` is run.

This accepts a real trade-off: the frozen-private guarantee (ADR-0001) no
longer holds unconditionally for the whole closure — a package can go
briefly stale if the host's `apt upgrade`/`apt remove` changes something
`assemble` relied on, until `lapt fix` is run. That's a deliberate, scoped
exception: it only ever applies to closure members that were *eligible to
be skipped in the first place* (declared, satisfied at install time);
anything actually bundled — including the top-level package always —
remains exactly as frozen-private as before. Vendor is out of scope for
this decision; it's a different operation (build-time linking) and not
addressed here.

## Implementation note: `fix` re-resolves nothing, appends only

`fix`'s partial re-assemble must not re-resolve the closure or touch
anything already bundled — that's what keeps the frozen-private trade-off
above "scoped." Concretely: it fetches only the specific `.lapt/system-deps`
entries that failed re-verification, using the version already recorded
there (not a fresh `apt-cache` lookup), and hardlinks only those into
`opt/<pkg>/`. The one new correctness requirement this creates: the
destination-collision check (ADR-0003) that runs before hardlinking must
include files *already present* in `opt/<pkg>/` from the original assemble,
not just collisions among the newly-added members — otherwise a
newly-unskipped dependency could silently clobber a path an already-bundled
file occupies. A fresh `install` has no such existing tree, so the same
collision check degenerates to the old all-new-members case for it; `fix`
is what makes it a real requirement.
