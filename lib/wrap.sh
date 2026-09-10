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
}

lapt::wrap_top_level_bins() {
  local work_dir=$1 opt_dir=$2 pkg=$3 lib_dir=$4 bin_dir=$5
  local rel src origin
  while IFS=$'\t' read -r rel src origin; do
    [[ $origin == "$pkg" && $rel == bin/* ]] || continue
    mv "$work_dir/$rel" "$work_dir/$rel.real"
    lapt::write_wrapper "$work_dir/$rel" "$opt_dir/$rel.real" "$lib_dir" "$bin_dir"
  done
}

lapt::write_wrapper() {
  local script_path=$1 exec_target=$2 lib_dir=$3 bin_dir=$4
  {
    echo '#!/bin/sh'
    [[ -n $lib_dir ]] && printf 'export LD_LIBRARY_PATH="%s:$LD_LIBRARY_PATH"\n' "$lib_dir"
    [[ -n $bin_dir ]] && printf 'export PATH="%s:$PATH"\n' "$bin_dir"
    printf 'exec "%s" "$@"\n' "$exec_target"
  } > "$script_path"
  chmod +x "$script_path"
}
