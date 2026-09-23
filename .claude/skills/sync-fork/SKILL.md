---
name: sync-fork
description: Pull the instructor's latest lecture and project notebooks into this fork. Use when the user says their instructor updated a lecture or project, or asks to sync/update the fork, get the latest notebooks, or pull upstream changes into learn-ml-by-building.
---

# Sync this fork with the instructor's repo

This repo is a fork of the course repo. Students work in the same notebook files the
instructor edits, so a sync has to bring in upstream changes **without losing local
work** — which usually sits uncommitted in the working tree.

- **origin** — `DroidRobot/learn-ml-by-building` (the student's fork on GitHub)
- **upstream** — `jinming99/learn-ml-by-building` (the instructor's repo)

Flow: `upstream → local main → origin`. Merging locally first (rather than syncing the
fork on GitHub and pulling) keeps uncommitted work safe and surfaces conflicts on the
machine where they can actually be resolved.

## Run it

```bash
.claude/skills/sync-fork/scripts/sync-fork.sh --dry-run   # preview, changes nothing
.claude/skills/sync-fork/scripts/sync-fork.sh             # merge + push to the fork
.claude/skills/sync-fork/scripts/sync-fork.sh --no-push   # local only
```

Run `--dry-run` first whenever the working tree is dirty, and show the user the incoming
commits and file list before doing the real run. The script is safe by default: it never
force-pushes, never discards uncommitted work, and never resolves a conflict itself.

What it does: adds the `upstream` remote if missing (via `gh repo view --json parent`),
fetches, reports the incoming commits, **warns when an incoming file is one the user has
edited locally**, stashes uncommitted work including untracked files, fast-forwards (or
merges if the fork has its own commits), re-applies the stash, and pushes to origin.

It exits non-zero and stops at the first conflict, leaving the stash intact.

## Conflicts

Report what conflicted and hand the decision to the user — do not auto-resolve.

**Notebooks (`.ipynb`) are the common case and the ugly one.** They are JSON, so git
conflict markers land inside cell arrays and usually make the file unopenable in Jupyter.
Don't hand-merge the JSON. Offer the user these instead:

1. **Keep your work, take theirs alongside** — the usual choice for a lecture notebook
   the student has been working in:
   ```bash
   cp "Lecture N .../notebook.ipynb" "Lecture N .../notebook-MYWORK.ipynb"   # if readable
   git checkout --theirs -- "Lecture N .../notebook.ipynb"
   git add "Lecture N .../notebook.ipynb"
   ```
   Then tell them which cells to carry over from `-MYWORK`.
2. **Keep only yours** — `git checkout --ours -- <path> && git add <path>`.
3. **Inspect both first** — `git show :2:<path>` (yours) and `git show :3:<path>`
   (instructor's) write clean copies to compare.

If the conflict arose during `git stash pop`, the stash entry still exists: resolve, `git
add`, then `git stash drop`. Never `git checkout --force` or `git reset --hard` with a
dirty tree — that is how a student loses a week of work.

For `utils/` and other `.py` files, a normal three-way merge is fine.

## Notes

- Requires the `gh` CLI authenticated only for the first run (to discover the parent);
  after that plain git is enough.
- The script refuses to run from a non-default branch — tell the user to
  `git checkout main` rather than working around it.
- Datasets (`Lecture*/*.csv`, `Lecture*/*.xlsx`) are gitignored and never travel with a
  sync. If a new lecture needs data, the student downloads it separately.
- If the user only wants to *see* what changed without syncing:
  `git fetch upstream && git log --oneline HEAD..upstream/main`.
- Files that exist only in the fork (including this skill under `.claude/skills/`) are
  never deleted by a sync: the merge keeps anything the instructor didn't touch, and the
  "files they change" preview uses a three-dot diff so they aren't listed as deletions.
  If a preview ever seems to show them removed, that is a display bug, not a real change.
