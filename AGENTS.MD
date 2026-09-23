# Agent guide

PoC that streams PostgreSQL changes to Google Cloud Pub/Sub with [Debezium Server](https://debezium.io/documentation/reference/stable/operations/debezium-server.html). The local runtime is Docker Compose in `postgresql-debezium/`. Humans set up GCP in the Cloud Console. Those steps live in `README.md`.

## Scope

- Change the PoC, its Compose file, docs, and the Cursor commands under `.cursor/commands/`.
- GCP resources (project, Pub/Sub API, topics, pull subscriptions, service account, JSON key) are created in the console. Keep `README.md` as the source of those steps.
- `infra/` is leftover Pulumi and Cloud Build from another approach. Leave it untouched until the user asks to delete it. Do not import it, extend it, or add Pulumi, Terraform, or another deploy pipeline.
- `__main__.py` only starts that leftover Pulumi program. Do not grow it.

## Secrets

Never commit `keys/`, service-account JSON, `.env`, or credentials. `.gitignore` already ignores `keys/`. The Compose file bind-mounts `postgresql-debezium/keys` at `/keys` inside the Debezium container.

## Trunk-based development

The trunk is the default branch (`git rev-parse --abbrev-ref origin/HEAD`, usually `main`). Work lands through a short-lived branch and a pull request, then the branch is deleted once it is fully merged.

Cursor commands:

| Command | File | What it does |
| --- | --- | --- |
| `/commit-work` | `.cursor/commands/commit-work.md` | Slice uncommitted work, branch from the latest trunk, bump the version, commit, push |
| `/sync-main` | `.cursor/commands/sync-main.md` | Fast-forward the local trunk to `origin` |
| `/new-pr` | `.cursor/commands/new-pr.md` | Open a GitHub pull request with `gh` |
| (shared) | `.cursor/commands/shared-git.md` | Rules those three commands share |

Follow the command file that matches the user's slash command. Shared rules:

- Never discard user work. No `reset --hard`, `clean -fdx`, force-push, or history rewrite.
- Never update git config or skip hooks.
- Stage named files only. No `git add .` or `git add -A`.
- New branches start from the latest trunk. Do not stack a feature branch on another feature branch.
- Reuse the current branch only when it is already an unmerged feature branch and the change continues that same slice.
- Do not open a pull request from the trunk.
- Push with `git push -u origin HEAD`. If origin authentication fails, stop and report it. Do not borrow an SSH key from another clone.
- Update the local trunk with fast-forward only. If that is not possible, stop.
- Suggest deleting branches that are fully merged into the trunk. Delete them only after the user agrees. Never `git branch -D`. Do not delete the trunk, and do not delete the head of an open pull request.

These commands were copied from another repo and adapted here:

- Version bumps use `bumpversion --config-file .bumpversion.cfg <part>`.
- An origin authentication failure stops the command. Leave git config and SSH keys as they are.
- `mypy` applies to PoC Python. Skip `infra/`.

## Versions

[Semantic versioning](https://semver.org/). Current version is in `version.txt` and the `Version:` line in `README.md`. `bumpversion` also rewrites `setup.py`.

- `patch` — fixes and small wording
- `minor` — a new deliverable or an architecture decision
- `major` — a breaking change

Every pull request includes one bump, made by bumpversion, not by hand. If several slices branch from the same trunk version, increment them in order so the version files do not collide.

## Python

Format PoC Python with `autopep8` and check it with `mypy` before committing. Type-annotate new Python. Do not format or type-check `infra/`.

## When docs and Compose drift

Topic names are `{server}.{schema}.{table}` with server `db-inventory` and schema `inventory`. If a table, the GCP project id, or the key path changes, update `postgresql-debezium/docker-compose.yml` and the console steps in `README.md` together.
