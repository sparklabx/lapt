lapt::resolve_closure() {
  local line cur="" pending=""
  local -A blockdeps=()
  local -a block_order=()
  local top=""

  while IFS= read -r line; do
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
      continue
    fi
    # deeper-indented provider lines: not yet handled (later slice)
  done

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
