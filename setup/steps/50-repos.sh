# shellcheck shell=bash disable=SC2154  # profile arrays come from lib.sh
# clones the profile's repos (clone only — each project owns its own build + deploy)

repo_dir() { [[ $1 == scripts ]] && echo "$HOME/scripts" || echo "$HOME/projects/$1"; }

apply_repos() {
  if ! gh auth status >/dev/null 2>&1; then
    warn "github not logged in — skipping repos (gh auth login, then re-run)"; return
  fi
  local r d owner
  owner=${github_user:-$(gh api user --jq .login)}
  mkdir -p "$HOME/projects"
  for r in "${repos[@]}"; do
    d=$(repo_dir "$r")
    if [[ -d $d/.git ]]; then ok "$d"; continue; fi
    if ! gh repo view "$owner/$r" >/dev/null 2>&1; then warn "no repo $owner/$r — skipped"; continue; fi
    gh repo clone "$owner/$r" "$d" -- -q
    did "$d"
  done
}

check_repos() {
  local r d0=$DRIFT
  for r in "${repos[@]}"; do [[ -d $(repo_dir "$r")/.git ]] || drift "not cloned: $r"; done
  ((DRIFT > d0)) || ok "${#repos[@]} repos cloned"
}
