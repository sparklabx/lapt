lapt::cache_entry_path() {
  local name=$1 version=$2
  echo "${LAPT_CACHE_ROOT:-$HOME/.local/share/lapt/cache}/${name}_${version}"
}
