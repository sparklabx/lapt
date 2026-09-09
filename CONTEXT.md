# lapt

A local, rootless installer that wraps `apt-get download` + `dpkg -x` to put Debian/Ubuntu packages under `$HOME/.local` without sudo and without touching the system package database.

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
The extracted, verbatim (`usr/`-prefixed) content of one downloaded `.deb`, stored once at `$HOME/.local/share/lapt/cache/<name>_<version>/`. Permanent and immutable once written — never evicted, never re-extracted for a given name+version. Not a cache in the LRU/eviction sense despite the name.
_Avoid_: package store

**Flattening**:
The path rewrite applied when consuming a cache entry (during assemble or vendor, never when populating the cache itself): the leading `usr/` is stripped, and a multiarch triplet directory (e.g. `x86_64-linux-gnu`) directly under `lib/`, `include/`, or `pkgconfig/` is stripped too. Cache entries themselves keep the verbatim Debian layout; only the assembled/vendored copy is flat.

**Assemble**:
What `lapt install <pkg>` does: hardlink every closure member's cache entry into one flattened `opt/<pkg>/` tree, generate `.wrap` wrappers where a runtime `lib/` exists, expose `bin/` entries, write `.lapt-version`. Produces a tracked, listed, removable entity under `opt/`.
_Avoid_: vendor, vendoring (reserved below for the unrelated `vendor` subcommand)

**Vendor**:
What `lapt vendor <target-dir> <pkg...>` does: hardlink (or, for `.pc` files, copy-and-rewrite) library/header/pkgconfig content straight from cache into a user-owned, lapt-untracked directory, for build-time linking against an external project. Never touches `opt/`, never creates a `.lapt-version`. Distinct from **assemble** even though both consume cache entries by hardlinking.
_Avoid_: install (a vendored package is never "installed" — it has no opt/<pkg>, isn't listed, isn't removable by lapt)

**Frozen-private**:
The policy that runtime libraries are never shared between installed packages — each `opt/<pkg>` gets its own complete, self-sufficient copy of every closure member's `lib/`, sized at assemble time and never updated by a later, unrelated install. No shared mutable lib pool, no reference counting.
_Avoid_: vendoring in the LD_LIBRARY_PATH sense (unrelated to the `vendor` subcommand)
