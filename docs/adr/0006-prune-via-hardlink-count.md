# Cache pruning via hardlink count, no manifest

Cache entries were declared permanent/never-evicted (see **Cache entry**,
`CONTEXT.md`) because nothing tracked whether one was still in use by an
assembled or vendored package. But `assemble` and `vendor` both consume cache
entries by hardlinking (ADR-0001, ADR-0002 — no manifest, state re-derived
from `opt/*/`) — so the filesystem already holds the answer: a cache file's
link count is exactly 1 plus the number of live hardlinks pointing at it. If
every file and symlink in a cache entry has link count 1, nothing outside
the cache references it.

Exception: `.pc` files are copied-and-rewritten by `vendor`, never
hardlinked (see **Vendor**), so their link count never reflects vendor
usage. Not a safety problem — the vendored copy is independent, so pruning
the cache entry after vendoring never breaks it. The check still only needs
link count 1 on every entry to prune; a `.pc` file's link count is always 1
regardless, no special-casing required.

Decided: `lapt prune` (no args) walks every cache entry under
`$HOME/.local/share/lapt/cache/`, and for each one, checks every file and
symlink under it via `stat -c %h` (or `find -links 1`). If none has a link
count above 1, the whole cache entry directory is removed. Entries with any
still-linked file are left alone. No manifest, no ownership tracking — this
reuses the same "re-derive from filesystem state" approach as install/remove.
