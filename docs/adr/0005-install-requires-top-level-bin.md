# `install` hard-aborts if the top-level package has no own bin

`assemble` (ADR-0004) only ever exposes the top-level package's own `usr/bin`
entries. A top-level package that contributes none — pure library/data
packages, e.g. a `-dev` package meant for build-time linking — would still
assemble successfully but expose nothing on `PATH`, producing a silent
no-op result the user almost certainly didn't intend.

Decided: `lapt install <pkg>` hard-aborts before assembling if the top-level
closure member has no `usr/bin` of its own. Error to stderr, exit 1, with a
hint toward `lapt vendor` for library-only packages — that subcommand is the
correct path for build-time linking and has no such requirement.

This check only looks at the top-level package's own contribution, same
scoping as bin exposure — a dependency lacking `bin/` is normal and not
checked.
