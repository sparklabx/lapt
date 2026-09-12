# `install` drops the top-level-bin requirement

Supersedes [ADR-0005](./0005-install-requires-top-level-bin.md).

ADR-0005 hard-aborted `lapt install <pkg>` whenever the top-level package
had no own `usr/bin`, on the theory that assembling one would silently
expose nothing on `PATH` — a result the user almost certainly didn't want —
and pointed at `lapt vendor` instead for library-only packages (e.g.
`libevent-dev`).

In practice this meant a genuinely common case — installing a `-dev`
package to build something else against it, without wanting the full
fetch/flatten/`env.sh` ceremony `vendor` used to require just to get at a
`.pc` file — had no path through `install` at all, even though `assemble`
already does everything a library-only install needs: hardlink the
package's `lib`/`include`/`pkgconfig` content into `opt/<pkg>`, same as any
other package. There's no silent-no-op risk once **exposure** (still
scoped to `bin`/`man` only) simply exposes nothing for a package that has
none — that's already how a system-satisfied dependency or a foreign `bin/`
package behaves today, not a new kind of outcome.

**Decided: drop the check entirely.** `install` no longer looks at whether
the top-level closure member has a `usr/bin` at all. A library-only package
assembles exactly like any other: hardlinked into `opt/<pkg>`, no wrapper
unless `needs_wrapper` says so (it won't, absent any `bin/` to wrap),
nothing exposed (there's nothing under `bin/`/`share/man/` to expose), listed
and removable like any other install.

**Consequence: `.pc` rewriting becomes unconditional for `install`.** A
library-only install is only useful for build-time linking if its `.pc`
files point at `opt/<pkg>` instead of the system `/usr` prefix baked in at
`.deb`-build time — the same rewrite `bundle_apply`'s `rewrite_pc=1` path
already performs for `vendor`. Rather than add a classification step to
decide which packages need it, `install` now always calls `bundle_apply`
with `rewrite_pc=1`. This is a no-op sed pass for the common case of a
package with no `.pc` files at all — cheap enough that branching around it
would be complexity with no payoff.

See [ADR-0013](./0013-vendor-redesign.md) for the corresponding redesign of
`vendor` itself, now that `install` covers library-only packages directly.
