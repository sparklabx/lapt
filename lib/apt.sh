lapt::is_system_satisfied() {
  local group=$1
  local -a names
  IFS='|' read -r -a names <<<"$group"
  local name status installed candidate line
  for name in "${names[@]}"; do
    status=$(dpkg -s "$name" 2>/dev/null) || continue
    installed=""
    while IFS= read -r line; do
      case $line in
        Status:*installed) : ;;
        Status:*) installed="" ; break ;;
        Version:\ *) installed=${line#Version: } ;;
      esac
    done <<<"$status"
    [[ -n $installed ]] || continue
    candidate=$(apt-cache policy "$name" 2>/dev/null | sed -n 's/^  Candidate: //p')
    [[ -n $candidate ]] || continue
    dpkg --compare-versions "$installed" ge "$candidate" || continue
    printf '%s %s\n' "$name" "$installed"
    return 0
  done
  return 1
}

lapt::pick_candidate() {
  local group=$1
  local -a names
  IFS='|' read -r -a names <<<"$group"
  local name candidate
  for name in "${names[@]}"; do
    candidate=$(apt-cache policy "$name" 2>/dev/null | sed -n 's/^  Candidate: //p')
    [[ -n $candidate ]] || continue
    printf '%s %s\n' "$name" "$candidate"
    return 0
  done
  return 1
}

lapt::_apt_finalize_providers() {
  local owner=$1 virtual=$2; shift 2
  local -a providers=("$@")
  local groups=${blockdeps[$owner]}
  local last=$groups prefix=""
  if [[ $groups == *$'\n'* ]]; then
    last=${groups##*$'\n'}
    prefix=${groups%$'\n'*}
  fi
  local -a toks=() newtoks=()
  IFS='|' read -r -a toks <<<"$last"
  local t e dup
  for t in "${toks[@]}"; do
    [[ $t == "$virtual" && $virtual == \<*\> ]] && continue
    newtoks+=("$t")
  done
  for t in "${providers[@]}"; do
    dup=0
    for e in "${newtoks[@]}"; do [[ $e == "$t" ]] && { dup=1; break; }; done
    (( dup )) || newtoks+=("$t")
  done
  local joined
  joined=$(IFS='|'; echo "${newtoks[*]}")
  if [[ -n $prefix ]]; then
    blockdeps[$owner]="$prefix"$'\n'"$joined"
  else
    blockdeps[$owner]="$joined"
  fi
}

lapt::resolve_closure() {
  local line cur="" pending=""
  local -A blockdeps=()
  local -a block_order=()
  local top=""
  local collecting=0 last_owner="" last_virtual=""
  local -a providers=()

  while IFS= read -r line; do
    if (( collecting )) && [[ $line =~ ^\ \ \ \ ([^[:space:]].*)$ ]]; then
      providers+=("${BASH_REMATCH[1]}")
      continue
    fi
    if (( collecting )); then
      lapt::_apt_finalize_providers "$last_owner" "$last_virtual" "${providers[@]}"
      collecting=0 last_owner="" last_virtual="" providers=()
    fi

    if [[ $line != ' '* ]]; then
      cur=$line
      [[ -z ${blockdeps[$cur]+x} ]] && { blockdeps[$cur]=""; block_order+=("$cur"); }
      [[ -z $top ]] && top=$cur
      continue
    fi
    if [[ $line =~ ^\ \|(Depends|PreDepends):\ (.*)$ ]]; then
      pending+="${pending:+|}${BASH_REMATCH[2]}"
      continue
    fi
    if [[ $line =~ ^\ \ (Depends|PreDepends):\ (.*)$ ]]; then
      local name=${BASH_REMATCH[2]}
      local group
      if [[ -n $pending ]]; then
        group="$pending|$name"
        pending=""
      else
        group=$name
      fi
      blockdeps[$cur]+="${blockdeps[$cur]:+$'\n'}$group"
      collecting=1 last_owner=$cur last_virtual=$name providers=()
      continue
    fi
    # 4-space-indented line with no preceding Depends/PreDepends: unreachable
    # per apt-cache's own grammar (providers always follow a dep line).
  done
  (( collecting )) && lapt::_apt_finalize_providers "$last_owner" "$last_virtual" "${providers[@]}"

  [[ -z $top ]] && return 0

  local -a queue=("$top") order=()
  local -A visited=([$top]=1)
  local qi=0 node depgroups g
  while (( qi < ${#queue[@]} )); do
    node=${queue[qi]}; ((qi++))
    depgroups=${blockdeps[$node]:-}
    [[ -z $depgroups ]] && continue
    while IFS= read -r g; do
      [[ -z $g ]] && continue
      if [[ -n ${visited[$g]+x} ]]; then continue; fi
      visited[$g]=1
      order+=("$g")
      [[ $g != *"|"* ]] && queue+=("$g")
    done <<<"$depgroups"
  done

  printf '%s\n' "${order[@]}"
}
