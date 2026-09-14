# Building tmux against vendored libraries

Walkthrough for building tmux from source without installing
`libevent-dev`/`libncurses-dev` system-wide, using `lapt install` +
`lapt vendor`.

## 1. Install the build dependencies

```
lapt install libevent-dev libncurses-dev
```

Each package is assembled into its own `opt/<pkg>`, dependency closure
resolved, system-satisfied members skipped, and `.pc` files rewritten to
point at that package's own `opt/<pkg>`.

## 2. Source the environment

```
. <(lapt vendor libevent-dev libncurses-dev)
```

Requires both packages already installed (step 1) — `vendor` does no
fetching of its own. Prints `PATH`, `LD_LIBRARY_PATH`, `CPATH`, and
`PKG_CONFIG_PATH` lines pointing at each package's own `opt/<pkg>` (in the
order given), which the process substitution above sources directly. The
printed script dedups via the same guard `lapt init`'s env file uses, so
it's also safe to persist into a shell startup file instead of sourcing ad
hoc.

## 3. A build-time gotcha: bison

If `bison` itself came from lapt rather than the system package, its own
hardcoded defaults (`/usr/share/bison`, `/usr/bin/m4`) won't resolve — lapt
doesn't put files at those absolute paths. `bison` runs *during* `make`
(generating the parser from the grammar file), so export its own supported
overrides before building, not after:

```
export BISON_PKGDATADIR="$HOME/.lapt/opt/bison/share/bison"
export M4="$HOME/.lapt/opt/bison/bin/m4"
```

This is upstream bison's own behavior, unrelated to lapt's vendor/wrap
machinery — only needed when `bison` itself is lapt-installed instead of
the system's.

## 4. Configure and build

`--prefix` can be anywhere — pick a normal build/install directory, same as
any other from-source build.

```
cd tmux-<version>
./configure --prefix="<install-dir>"
make -j"$(nproc)"
```

`pkg-config` finds the installed `ncurses`/`libevent` `.pc` files via
`PKG_CONFIG_PATH`; those `.pc` files carry the include/lib paths into the
compiler and linker.

## 5. Make it reachable

```
make install
ln -s "<install-dir>/bin/tmux" "$HOME/.local/bin/tmux"
```

`tmux` still needs the vendored libraries to be reachable at runtime, so
step 2's env script must be sourced in any shell that runs it — the symlink
alone doesn't carry `LD_LIBRARY_PATH` with it.
