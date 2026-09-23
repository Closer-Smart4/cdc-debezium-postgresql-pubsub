# Commit work

Inspect uncommitted work, split unrelated changes, publish a short-lived branch per slice from the latest default branch, bump the version, commit, and push to origin.

Optional argument after `/commit-work` is the branch name (or a prefix when work is split). If none is given, suggest a kebab-case name from the changes and use it.

Shared rules, origin authentication, fast-forward, and merged-branch cleanup: [shared-git.md](shared-git.md).

## Extra hard rules

- Stage only named files. No `git add .` / `git add -A`.
- Do not commit secrets (`.env`, credentials, keys) or `.venv`.
- Bump versions only with `.venv/bin/bumpversion --config-file .bumpversion.cfg <part>`. Never edit version numbers by hand.
- PoC Python must be type-annotated. Run `.venv/bin/mypy` on changed Python files before committing them. Skip `infra/`; that tree is obsolete and will be deleted.
- New slices start from the latest default branch. Do not stack a new branch on another feature branch.
- Reuse the current branch only when it is already an unmerged feature branch and the work is a continuation of that same slice.

## 1. Inspect

Run these in parallel:

- `git status` and `git status -u --short`
- `git diff`, `git diff --cached`, and their `--stat` forms
- `git log -8 --oneline`
- `git branch --show-current`
- `git rev-parse --abbrev-ref origin/HEAD`

Fast-forward the local default branch ([shared-git.md](shared-git.md)). If there is nothing to commit, suggest merged-branch cleanup and stop.

## 2. Group the work

Split files into the smallest set of independent slices. Keep tightly coupled changes together.

Exclude `.venv/`, secrets, and local junk the user did not intend to share.

## 3. Name branches and choose the bump

For each slice:

- **Branch name**: `$ARGUMENTS` for one slice; `$ARGUMENTS/<concern>` when splitting. Prefer `type/kebab-name` (`docs/`, `feat/`, `fix/`, `chore/`).
- **Reuse**: if HEAD is already that unmerged feature branch (or `$ARGUMENTS` names it) and the slice belongs there, stay on it.
- **Semver**: `patch` (fixes, small wording), `minor` (new deliverable section or architecture decision), `major` (breaking).
- **Commit message**: 1–2 sentences on why, matching this repo's style.

If several new slices start from the same default-branch version, increment sequentially (`0.3.0` → `0.3.1`, then `0.3.2`) so version files do not collide.

State the plan (slice, branch, reuse vs new, bump, files), then execute. Wait only if a slice is ambiguous or unsafe.

## 4. Snapshot

Before moving files between branches:

```bash
SHA=$(git stash create "pre-commit-work")
if [ -n "$SHA" ]; then
  git update-ref "refs/backup/commit-work-$(date +%s)" "$SHA"
fi
```

Use `git stash push -u -m "commit-work-wip"` only when splitting slices. For a single slice on an already-dirty tree, keep the working files.

## 5. Publish each slice

For each slice, in order:

1. If not reusing the current unmerged branch: check out `<default-branch>` (clean tree or after stash) and create `git checkout -b <branch-name>` from that tip. Never branch from another feature branch.
2. Restore only that slice’s files from the stash when a stash was used (`git checkout stash -- <file> ...`).
3. `.venv/bin/bumpversion --config-file .bumpversion.cfg <part>` (`patch`, `minor`, or `major`). If this branch already has the intended bump for this slice, do not bump again.
4. Stage only the slice files plus the version files bumpversion rewrites: `version.txt`, `README.md`, `.bumpversion.cfg`, and `setup.py`.
5. Commit:

```bash
git commit -m "$(cat <<'EOF'
Commit message here.

EOF
)"
```

6. `git push -u origin HEAD`

After the last slice, drop the WIP stash only if every intended file was committed. Keep the backup ref. Do not hand-edit version strings.

## 6. Cleanup and report

Suggest merged-branch cleanup ([shared-git.md](shared-git.md)). Exclude branches just published in this run.

For each published branch, list: name, reuse vs new, bump (`x.y.z` → `x.y.z`), commit subject, and `origin` URL. Mention leftover uncommitted files and any fully merged branches suggested for deletion.
