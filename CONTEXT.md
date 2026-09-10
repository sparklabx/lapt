# lapt

A local, rootless installer that wraps `apt-get download` + `dpkg -x` to put Debian/Ubuntu packages under `$HOME/.local` without sudo and without writing to the system package database. Read-only queries against it (e.g. `dpkg -s`, `dpkg --compare-versions`) are fine.

## Language

**Closure**:
The transitive Depends+PreDepends set of a package, resolved via `apt-cache depends --recurse` (Recommends/Suggests/Conflicts/Breaks/Replaces/Enhances excluded). Ignores Conflicts/Breaks metadata entirely — collision detection at assemble/vendor time is the only safety net for what apt's Conflicts field would otherwise have prevented.
_Avoid_: dependency tree, dependency graph (no parent/child structure is ever built — the closure is a flat set)

**Top-level package**:
The package name given directly to `install`, `fetch`, or `vendor` — as opposed to a package that only appears because something else's closure depends on it.
_Avoid_: root package

**Scope-restricted package**:
A package whose closure member has every file under `usr/**`. Checked via `dpkg-deb -c` before extraction; any closure member failing this check hard-aborts the whole operation. This invariant is what makes it safe to never run maintainer scripts, and what makes flattening (below) unambiguous.
_Avoid_: usr-only package (fine as shorthand in prose, but the glossary term is this one)

**Cache entry**:
The extracted, verbatim (`usr/`-prefixed) content of one downloaded `.deb`, stored once at `$HOME/.local/share/lapt/cache/<name>_<version>/`. Immutable once written — never re-extracted for a given name+version. Not evicted automatically, and not an LRU cache; only removed by an explicit `lapt prune`, which reclaims entries no longer referenced by any assembled or vendored package (see ADR-0006 — checked via hardlink count, no manifest needed since consumption is always by hardlinking).
_Avoid_: package store

**Flattening**:
The path rewrite applied when consuming a cache entry (during assemble or vendor, never when populating the cache itself): the leading `usr/` is stripped, and a multiarch triplet directory (e.g. `x86_64-linux-gnu`) directly under `lib/`, `include/`, or `pkgconfig/` is stripped too. Cache entries themselves keep the verbatim Debian layout; only the assembled/vendored copy is flat.

**Assemble**:
What `lapt install <pkg>` does, once two early-exit checks pass: `opt/<pkg>` already existing (no-op, "already installed — run `remove` first") and `<pkg>` already being installed by the system package manager (no-op notice and exit, nothing created or tracked — ADR-0007; distinct from a **system-satisfied dependency**, below, which only skips bundling that one dependency and keeps assembling the rest). Past those: hard-aborts up front if the top-level package has no own `usr/bin` (ADR-0005 — `vendor` is the right tool for library-only packages), then for every closure member other than the top-level package checks whether it's a **system-satisfied dependency** (below) and skips it if so, hardlinks the rest of each closure member's cache entry into one flattened `opt/<pkg>/` tree, generates a `.wrap` wrapper where a runtime `lib/` exists or the closure has `bin/` files from a package other than the top-level one, performs exposure for the top-level package's own entries, writes `.lapt/version`. Produces a tracked, listed, removable entity under `opt/`.
_Avoid_: vendor, vendoring (reserved below for the unrelated `vendor` subcommand)

