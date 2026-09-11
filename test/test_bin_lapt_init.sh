#!/usr/bin/env bash
# Subprocess tests for bin/lapt, seam: `lapt init` only. No apt fakes needed --
# init only ever writes $LAPT_HOME/env and prints instructions.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAPT="$ROOT/bin/lapt"

fail=0
assert_eq() {
  local desc=$1 expected=$2 actual=$3
  if [[ $expected != "$actual" ]]; then
    printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' "$desc" "$expected" "$actual"
    fail=1
  fi
}
assert_exit0() {
  local desc=$1 rc=$2
  [[ $rc -eq 0 ]] || { printf 'FAIL: %s\n  expected exit 0, got %s\n' "$desc" "$rc"; fail=1; }
}

# env keeps $HOME literal (not this machine's expanded path) so it stays
# correct if $HOME ever differs (e.g. dotfiles synced to another user/machine)
# -- verified by sourcing it under a different HOME than it was written under
test_init_writes_env() {
  export HOME; HOME=$(mktemp -d)
  local lapt_home="$HOME/.lapt"

  local out rc
  out=$("$LAPT" init 2>&1)
  rc=$?
  assert_exit0 "init exits 0" "$rc"
  case $out in
    *"$lapt_home/env"*) ;;
    *) printf 'FAIL: %s\n  expected output to mention env path, got: %s\n' "init prints env path" "$out"; fail=1 ;;
  esac

  local other_home; other_home=$(mktemp -d)
  local path_out manpath_out
  path_out=$(HOME="$other_home" PATH="/usr/bin" bash -c '. "$1"; echo "$PATH"' _ "$lapt_home/env")
  manpath_out=$(HOME="$other_home" MANPATH="" bash -c '. "$1"; echo "$MANPATH"' _ "$lapt_home/env")
  assert_eq "PATH prepended relative to sourcing shell's own \$HOME" \
    "$other_home/.lapt/bin:/usr/bin" "$path_out"
  assert_eq "MANPATH prepended relative to sourcing shell's own \$HOME" \
    "$other_home/.lapt/share/man::" "$manpath_out"

  rm -rf "$HOME" "$other_home"; unset HOME
}

# re-sourcing env (e.g. a nested shell also sourcing ~/.bashrc) must not
# keep prepending duplicate entries -- mirrors the addpath() dedup idiom
# already used elsewhere in this user's own ~/.bashrc
test_init_resourcing_env_is_idempotent() {
  export HOME; HOME=$(mktemp -d)
  "$LAPT" init >/dev/null 2>&1
  local lapt_home="$HOME/.lapt"

  local path_out manpath_out
  path_out=$(PATH="/usr/bin" bash -c '. "$1"; . "$1"; echo "$PATH"' _ "$lapt_home/env")
  manpath_out=$(MANPATH="" bash -c '. "$1"; . "$1"; echo "$MANPATH"' _ "$lapt_home/env")
  assert_eq "PATH entry not duplicated on re-source" "$lapt_home/bin:/usr/bin" "$path_out"
  assert_eq "MANPATH entry not duplicated on re-source" "$lapt_home/share/man::" "$manpath_out"

  rm -rf "$HOME"; unset HOME
}

# never touches ~/.bashrc or anything outside $LAPT_HOME -- init only prints
# a suggestion, per the user's explicit "do not prompt, just notice" decision
test_init_never_touches_bashrc() {
  export HOME; HOME=$(mktemp -d)
  printf 'existing content\n' > "$HOME/.bashrc"

  "$LAPT" init >/dev/null 2>&1

  assert_eq ".bashrc left untouched" "existing content" "$(cat "$HOME/.bashrc")"

  rm -rf "$HOME"; unset HOME
}

# re-running init regenerates env unconditionally (unlike vendor's env.sh,
# which is only written if missing) -- init is an explicit one-off action
test_init_regenerates_env() {
  export HOME; HOME=$(mktemp -d)
  local lapt_home="$HOME/.lapt"
  mkdir -p "$lapt_home"
  printf 'stale\n' > "$lapt_home/env"

  "$LAPT" init >/dev/null 2>&1

  if grep -q 'stale' "$lapt_home/env"; then
    printf 'FAIL: %s\n  expected env to be regenerated, stale content still present\n' "init regenerates env"
    fail=1
  fi

  rm -rf "$HOME"; unset HOME
}

# LAPT_HOME is not configurable -- a pre-set env var is ignored, $HOME/.lapt
# is used regardless
test_init_ignores_preset_lapt_home_env_var() {
  export HOME; HOME=$(mktemp -d)
  local other_dir; other_dir=$(mktemp -d)

  LAPT_HOME="$other_dir" "$LAPT" init >/dev/null 2>&1

  if [[ -e "$other_dir/env" ]]; then
    printf 'FAIL: %s\n  expected LAPT_HOME env var to be ignored, env written there anyway\n' "preset LAPT_HOME is ignored"
    fail=1
  fi
  if [[ ! -f "$HOME/.lapt/env" ]]; then
    printf 'FAIL: %s\n  expected env under $HOME/.lapt regardless of LAPT_HOME env var\n' "always writes to \$HOME/.lapt"
    fail=1
  fi

  rm -rf "$HOME" "$other_dir"; unset HOME
}

test_init_writes_env
test_init_resourcing_env_is_idempotent
test_init_never_touches_bashrc
test_init_regenerates_env
test_init_ignores_preset_lapt_home_env_var
if [[ $fail -eq 0 ]]; then echo "OK"; else exit 1; fi
