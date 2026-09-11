lapt::bundle_manifest() {
  local dest_dir=$1; shift
  local spec name version origin cache_path f rel
  local -a rows=()
  local -A seen=()

  if [[ -d $dest_dir ]]; then
    while IFS= read -r -d '' f; do
      rel=${f#"$dest_dir"/}
      seen[$rel]=existing
      rows+=("$rel"$'\t'"$f"$'\t'"existing")
    done < <(find "$dest_dir" \( -type f -o -type l \) -print0)
  fi

  for spec in "$@"; do
    IFS=$'\t' read -r name version origin <<<"$spec"
    cache_path=$(lapt::cache_entry_path "$name" "$version")
    while IFS= read -r -d '' f; do
      rel=${f#"$cache_path"/usr/}
      if [[ $rel =~ ^(lib|include|pkgconfig)/[a-z0-9_]+-linux-gnu[a-z0-9]*/(.*)$ ]]; then
        rel="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
      fi
      if [[ -n ${seen[$rel]+x} ]]; then
        echo "lapt: error: collision at $rel (${seen[$rel]} vs $origin)" >&2
        return 1
      fi
      seen[$rel]=$origin
      rows+=("$rel"$'\t'"$f"$'\t'"$origin")
    done < <(find "$cache_path" \( -type f -o -type l \) -print0)
  done

  printf '%s\n' "${rows[@]}"
}

lapt::bundle_apply() {
  local dest_dir=$1 rewrite_pc=$2
  local rel src origin dest
  while IFS=$'\t' read -r rel src origin; do
    [[ $origin == existing ]] && continue
    dest="$dest_dir/$rel"
    mkdir -p "$(dirname "$dest")"
    if [[ $rewrite_pc == 1 && $rel == *.pc ]]; then
      # Most .pc files reference ${libdir}/${includedir} in Libs:/Cflags: and
      # need no further rewrite once those variables are fixed above. A few
      # (e.g. Debian's ncurses.pc) hardcode an absolute -L/-I path directly in
      # Libs:/Cflags: instead -- rewrite those too, to the same place their
      # own files just landed.
      sed -E -e "s|^prefix=.*|prefix=$dest_dir|" \
          -e "s|^libdir=.*|libdir=$dest_dir/lib|" \
          -e "s|^includedir=.*|includedir=$dest_dir/include|" \
          -e "s|-L/[^ ]+|-L$dest_dir/lib|g" \
          -e "s|-I/[^ ]+|-I$dest_dir/include|g" \
          "$src" > "$dest"
    else
      ln "$src" "$dest"
    fi
  done
}
