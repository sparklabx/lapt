lapt::resolve_closure() {
  local first=1 line
  local -A seen=()
  while IFS= read -r line; do
    [[ $line == ' '* ]] && continue
    if (( first )); then
      first=0
      continue
    fi
    [[ -n ${seen[$line]+x} ]] && continue
    seen[$line]=1
    printf '%s\n' "$line"
  done
}
