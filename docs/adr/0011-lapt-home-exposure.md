# Exposure moves bin/man into LAPT_HOME, supersedes ADR-0004's location choice

ADR-0004 chose `$HOME/.local/bin` and `$HOME/.local/share/{man,bash-completion/completions,applications,icons,mime}`
as exposure targets specifically because they need no extra `PATH`/env var
setup on most systems — they're already scanned by default. In practice this
meant lapt's installed packages were indistinguishable, on disk, from
anything else that happens to write into `$HOME/.local` — no single
directory a user could point at, back up, or wipe to undo every trace of
lapt. Convenience of setup was bought at the cost of isolation.

**`bin/` and `share/man/` move to `$LAPT_HOME`, a single fixed root.**
`LAPT_HOME` is always `$HOME/.lapt` — not configurable, no env var override —
and replaces the previously independent `LAPT_OPT_ROOT`/`LAPT_CACHE_ROOT`
overrides — `opt/`, `cache/`, and now the top-level package's own exposed
executables and man pages all live under one directory, with no override to
fragment that back apart. A new `lapt init` subcommand writes `$LAPT_HOME/env` (prepending
`$LAPT_HOME/bin` to `PATH`, prepending `$LAPT_HOME/share/man` to `MANPATH`
with its trailing colon preserved so the system's default man search paths
still apply, each guarded against re-sourcing so a nested shell sourcing it
twice doesn't duplicate the entry) and tells the user which line to add to
their shell rc. `lapt init` never touches `~/.bashrc` or any file
outside `$LAPT_HOME` itself — it prints a suggestion and stops there,
regenerating `env` unconditionally on every run since it's an explicit,
one-off action rather than a lazily-populated cache file like `vendor`'s
`env.sh`.

**bash-completion/desktop/icon/MIME entries are dropped from exposure
entirely — not relocated, not deferred.** ADR-0004 exposed these to
`$HOME/.local/share/{bash-completion/completions,applications,icons,mime}`;
that stops. Unlike `bin`/`man`, these categories are consumed by tooling
(bash's completion loader, desktop environments) that isn't necessarily
pointed at a `lapt init`-sourced environment, so keeping them exposed would
mean hardcoding a second, unrelated root (`$HOME/.local`) into the
exposure mechanism purely to preserve a zero-setup property for four
categories nothing currently depends on lapt providing. That's complexity
serving no active design need, so it's cut rather than carried forward
half-migrated. `lib/expose.sh`'s category `case` only ever recognizes
`bin/*` and `share/man/*`; anything else is treated exactly like a
non-exposable path such as `lib/` — never symlinked anywhere. Revisit only if
a real need for exposing these categories resurfaces, at which point it can
be designed against whatever `LAPT_HOME`-based convention makes sense then.

**This narrows ADR-0004's scope; every invariant it set for the categories
that remain still holds.** Exposure is still scoped to the top-level
package's own files only, never a dependency's; still one shared destination
(now just `LAPT_HOME`, since there's only one root at all); still recorded
to a per-package `opt/<pkg>/.lapt/exposed` list for O(this package's own
entries) removal, no shared-dir scan. `expose_add`/`expose_remove` take a
single `lapt_home` parameter — no second root, no `legacy_home` concept,
internal or otherwise, since there's nothing left for it to route to.

Existing installs are unaffected by upgrading lapt itself, but any package
installed under the old `$HOME/.local/share/lapt` layout has already-exposed
`bin`/`man` symlinks sitting in `$HOME/.local`. There is no migration path:
per the user's own call when this was decided, existing packages are removed
and pruned by hand and reinstalled fresh under the new layout.
