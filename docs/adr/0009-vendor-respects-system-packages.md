# Vendor also respects system-installed packages

Revises [ADR-0007](./0007-respect-system-installed-packages.md), which
scoped its system-satisfied-dependency skip to `assemble` only and declared
`vendor` out of scope. Reconsidered: `vendor`'s `target-dir` exists purely
for build-time linking against an external project, and `/usr/include`,
`/usr/lib`, `/usr/lib/<multiarch-triplet>` are already on a compiler's and
linker's default search paths — and a `.pc` file's `PKG_CONFIG_PATH`
lookup prepends `target-dir` to, rather than replaces, `pkg-config`'s
default search, so the system copy is still found either way. Hardlinking
(or copy-rewriting) a package into `target-dir` that the host already
provides is pure duplication with no correctness benefit. This is unlike
`assemble`, where `opt/<pkg>` must stay self-contained and frozen-private
regardless of host state (ADR-0001) — `vendor` has no such requirement,
since it was never meant to be a portable, host-independent copy in the
first place.

**Same detection, same mechanism, both scopes.** Reuses ADR-0007's
`is_system_satisfied` check (`dpkg -s` + `dpkg --compare-versions` by
package name) unmodified — no new detection logic. Two places it now
applies within `vendor <target-dir> <pkg...>`:

- **Each named package itself**: if system-satisfied, skip it entirely —
  nothing hardlinked or copied for it, just a notice. Same shape as
  `assemble`'s top-level check (ADR-0007), but for `vendor` this applies to
  *every* package in the argument list, since `vendor` has no single
  privileged "top-level" the way `install` does — each named package is
  independently either vendored or skipped.
- **Every other closure member** (of whichever named packages weren't
  skipped): skipped if system-satisfied, identical to `assemble`'s
  dependency skip.

**No `.lapt/system-deps` equivalent, no `fix` for vendor.** `vendor`
creates no `.lapt/` state at all — unchanged by this ADR (CONTEXT.md:
"never touches `opt/`, never creates a `.lapt/version`"). A skip decision
here isn't tracked or repairable. If the host later removes or upgrades a
package that was skipped, a subsequent external build could fail to find
it; the fix is to just re-run `lapt vendor`, consistent with vendor never
having had persistent, repairable state to begin with.

**No mechanism change to closure resolution or bundling.** This doesn't
touch `resolve_closure` (still apt-only, no `dpkg` involved in picking
OR-alternatives — that stays a separate, deliberately unrelated question)
or `bundle_manifest`/`bundle_apply`. `cmd_vendor` filters its closure
member list by `is_system_satisfied` before calling `bundle_manifest`,
exactly the same shape as `cmd_install` already does — the skip happens in
orchestration, not in the shared bundling module.

Multiple named packages can share closure members; `bundle_manifest`'s
existing collision check (ADR-0003) already handles that regardless of how
many top-level packages contributed to the combined member list — no new
cross-package logic needed for that either.
