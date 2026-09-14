# Remove `lapt fix`

`lapt fix <pkg>` (introduced in
[ADR-0007](./0007-respect-system-installed-packages.md)) re-verifies every
entry in a package's `.lapt/system-deps`, selectively re-fetches anything
no longer system-satisfied, re-bundles it into `opt/<pkg>/`, and
conditionally regenerates the `.wrap` wrapper if that newly triggers one.
All of that partial-re-assemble logic exists to repair one rare case: a
system-satisfied dependency (ADR-0007's *skip* half) later disappearing
from the host. That's complex machinery for a case simpler to handle by
just reinstalling: `lapt remove <pkg> && lapt install <pkg>`, which
re-resolves the closure and rebuilds `opt/<pkg>/` from scratch — no
partial-state bookkeeping, no separate code path to keep correct.

This amends ADR-0007's "Dependencies: skip, track, repair via `lapt fix`"
section. The **skip** half stands unchanged — a system-satisfied
dependency still isn't fetched or bundled at install time. The **track**
half (`opt/<pkg>/.lapt/system-deps`, and the `lapt::system_deps_write`
call in `_install_one` that populated it) and the **repair** half (`fix`
itself) are both dropped — with `fix` gone, nothing ever reads
`.lapt/system-deps` again, so recording it is dead weight.

Frozen-private's (ADR-0001) accepted staleness window — a skipped
dependency can drift if the host's package manager later changes it — is
now closed by reinstall instead of by `fix`. This is a strictly simpler
repair story: no separate "is a repair needed" check, no partial-bundle
code path, at the cost of a full reinstall instead of a partial one for
what's already a rare case.

`bundle_apply`'s `rewrite_pc` parameter existed only because `fix` called
it with `rewrite_pc=0` (bundling into an existing `opt/<pkg>/` without
rewriting embedded `.pc` paths — since a package that was already
correctly assembled shouldn't need its `.pc` files touched again). With
`fix` gone, `bundle_apply` has a single caller (`cmd_install`), which
always wants the rewrite; the parameter collapses out and the rewrite
branch always runs.
