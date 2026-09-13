# Drop the usr/-only restriction on installable packages

Revises the **Scope-restricted package** invariant (CONTEXT.md glossary; no
prior ADR established it — it was a foundational assumption baked into
`cache_ensure` from the start: `dpkg-deb -c` was checked against every file
in a `.deb` before extraction, and any file outside `usr/**` hard-aborted the
whole fetch).

The restriction meant a package that installs anything outside `usr/` (e.g.
`git`'s `etc/`-adjacent scaffolding some packages ship, or any package with
real content under root-level `bin/`, `sbin/`, `lib/`) simply couldn't be
installed by `lapt` at all — not just that one file skipped, the entire
top-level install (and any closure it appeared in as a dependency) refused
to fetch. In practice this rejected real, common packages for no benefit:
`dpkg -x` never runs maintainer scripts regardless of where a package's
files live, so the safety property the check was thought to buy was never
actually contingent on the `usr/` restriction — only "flattening stays
unambiguous" was, and that's addressed directly below.

**Decided: `cache_ensure` no longer inspects `dpkg-deb -c` output at all.**
Any package apt can produce a candidate for can be fetched and cached,
regardless of layout.

**Flattening generalizes to: strip `usr/` if present, else strip nothing.**
`bundle_manifest` computed each file's relative path by stripping a leading
`usr/`; it now strips `usr/` only when the file is actually under it,
otherwise keeps the file's own root-relative path unchanged. This one change
has three consequences, all "free" — no bin/lib/sbin-specific code needed:

- `usr/bin/x` and root-level `bin/x` reduce to the identical rel path
  `bin/x` — they flatten into the same `opt/<pkg>/bin/`. Same for
  `usr/lib`≡`lib`, `usr/sbin`≡`sbin`. `expose.sh` and `wrap.sh` are
  unmodified by this ADR: both already key off rel-path prefixes
  (`bin/*`, `share/man/*`, `lib/*`), so the merged paths are
  exposed/wrapped exactly like their `usr/`-prefixed equivalents always
  were.
- The existing multiarch triplet strip (`lib|include|pkgconfig` directly
  under a `*-linux-gnu*` dir) applies unconditionally after the above, so it
  now also fires for a root-level `lib/x86_64-linux-gnu/`, not just
  `usr/lib/x86_64-linux-gnu/`.
- The existing collision check (`seen[]` in `bundle_manifest`) is unchanged
  and now also catches the (practically unreachable on a usr-merged host,
  since `/bin` is a symlink to `/usr/bin` there) case of one package
  genuinely shipping both `bin/x` and `usr/bin/x` as distinct real files —
  same hard-fail-the-whole-install behavior as any other collision.

**`sbin/` (root or `usr/`) is deliberately left unexposed**, same as it
already was: `expose.sh`'s case statement only ever matched `bin/*` and
`share/man/*`, so `usr/sbin/*` was already hardlinked-but-inert before this
change. Root-level `sbin/*` now reduces to the same rel path and inherits
the same treatment — no new exposure category was added for it.

**A new one-line notice surfaces unexposed content.** Once arbitrary
top-level dirs can show up in `opt/<pkg>/`, `cmd_install` scans the final
manifest for top-level dir names other than `bin`/`lib`/`share` (the
categories already handled — `share` includes `share/man`, which is exposed,
plus ordinary always-inert content like `share/doc`/`share/locale` that was
already common and unremarked-on before this change) and prints one line
naming whichever others are present, e.g. `lapt: git also has etc/ under
opt/git — bundled but not exposed, worth a look if you need it`. This is a
per-install, whole-`opt/<pkg>`-tree scan — it does not attribute content to
the top-level package vs. a dependency, since the point is just "here's what
landed in your package's tree that nothing automatically wires up," not an
audit of provenance.

**Out of scope:** any mechanism for surfacing package-specific post-install
setup steps (e.g. a `git`-style `GIT_EXEC_PATH` hint) is a separate,
unrelated idea and is not addressed here.
