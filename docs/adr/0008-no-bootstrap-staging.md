# No bootstrap staging, no toolchain truncation

Considered: since `lapt` itself shells out to external tools before it can
install anything, does it need a bootstrap mechanism — skipping code
sections whose required tool is missing, or installing tools one at a time
and enabling the sections that depend on them as each becomes available?

**lapt's actual toolchain, checked against Debian's own priority metadata**
(`dpkg-query -W -f='${Priority} ${Essential}'`) on a stock bookworm host:
`apt` (required), `dpkg` (required, essential), `coreutils` (required,
essential), `findutils` (required, essential), `grep` (required,
essential), `sed` (required, essential), `bash` (required, essential).
`apt`/`dpkg` are irreducible — they're what `lapt` wraps (`apt-get
download`, `apt-cache depends --recurse`, `dpkg -x`, `dpkg-deb -c`,
`dpkg -s`, `dpkg --compare-versions`); no code path can skip them, since
without them there is nothing left for lapt to do. The rest
(`findutils`/`grep`/`sed`) are individually truncatable in principle —
hardlink-count checks (ADR-0006) can use `stat -c %h` instead of `find`,
and line parsing (closure output, `dpkg-deb -c` listings, `.pc` rewrites)
can use bash string matching (`[[ $line == Depends:* ]]`,
`${line#prefix}`) instead of `grep`/`sed`.

Decided: build neither a staged-bootstrap mechanism nor a
toolchain-truncation rewrite. All seven tools above are `Priority:
required` as a set on any Debian/Ubuntu install — Debian's own package
system guarantees them together, not individually, so there is no real
host where `apt`+`dpkg` are present but `findutils`/`grep`/`sed` are not.
Truncating `find`/`grep`/`sed` calls into hand-rolled bash matching would
trade well-tested parsing tools for more fragile string matching, in
exchange for portability to a target that doesn't exist. A host stripped
enough to lack `findutils`/`grep`/`sed` (a custom `debootstrap
--variant=minbase`, a distroless-style image) is also a host lapt cannot
bootstrap into regardless, since `apt`/`dpkg` are gone too — and that
failure mode is unsolvable by staging or skipping code sections, since the
very tools needed to fetch and install anything are the ones missing.

This is the same class of exclusion as vendor being out of scope for
ADR-0007: an unsupported base is a documented assumption, not a case to
engineer around. If a real target ever ships `apt` and `dpkg` without
`coreutils`/`findutils`/`grep`/`sed`, revisit — no such combination exists
on Debian/Ubuntu today.
