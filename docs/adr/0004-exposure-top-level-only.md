# Exposure: top-level-only, standard dirs, per-package removal list

`assemble` hardlinks every closure member's files into `opt/<pkg>/`, but
nothing there is discoverable on its own — not on `PATH`, not found by
`man`, shell completion, or desktop environments. **Exposure** is the extra
step of symlinking specific files out into standard, already-scanned
locations: executables into `$HOME/.local/bin`; `man` pages into
`$HOME/.local/share/man/**`; completion scripts into
`$HOME/.local/share/bash-completion/completions`; and `.desktop`
files/icons/MIME fragments into `$HOME/.local/share/{applications,icons,mime}`.
These standard XDG-ish locations were chosen over a lapt-namespaced dir
specifically so nothing needs extra `PATH`/env var setup — they're already
on `PATH` or already scanned by default.

**Scoped to the top-level package's own files, never a dependency's.** A
closure can include full applications, not just libraries — e.g. a
Python-based CLI tool depends on `python3`, which ships its own
`bin/python3`, man pages, etc. Exposing everything found under
`opt/<pkg>/**` (the naive approach) would leak such incidental dependencies
into the shared dirs, and two unrelated top-level installs sharing a
dependency would collide over — and steal ownership of — the same exposed
name; removing one would then delete something the other still needs.
`assemble` already tracks, per file, which closure member contributed it
(computed for collision detection), so exposure only symlinks entries whose
origin is the top-level package itself. A dependency's own executables/etc.
are still hardlinked into `opt/<pkg>/` — nothing is lost — and for
binaries specifically, the `.wrap` wrapper prepends `opt/<pkg>/bin` to
`PATH` so the top-level binary can still find them internally. (This is why
a wrapper is needed whenever the closure has a runtime `lib/` **or** `bin/`
files from any package other than the top-level one.)

**No desktop/mime/icon cache-refresh commands are run** (`update-desktop-database`,
`update-mime-database`, `gtk-update-icon-cache`) — files are placed and
left. Desktop environments rebuild these caches periodically on their own;
running them adds a dependency on tools that may not be installed, for a
purely cosmetic immediacy gain a user can trigger themselves.

**Removal via a per-package list, not a shared-dir scan.** `assemble` writes
`opt/<pkg>/.lapt/exposed` — a flat list, one `$HOME`-relative path per line,
no manifest format, no jq (same spirit as `.lapt/version`) — recording
every symlink it created for that package. `remove` reads this file and
unlinks each listed path directly: O(this package's own exposed entries).
The alternative — walking every shared exposure dir on every removal,
matching by resolved symlink target — was rejected as O(everything ever
exposed by every installed package); `icons/` alone can hold thousands of
entries across theme/size subdirs, and that cost only grows the more is
installed. One cheap check remains per line before unlinking: confirm the
symlink still resolves into this package's own `opt/<pkg>/`, guarding
against the rare case where a later, unrelated install claimed the same
exposed name. This check is bounded by this package's own entry count, so
it doesn't reintroduce the scan cost being avoided.

This does not reopen ADR-0002's core decision (no global ownership
database, no jq). `.lapt/exposed` is scoped to one package, lives inside
that package's own `opt/<pkg>/`, and is deleted along with it — it records
what `assemble` did, it doesn't track ownership across packages.