**System-satisfied dependency**:
A closure member that's skipped — fetched and bundled by neither `assemble` nor `vendor` — because the host already has it: checked by package name via read-only `dpkg -s`/`dpkg --compare-versions` against the closure's version constraint, never by probing `/usr/lib` or `$PATH` (a same-named file there doesn't prove it's the right package or version). For `assemble`, only a non-top-level closure member is ever eligible — the top-level package is always bundled. For `vendor`, every named package in `vendor <target-dir> <pkg...>` is independently eligible, top-level or not — there's no privileged package the way `install` has one. Only `assemble`'s skips are recorded, to `.lapt/system-deps` (one `<name> <version-relied-on>` per line, same flat-file style as `.lapt/version`) so `lapt fix` can re-verify them later; this is the one deliberate, scoped exception to frozen-private (below) for `assemble` — a skipped dependency can go stale if the host's package manager later changes it, until `fix` re-bundles it. `vendor` has no equivalent tracking (see **Vendor**, below) and no `fix` — re-run `vendor` if a skipped package's host state changes. See ADR-0007, ADR-0009.
_Avoid_: checking for a same-named file/binary on disk or `$PATH` (unreliable — doesn't verify package identity or version)

**`lapt fix <pkg>`**:
Re-verifies every entry in a package's `.lapt/system-deps` against current `dpkg` state; anything no longer installed or no longer version-satisfying is fetched and bundled into `opt/<pkg>/` now (a partial re-assemble, regenerating the `.wrap` wrapper if bundling newly triggers one). The only way staleness gets repaired — `lapt list` does not proactively check this, and `install` on an already-installed package stays a plain no-op. See ADR-0007.

**Exposure**:
Symlinking the top-level package's own files — executables, `man` pages, bash-completion scripts, `.desktop`/icon/MIME entries — out of `opt/<pkg>/` into the standard, already-scanned `$HOME/.local/bin` and `$HOME/.local/share/{man,bash-completion/completions,applications,icons,mime}` locations, making them reachable without any extra `PATH`/env var setup. Scoped to the top-level package's own files only — never to files contributed by a dependency in the closure, which stay hardlinked inside `opt/<pkg>/` (reachable *from inside* the `.wrap` wrapper via a `PATH` prepend, just not exposed to the shell or desktop environment). Every exposed path is recorded to that package's **exposure list** (below). No desktop/mime/icon cache-refresh commands are run — files are placed and left. See ADR-0004.
_Avoid_: exposing everything under `opt/<pkg>/**` (would leak incidental dependencies like a bundled `python3` into the shared dirs, and create ownership conflicts between unrelated installs that share a dependency); bin exposure / share exposure as separate concepts (one mechanism, same scoping, same removal path)

**Exposure list** (`.lapt/exposed`):
A flat, one-`$HOME`-relative-path-per-line file written by `assemble` alongside `.lapt/version`, recording every symlink created by exposure for that package. `remove` reads it directly to know what to unlink — O(this package's own exposure count), not a scan of the shared dirs (rejected: O(everything ever exposed)). Scoped to and deleted with its `opt/<pkg>/`; not a global manifest (ADR-0002 still holds). See ADR-0004.

**Vendor**:
What `lapt vendor <target-dir> <pkg...>` does: for each named package, skip it entirely if it's a **system-satisfied dependency** (above); otherwise resolve its closure and, for every member not itself system-satisfied, hardlink (or, for `.pc` files, copy-and-rewrite) library/header/pkgconfig content straight from cache into a user-owned, lapt-untracked directory, for build-time linking against an external project. Safe to skip a system-satisfied member here because `target-dir` is only ever used for build-time linking, and the host's default compiler/linker/`pkg-config` search paths already reach `/usr/include`, `/usr/lib(/<multiarch-triplet>)` — no `.wrap`-style indirection needed the way `assemble` needs one. Never touches `opt/`, never creates a `.lapt/version` or any other tracked state. Distinct from **assemble** even though both consume cache entries by hardlinking. See ADR-0009.
_Avoid_: install (a vendored package is never "installed" — it has no opt/<pkg>, isn't listed, isn't removable by lapt)

**`lapt wrap <binary> <target-dir>`**:
Moves an arbitrary, already-built binary that is not an apt package (e.g. a self-built Go binary needing a C library) into `<target-dir>/bin/<name>`, generates a `.wrap`-style wrapper alongside it that prepends `<target-dir>/lib` to `LD_LIBRARY_PATH` before exec'ing the moved binary, then symlinks `$HOME/.local/bin/<name>` to that wrapper — reusing **Exposure** unchanged, just pointed at `<target-dir>` instead of an `opt/<pkg>` tree. `<target-dir>` is expected to be a **Vendor** target-dir, already or about to be populated with whatever runtime libraries the binary needs. Never prepends to `PATH` the way `assemble`'s wrapper sometimes does — `vendor` never populates `target-dir/bin` with dependency binaries, so there is never another `bin/` to reach. No tracked state, no removal subcommand, same as `vendor`: undo by hand (`rm` the symlink, optionally the moved binary).
_Avoid_: install, assemble (no apt closure is ever resolved here, no `.lapt/version` is ever written — the input is a binary path, not a package name)

**Frozen-private**:
The policy that runtime libraries are never shared between installed packages — each `opt/<pkg>` gets its own complete, self-sufficient copy of every closure member's `lib/`, sized at assemble time and never updated by a later, unrelated install. No shared mutable lib pool, no reference counting. One deliberate, scoped exception: a **system-satisfied dependency** (above) is never bundled at all, so it can drift with the host until `lapt fix` re-bundles it — everything actually bundled, including the top-level package always, remains exactly as frozen as stated here.
_Avoid_: vendoring in the LD_LIBRARY_PATH sense (unrelated to the `vendor` subcommand)
