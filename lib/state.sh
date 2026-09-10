lapt::version_write() {
  local opt_dir=$1 version=$2
  mkdir -p "$opt_dir/.lapt"
  {
    printf 'version=%s\n' "$version"
    printf 'installed=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$opt_dir/.lapt/version"
}

lapt::system_deps_write() {
  local opt_dir=$1
  mkdir -p "$opt_dir/.lapt"
  cat > "$opt_dir/.lapt/system-deps"
}
