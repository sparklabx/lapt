# `pkgenv/`: per-package post-install env vars

Supersedes ADR-0014's "out of scope" note, which explicitly named this
exact idea (a `git`-style `GIT_EXEC_PATH` hint) and deferred it as "a
separate, unrelated idea." This ADR reopens and resolves it.

## Problem

Some packages compile in absolute default paths (typically `/usr/lib/...`
or `/usr/share/...`) for helper files they look up at runtime, rather than
deriving the path from their own binary's location. `lapt` relocates
packages into `opt/<pkg>/`, flattening `usr/` away (ADR-0014), so those
compiled-in defaults point nowhere. Three real instances:

- `git`: exec-path helpers (`git-upload-pack`, `git-remote-https`, ...)
  default to `/usr/lib/git-core`; needs `GIT_EXEC_PATH`.
- `file`: the magic database defaults to a fixed system path; needs
  `MAGIC`.
- `bison`: its data directory and its `m4` dependency default to
  `/usr/share/bison` and `/usr/bin/m4`; needs `BISON_PKGDATADIR` and `M4`
  (already documented as a manual build-time workaround in
  `docs/examples/building-tmux.md` §3).

Verified against the real `.deb`s (`apt-get download` + `dpkg-deb -e`/`-c`
for `git`, `file`, `libmagic1`, `bison`, `m4`): nothing in `postinst`,
`DEBIAN/triggers`, or `control` already encodes this. `DEBIAN/triggers` is
an unrelated dpkg mechanism (cross-package filesystem-change notification,
e.g. `ldconfig`/`mandb`) — not per-package post-install setup. The fix has
to be `lapt`'s own data.

## Decided

**`pkgenv/`**, a top-level directory in the `lapt` repo (shipped alongside
`bin/` and `lib/` in release tarballs — see `release.sh`), one file per
package: `pkgenv/git`, `pkgenv/file`, `pkgenv/bison`. Each file is a flat,
declarative list of `VAR=relative/path` lines — never shell, no code
execution, ever (consistent with ADR-0002's "no manifest, no jq" bias
against smuggling logic into data files).

**Presence of `pkgenv/$pkg` forces a wrapper** for that package's top-level
`bin/` files, regardless of whether `lib/` or a foreign `bin/` would
otherwise trigger one (`lapt::needs_wrapper` in `lib/wrap.sh`). Without
this, an entry like `file`'s — which bundles no `lib/` and no foreign
`bin/` of its own — would be dead code in the common case.

**Each `VAR=relpath` line is resolved and guarded**: before emitting
`export VAR="<resolved>"` into the wrapper, `lapt::write_wrapper` checks the
resolved path exists; a missing one is skipped silently, not exported
broken. This handles a dependency (e.g. bison's `m4`) that turned out to be
system-satisfied and so was never bundled — an unset `M4` is safe; a `M4`
pointing at a nonexistent file is not.

**No detection heuristic.** No scanning binaries for orphaned absolute
`/usr/...` path strings to auto-discover more cases — catalog-only for now
(YAGNI). Revisit if a third undiscovered case causes real pain beyond
these three.

**New `lapt rewrap <pkg>` command**, not folded into `fix`: refreshes an
already-installed package's wrapper in place (re-run after adding or
editing a `pkgenv/$pkg` entry) without requiring a reinstall. Reuses
`cmd_fix`'s existing-scan re-tagging trick (`bin/lapt`, `cmd_fix`) to tell
a package's own `bin/` files apart from a dependency's once they're
already on disk together, but does no fetching of its own — it only
recomputes from what's currently bundled in `opt/<pkg>/`. (`fix` itself
was later removed, see ADR-0016 — `cmd_rewrap` keeps its own copy of this
trick.)
