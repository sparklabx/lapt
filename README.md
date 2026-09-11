# lapt

lapt installs Debian/Ubuntu packages under `$HOME/.local` — no sudo, no writes
to the system package database — for when you're on a shared or managed
machine without root but still want a real `.deb` package instead of building
from source. Under the hood it's a thin wrapper around `apt-get download` +
`dpkg -x`.

## Features

- **Each package in its own private tree, easy to remove** - no shared
  `/usr`, no apt dependency-hell: removing one package can't break another,
  because none of them share files.
- **Vendor libraries for building** - pulls a library's files into a plain
  folder and writes an `env.sh` you source to set the right env vars, so you
  can build something against it without installing a `-dev` package
  system-wide.
- **Respects packages the system already has** - before bundling a
  dependency, lapt checks if `dpkg` already provides it and reuses that
  instead of duplicating it. This keeps installs small and avoids two
  copies of the same library drifting apart. If the system copy later gets
  removed, `lapt fix <pkg>` detects the gap and bundles a replacement.

## Requirements

- Debian or Ubuntu (or a derivative) with `apt`/`dpkg` available
- bash 4+
- No sudo/root required

## Install

Clone the repo and symlink `bin/lapt` into `$HOME/.local/bin` (already on
`PATH` for most setups):

```
git clone <this-repo> lapt
ln -s "$PWD/lapt/bin/lapt" "$HOME/.local/bin/lapt"
```

Or, without the full repo (no tests/docs/git history), download a release
tarball from the Releases page, extract it anywhere, and symlink the same
way:

```
tar xzf lapt-<version>.tar.gz
ln -s "$PWD/lapt/bin/lapt" "$HOME/.local/bin/lapt"
```

## Quickstart

```
$ lapt install curl
$ curl -V
curl 8.4.0
```

## Commands

- `lapt install <pkg>` — bundle a package and its dependency closure into
  `opt/<pkg>`, generating a wrapper and exposing its own binaries as needed.
- `lapt remove <pkg>` — unlink a package's exposed files and delete its
  `opt/<pkg>` tree.
- `lapt list` — list installed packages.
- `lapt vendor <target-dir> <pkg...>` — flatten a package closure's
  libraries/headers/pkgconfig into a plain directory, for linking an external
  build against.
- `lapt fix <pkg>` — re-check a package's system-satisfied dependencies
  against current `dpkg` state and re-bundle anything no longer satisfied.
- `lapt prune` — reclaim cache entries no longer referenced by any installed
  or vendored package.
- `lapt expose <pkg>` — (re-)symlink an installed package's own binaries/man
  pages/etc. into `$HOME/.local`'s standard directories.

See [`CONTEXT.md`](CONTEXT.md) for the full domain model (closures, exposure,
vendoring, etc.) and [`docs/adr/`](docs/adr/) for the design decisions behind
them.

## License

MIT — see [LICENSE](LICENSE).
