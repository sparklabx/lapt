lapt::needs_wrapper() {
  local pkg=$1
  local rel src origin has_lib=0 has_bin=0
  while IFS=$'\t' read -r rel src origin; do
    case $rel in
      lib/*) has_lib=1 ;;
      bin/*) [[ $origin != "$pkg" ]] && has_bin=1 ;;
    esac
  done
  [[ $has_lib == 1 ]] && echo lib
  [[ $has_bin == 1 ]] && echo bin
  [[ -f "$ROOT/pkgenv/$pkg" ]] && echo pkgenv
}

# Debian policy (ch. 9) recommends private, binary-only support files a
# package needs but doesn't expose live under /usr/lib/<package-name>/ -- a
# compiled-in RUNPATH that assumes that system path is wrong once lapt
# relocates the package under $HOME/.lapt/opt.
# LD_LIBRARY_PATH outranks RUNPATH in the dynamic linker's search order, so
# listing that one policy-conventional subdir (if present) fixes it without
# touching the binary. check_dir/final_dir split matches lapt::pkgenv_lines:
# check_dir is where the dir is checked to exist right now, final_dir is what
# the returned path is built from (where it'll actually run from).
lapt::lib_dir_list() {
  local check_dir=$1 final_dir=$2 pkg=$3
  local dirs=$final_dir
  [[ -d "$check_dir/$pkg" ]] && dirs+=":$final_dir/$pkg"
  echo "$dirs"
}

lapt::wrap_top_level_bins() {
  local work_dir=$1 opt_dir=$2 pkg=$3 lib_dir=$4 bin_dir=$5
  local rel src origin
  while IFS=$'\t' read -r rel src origin; do
    [[ $origin == "$pkg" && $rel == bin/* ]] || continue
    mv "$work_dir/$rel" "$work_dir/$rel.real"
    lapt::write_wrapper "$work_dir/$rel" "$opt_dir/$rel.real" "$lib_dir" "$bin_dir" "$pkg" "$work_dir" "$opt_dir"
  done
}

# pkgenv/<pkg>, if present, is a declarative VAR=relative/path list (never
# shell) of post-install env vars a package's compiled-in defaults need
# (e.g. git's GIT_EXEC_PATH) -- see docs/adr/0015. A line is skipped if its
# resolved path doesn't exist, so a dependency that turned out to be
# system-satisfied (and so was never bundled) doesn't leave a wrapper
# exporting a broken path. check_dir is where the files physically live
# right now (existence is tested there); final_dir is what the exported
# value points at -- during install these differ (work_dir vs. the not-yet-
# existing opt_dir the mv will land on, same split bundle_apply's
# dest_dir/final_dir already makes), while a same-dir refresh (rewrap) passes
# the same path for both.
lapt::pkgenv_lines() {
  local pkg=$1 check_dir=$2 final_dir=$3
  [[ -n $pkg ]] || return 0
  local pkgenv_file="$ROOT/pkgenv/$pkg"
  [[ -f $pkgenv_file ]] || return 0
  local line var relpath
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    var=${line%%=*}
    relpath=${line#*=}
    if [[ ! -e "$check_dir/$relpath" ]]; then
      echo "lapt: pkgenv/$pkg declares $var=$relpath, but $check_dir/$relpath doesn't exist -- skipping" >&2
      continue
    fi
    printf 'export %s="%s"\n' "$var" "$final_dir/$relpath"
  done < "$pkgenv_file"
}

lapt::write_wrapper() {
  local script_path=$1 exec_target=$2 lib_dir=$3 bin_dir=$4 pkg=${5:-} check_dir=${6:-} final_dir=${7:-}
  {
    echo '#!/bin/sh'
    [[ -n $lib_dir ]] && printf 'export LD_LIBRARY_PATH="%s:$LD_LIBRARY_PATH"\n' "$lib_dir"
    [[ -n $bin_dir ]] && printf 'export PATH="%s:$PATH"\n' "$bin_dir"
    lapt::pkgenv_lines "$pkg" "$check_dir" "$final_dir"
    printf 'exec "%s" "$@"\n' "$exec_target"
  } > "$script_path"
  chmod +x "$script_path"
}
