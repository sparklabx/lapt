# `vendor` becomes a thin env-script layer over `install`

Supersedes [ADR-0009](./0009-vendor-respects-system-packages.md) (and, for
the mechanism it revised, [ADR-0007](./0007-respect-system-installed-packages.md)'s
scoping of that mechanism to `assemble` only).

`vendor <target-dir> <pkg...>` used to be a second, parallel path to the
same cache: resolve each named package's own closure, skip
system-satisfied members, fetch and flatten the rest straight from cache
into `target-dir`, and write a `target-dir/env.sh`. Now that
[ADR-0012](./0012-install-drops-top-level-bin-requirement.md) lets
`install` handle library-only packages directly — with the same flattening,
the same `.pc` rewriting, the same system-satisfied-dependency skip
(unaffected by this ADR) — `vendor`'s entire fetch/closure/bundle mechanism
is now duplicate work solving a problem `install` already solves.

**`vendor` no longer takes a `target-dir` and does no fetching of its own.**
New shape: `lapt vendor <pkg...>`. For each named package, require that it's
already `lapt install`-ed — checked the same way every other subcommand
checks this, `opt/<pkg>/.lapt/version` exists. If any named package is
missing: collect *all* missing names (not just the first) and report them
together in one error, nothing printed to stdout, nonzero exit — a user
vendoring five packages where two were never installed should see both
named at once, not fail-fast on the first and have to re-run four more
times to find the second. If every named package is present: print an env
script to stdout — `PATH`, `LD_LIBRARY_PATH`, `PKG_CONFIG_PATH` lines
pointing at each package's own `opt/<pkg>/{bin,lib,lib/pkgconfig}`, in the
order given on the command line — and nothing else. No file is written
anywhere; the caller redirects or sources it themselves, e.g.
`. <(lapt vendor libevent-dev libncurses-dev)`.

**Consequence: ADR-0009 becomes moot, not just narrowed.** `vendor` no
longer resolves closures, fetches anything, or checks `dpkg` state at all —
there is nothing left for a system-satisfied-dependency skip to apply to.
That check still happens exactly once, inside `install`, for every package
that ends up vendored.

**No more `.pc` rewriting inside `vendor` itself.** Each named package's
`.pc` files were already rewritten to point at its own `opt/<pkg>` at
`install` time (ADR-0012) — `vendor`'s job is now purely to expose the
already-correct paths via `PKG_CONFIG_PATH`, not to rewrite anything again.

**Each package keeps its own frozen-private tree; nothing is flattened
together.** The old `vendor` merged every named package's closure into one
shared `target-dir`, so two packages' `lib/` directories ended up
side by side in the same tree (deduping shared closure members, per
ADR-0009). The new `vendor` has no shared tree to merge into — each named
package already has its own self-contained `opt/<pkg>`, and the env script
just chains their `bin`/`lib`/`lib/pkgconfig` paths together in argument
order via `PATH`/`LD_LIBRARY_PATH`/`PKG_CONFIG_PATH` prepends, exactly like
multiple installed packages already coexist for any other purpose. A build
depending on two vendored libraries that happen to share a transitive
dependency now simply has that dependency's files present twice (once
under each depending package's `opt/`) rather than deduped into one
`target-dir` — accepted, since `opt/` is sized in whole packages already
and disk cost here is a hardlink, not a copy.

**No `vendor`-specific tracked state, same as before.** `vendor` still
creates nothing under `opt/` and still has no `fix` equivalent — there's
nothing to go stale, since it never bundles anything of its own; it only
reads state `install` already produced and maintains.
