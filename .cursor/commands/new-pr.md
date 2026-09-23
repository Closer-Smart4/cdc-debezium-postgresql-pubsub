# New pull request

Create a GitHub pull request from a short-lived branch. Suggest a title and description from the commits and diff, then open the PR with `gh`.

Optional argument after `/new-pr` is a title override. If none is given, suggest a title. The PR is opened from the current branch unless `$ARGUMENTS` matches an existing local branch name.

Shared rules, origin authentication, fast-forward, and merged-branch cleanup: [shared-git.md](shared-git.md).

## Extra hard rules

- Do not open a PR from the default branch. Use `/commit-work` first if the work is still uncommitted.
- Use `gh pr create` for all GitHub PR work. Do not invent a PR URL.
- Base the PR on `<default-branch>`.

## 1. Inspect

Run these in parallel:

- `git status` (staged, unstaged, untracked)
- `git branch --show-current`
- `git rev-parse --abbrev-ref origin/HEAD`
- whether the branch tracks a remote and is up to date
- `git log --oneline <default-branch>..HEAD`
- `git diff <default-branch>...HEAD`

Fast-forward the local default branch ([shared-git.md](shared-git.md)).

If `$ARGUMENTS` is an existing local branch and it is not HEAD, use it as the PR head. Check it out only if the working tree is clean; otherwise stop.

If HEAD is the default branch, stop. Tell the user to run `/commit-work` first.

If there are no commits ahead of the default branch, suggest merged-branch cleanup and stop.

If the current head is already fully merged into the default branch, do not open a PR. Suggest deleting that branch and stop.

If `gh` is missing, stop and tell the user to install [GitHub CLI](https://cli.github.com/).

If an open PR already exists (`gh pr view --json url,state`), report the URL, suggest cleanup of other fully merged branches, and stop.

## 2. Suggest title and description

Read every commit and the full diff against the default branch. Draft:

- **Title**: short, why-focused, matching this repo’s commit style. Use `$ARGUMENTS` when it is a title override (not a branch name).
- **Body**:

```markdown
## Summary
<1-3 bullet points>

## Test plan
- [ ] <checklist of what to verify>
```

Mention the version bump (`x.y.z` → `x.y.z`) when version files changed. If the branch did not bump the version, warn that every PR must use `.venv/bin/bumpversion --config-file .bumpversion.cfg` and stop unless the user already confirmed they want the PR anyway.

State the title and description, then create the PR. Wait only if the head branch is ambiguous or the diff looks unsafe.

## 3. Push and create

Push if the branch has no upstream or is ahead of origin (`git push -u origin HEAD`).

```bash
gh pr create --base <default-branch> --head <branch> --title "the pr title" --body "$(cat <<'EOF'
## Summary
- ...

## Test plan
- [ ] ...

EOF
)"
```

## 4. Cleanup and report

Suggest merged-branch cleanup ([shared-git.md](shared-git.md)). Do not suggest deleting the unmerged head of the PR just opened. If that PR is still open, say the head can be deleted after it merges.

Return the PR URL, title, base ← head, and whether the branch was pushed. Mention leftover uncommitted files and any fully merged branches suggested for deletion.
