#!/usr/bin/env bash
# Sync this fork with the instructor's upstream repo, then push to origin.
#
#   ./sync-fork.sh              # check, merge, push
#   ./sync-fork.sh --dry-run    # show what would happen, change nothing
#   ./sync-fork.sh --no-push    # update local only, leave the GitHub fork alone
#
# Never force-pushes, never discards uncommitted work, never resolves a
# conflict on your behalf.

set -euo pipefail

DRY_RUN=0
NO_PUSH=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --no-push) NO_PUSH=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

run() {  # echo in dry-run, execute otherwise
  if [ "$DRY_RUN" = 1 ]; then echo "    [dry-run] $*"; else "$@"; fi
}

cd "$(git rev-parse --show-toplevel)"
echo "Repo: $(pwd)"
[ "$DRY_RUN" = 1 ] && echo "MODE: dry run — nothing will be changed."

# --- 1. upstream remote ------------------------------------------------------
if ! git remote get-url upstream >/dev/null 2>&1; then
  echo "No 'upstream' remote. Looking up this fork's parent on GitHub..."
  slug=$(gh repo view --json parent \
         --jq 'if .parent then .parent.owner.login + "/" + .parent.name else empty end' 2>/dev/null || true)
  if [ -z "$slug" ]; then
    echo "ERROR: could not determine the parent repo." >&2
    echo "Add it by hand:  git remote add upstream https://github.com/OWNER/REPO.git" >&2
    exit 1
  fi
  echo "Parent: $slug"
  run git remote add upstream "https://github.com/$slug.git"
fi
echo "Upstream: $(git remote get-url upstream 2>/dev/null || echo '(pending)')"

# --- 2. branch sanity --------------------------------------------------------
default_branch=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
default_branch=${default_branch:-main}
current_branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$current_branch" != "$default_branch" ]; then
  echo "ERROR: you are on '$current_branch', not '$default_branch'." >&2
  echo "Switch first:  git checkout $default_branch" >&2
  exit 1
fi

# --- 3. fetch ----------------------------------------------------------------
echo
echo "Fetching upstream..."
git fetch upstream --prune --quiet
git fetch origin  --prune --quiet

behind=$(git rev-list --count "HEAD..upstream/$default_branch")
ahead=$(git rev-list --count "upstream/$default_branch..HEAD")

if [ "$behind" = 0 ]; then
  echo "Already up to date with upstream/$default_branch. Nothing to pull."
  [ "$ahead" != 0 ] && echo "(You have $ahead local commit(s) upstream doesn't have — that's fine.)"
  exit 0
fi

echo
echo "=== $behind new commit(s) from your instructor ==="
git log --oneline --no-decorate "HEAD..upstream/$default_branch"
echo
echo "=== files they change ==="
git diff --stat "HEAD..upstream/$default_branch"

# --- 4. collision check: incoming files vs. your uncommitted work ------------
# Paths in this repo contain spaces, so git quotes them and awk-splitting mangles
# them. Strip the 2-char status code + space, then the surrounding quotes.
unquote() { sed 's/^"//; s/"$//'; }
incoming=$(git diff --name-only "HEAD..upstream/$default_branch" | unquote | sort -u)
yours=$(git status --porcelain | cut -c4- | unquote | sort -u)
collisions=$(comm -12 <(echo "$incoming") <(echo "$yours") || true)

if [ -n "$collisions" ]; then
  echo
  echo "!!! HEADS UP — the update touches files you have edited locally:"
  echo "$collisions" | sed 's/^/    /'
  echo
  echo "    Your edits are stashed and re-applied below. If a conflict lands in a"
  echo "    notebook, see the 'Conflicts' section of the skill before resolving."
fi

# --- 5. stash uncommitted work ----------------------------------------------
# '.claude' is excluded on purpose: this script lives there, and stashing it would
# delete the file out from under the running shell.
stashed=0
if [ -n "$(git status --porcelain -- ':!.claude')" ]; then
  echo
  echo "Stashing your uncommitted work (tracked + untracked)..."
  git status --short -- ':!.claude' | sed 's/^/    /'
  run git stash push --include-untracked \
      --message "sync-fork auto-stash $(date '+%Y-%m-%d %H:%M:%S')" -- ':!.claude'
  stashed=1
fi

# --- 6. merge ----------------------------------------------------------------
echo
if [ "$ahead" = 0 ]; then
  echo "Fast-forwarding $default_branch to upstream/$default_branch..."
  run git merge --ff-only "upstream/$default_branch"
else
  echo "Your branch has $ahead local commit(s); merging instead of fast-forwarding..."
  if [ "$DRY_RUN" = 1 ]; then
    echo "    [dry-run] git merge --no-edit upstream/$default_branch"
  elif ! git merge --no-edit "upstream/$default_branch"; then
    echo
    echo "MERGE CONFLICT. Your stash is safe (git stash list)." >&2
    echo "Resolve the files above, 'git add' them, then 'git commit'." >&2
    echo "To bail out entirely:  git merge --abort" >&2
    exit 1
  fi
fi

# --- 7. restore your work ----------------------------------------------------
if [ "$stashed" = 1 ]; then
  echo
  echo "Re-applying your stashed work..."
  if [ "$DRY_RUN" = 1 ]; then
    echo "    [dry-run] git stash pop"
  elif ! git stash pop; then
    echo
    echo "CONFLICT re-applying your edits. Nothing is lost — your work is still" >&2
    echo "in the stash (git stash list). Resolve the marked files, 'git add' them," >&2
    echo "then 'git stash drop' to clear the entry." >&2
    exit 1
  fi
fi

# --- 8. push to your fork ----------------------------------------------------
echo
if [ "$NO_PUSH" = 1 ]; then
  echo "--no-push: local is updated; your GitHub fork is untouched."
else
  echo "Pushing to your fork (origin/$default_branch)..."
  run git push origin "$default_branch"
fi

echo
echo "Done. Local, fork, and instructor are in sync."
if [ "$stashed" = 1 ]; then
  echo "Your uncommitted work was preserved:"
  git status --short -- ':!.claude' | sed 's/^/    /'
fi
exit 0
