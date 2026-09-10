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
