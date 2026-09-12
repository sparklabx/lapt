lapt::expose_add() {
  local pkg=$1
  local opt_dir="$LAPT_HOME/opt/$pkg"
  local rel src origin dest miss=0
  while IFS=$'\t' read -r rel src origin; do
    [[ $origin == "$pkg" ]] || continue
    case $rel in
      bin/*|share/man/*) ;;
      *) continue ;;
    esac
    dest="$LAPT_HOME/$rel"
    if [[ -L $dest && $(readlink -f "$dest") == "$opt_dir/$rel" ]]; then
      echo "$rel"
      continue
    fi
    mkdir -p "$(dirname "$dest")"
    if ln -s "$opt_dir/$rel" "$dest" 2>/dev/null; then
      echo "$rel"
    else
      echo "lapt: warning: could not expose $rel: $dest already exists" >&2
      miss=1
    fi
  done
  return "$miss"
}

lapt::expose_remove() {
  local pkg=$1
  local opt_dir="$LAPT_HOME/opt/$pkg"
  local rel dest
  while IFS= read -r rel; do
    dest="$LAPT_HOME/$rel"
    [[ -L $dest ]] || continue
    [[ $(readlink -f "$dest") == "$opt_dir/$rel" ]] || continue
    rm -f "$dest"
  done
}
