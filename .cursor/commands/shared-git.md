# Shared git workflow

Used by `/commit-work`, `/sync-main`, and `/new-pr`. This repo is trunk-based: short-lived branches from the latest default branch, then delete them once they are fully merged.

## Hard rules

- Never discard user work. No `reset --hard`, `clean -fdx`, force-push, or history rewrite.
- Never update git config or skip hooks.
- Do not delete the default branch or any unmerged branch. Suggest deleting fully merged feature branches; delete them only after the user agrees. Never `git branch -D`.
- Push with `git push -u origin HEAD` when a feature branch needs an upstream. Never force-push.

## Default branch

`git rev-parse --abbrev-ref origin/HEAD` (usually `main`). Use that name everywhere below as `<default-branch>`.

## Origin authentication

If a `git fetch` / `git push` / `git pull` to `origin` fails with `Permission denied (publickey)` or another auth error, stop and report the error. Do not change git config, rewrite the remote URL, or reuse an SSH key from another project.

## Fast-forward local default branch

```bash
git fetch --prune origin
```

If HEAD is `<default-branch>` and the working tree is clean:

```bash
git pull --ff-only origin <default-branch>
```

If HEAD is `<default-branch>` and the working tree is dirty, do not pull. Report that the default branch cannot be updated while it is checked out with local changes.

If HEAD is not `<default-branch>`:

```bash
git fetch origin <default-branch>:<default-branch>
```

`--ff-only` only. If a fast-forward is not possible, stop. Do not merge or rebase the default branch.

## Suggest merged-branch cleanup

After the default branch is up to date (or after publishing a feature branch):

```bash
git branch --merged <default-branch>
git branch -r --merged <default-branch>
```

A branch is a cleanup candidate when all of these are true:

- It is not `main` / `master` / `HEAD` / `origin/HEAD` / `origin/main` / `origin/master`
- `git merge-base --is-ancestor <branch> <default-branch>`
- It is not an unmerged branch created or used as the PR head in this run

If a cleanup candidate is currently checked out, switch to `<default-branch>` first only when the working tree is clean; otherwise list it and leave checkout unchanged.

List each candidate (local and/or `origin/...`) and suggest:

```bash
git branch -d <branch>
git push origin --delete <branch>
```

Do not delete until the user agrees.
