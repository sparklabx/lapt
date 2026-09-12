lapt::cache_entry_path() {
  local name=$1 version=$2
  echo "$LAPT_HOME/cache/${name}_${version}"
}

lapt::cache_referenced() {
  local entry_dir=$1
  [[ -n $(find "$entry_dir" \( -type f -o -type l \) ! -links 1 -print -quit) ]]
}

lapt::cache_ensure() {
  local name=$1 version=$2
  local entry; entry=$(lapt::cache_entry_path "$name" "$version")
  [[ -d $entry ]] && return 0

  local scratch; scratch=$(mktemp -d)
  echo "lapt: fetching ${name} ${version}..." >&2
  if ! (cd "$scratch" && apt-get download "${name}=${version}"); then
    echo "lapt: error: apt-get download failed for $name=$version" >&2
    rm -rf "$scratch"
    return 1
  fi
  local debfile; debfile=$(printf '%s\n' "$scratch"/*.deb)

  local fields path
  while read -r -a fields; do
    # directories outside usr/ are inert scaffolding: bundle_manifest only
    # ever walks -type f from a cache entry, so an empty dir here is never
    # read or flattened. CONTEXT.md's Scope-restricted package definition is
    # "every file under usr/**" -- only actual files are checked.
    [[ ${fields[0]:0:1} == d ]] && continue
    path=${fields[5]}
    case $path in
      ./|./usr|./usr/*) ;;
      *)
        echo "lapt: error: $name $version has a file outside usr/: $path" >&2
        rm -rf "$scratch"
        return 1
        ;;
    esac
  done < <(dpkg-deb -c "$debfile")

  local parent tmp
  parent=$(dirname "$entry")
  mkdir -p "$parent"
  tmp=$(mktemp -d "$parent/.tmp.XXXXXX")
  dpkg -x "$debfile" "$tmp"
  mv "$tmp" "$entry"
  rm -rf "$scratch"
}
