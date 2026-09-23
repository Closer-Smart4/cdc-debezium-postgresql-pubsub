# Sync main

Fast-forward the local default branch to match `origin`. This does not push feature branches and does not rewrite history.

Shared rules, origin authentication, fast-forward, and merged-branch cleanup: [shared-git.md](shared-git.md).

## Extra hard rules

- Do not stash, commit, or switch away from a dirty branch to make the sync work.
- Stay on the current branch unless it is already the default branch and the working tree is clean.

## 1. Inspect

Run these in parallel:

- `git status -sb`
- `git branch --show-current`
- `git rev-parse --abbrev-ref origin/HEAD`
- `git rev-parse <default-branch> origin/<default-branch>` (after fetch if needed)

## 2. Fast-forward

Follow **Fast-forward local default branch** in [shared-git.md](shared-git.md).

## 3. Cleanup and report

Suggest merged-branch cleanup ([shared-git.md](shared-git.md)). This is the usual moment leftover feature branches become fully merged.

State:

- current branch (unchanged unless it was a clean default branch)
- `<default-branch>` before → after (`git rev-parse --short`)
- whether it was already up to date, fast-forwarded, or blocked
- leftover dirty or untracked files, if any
- fully merged branches suggested for deletion
