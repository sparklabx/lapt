lapt::expose_add() {
  local opt_dir=$1 dest_home=$2 pkg=$3
  local rel src origin dest miss=0
  while IFS=$'\t' read -r rel src origin; do
    [[ $origin == "$pkg" ]] || continue
    case $rel in
      bin/*|share/man/*|share/bash-completion/completions/*|share/applications/*|share/icons/*|share/mime/*) ;;
      *) continue ;;
    esac
    dest="$dest_home/$rel"
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
  local opt_dir=$1 dest_home=$2
  local rel dest
  while IFS= read -r rel; do
    dest="$dest_home/$rel"
    [[ -L $dest ]] || continue
    [[ $(readlink -f "$dest") == "$opt_dir/$rel" ]] || continue
    rm -f "$dest"
  done
}
