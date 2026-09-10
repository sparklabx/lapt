lapt::cache_entry_path() {
  local name=$1 version=$2
  echo "${LAPT_CACHE_ROOT:-$HOME/.local/share/lapt/cache}/${name}_${version}"
}

lapt::cache_referenced() {
  local entry_dir=$1
  [[ -n $(find "$entry_dir" \( -type f -o -type l \) ! -links 1 -print -quit) ]]
}
