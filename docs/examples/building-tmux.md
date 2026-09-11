# Building tmux against vendored libraries

Walkthrough for building tmux from source without installing
`libevent-dev`/`libncurses-dev` system-wide, using `lapt vendor`.

## 1. Vendor the build dependencies

```
lapt vendor <target-dir> libevent-dev libncurses-dev
```

Resolves each package's dependency closure, skips anything already
system-satisfied, and flattens libraries/headers/pkgconfig into
`<target-dir>`. Also writes `<target-dir>/env.sh`.

## 2. Source the environment

```
. <target-dir>/env.sh
```

Exports `PATH`, `LD_LIBRARY_PATH`, and `PKG_CONFIG_PATH` pointing at the
vendored tree.

## 3. A build-time gotcha: bison

If `bison` itself came from lapt rather than the system package, its own
hardcoded defaults (`/usr/share/bison`, `/usr/bin/m4`) won't resolve — lapt
doesn't put files at those absolute paths. `bison` runs *during* `make`
(generating the parser from the grammar file), so export its own supported
overrides before building, not after:

```
export BISON_PKGDATADIR="$HOME/.local/share/lapt/opt/bison/share/bison"
export M4="$HOME/.local/share/lapt/opt/bison/bin/m4"
```

This is upstream bison's own behavior, unrelated to lapt's vendor/wrap
machinery — only needed when `bison` itself is lapt-installed instead of
the system's.

## 4. Configure and build

`--prefix` can be anywhere — it's unrelated to `<target-dir>`. Just don't
point it *at* `<target-dir>` itself: `vendor` already populates
`<target-dir>/bin`, `<target-dir>/lib`, etc. with the vendored
dependencies, so installing the build there too would land in and mix with
those same directories. A subdirectory (e.g. `<target-dir>/out`) or a wholly
separate path both work fine.

```
cd tmux-<version>
./configure --prefix="<install-dir>"
make -j"$(nproc)"
```

`pkg-config` finds the vendored `ncurses`/`libevent` `.pc` files via
`PKG_CONFIG_PATH`; those `.pc` files carry the include/lib paths into the
compiler and linker.

## 5. Make it reachable

```
make install
ln -s "<install-dir>/bin/tmux" "$HOME/.local/bin/tmux"
```

`tmux` still needs the vendored libraries to be reachable at runtime, so
`env.sh` must be sourced in any shell that runs it — the symlink alone
doesn't carry `LD_LIBRARY_PATH` with it.
