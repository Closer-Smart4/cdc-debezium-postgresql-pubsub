# Agent guide

PoC that streams PostgreSQL changes to Pub/Sub with [Debezium Server](https://debezium.io/documentation/reference/stable/operations/debezium-server.html). The local runtime is Docker Compose in `postgresql-debezium/`, backed by the Pub/Sub emulator. Publishing to a real Google Cloud project, and from there into BigQuery, is optional and documented in `README.md`.

## Scope

- Change the PoC, its Compose file, docs, and the Cursor commands under `.cursor/commands/`.
- The default stack uses the Pub/Sub emulator (`docker-compose.yml` alone). The complete path is documented step by step in `README.md`: `scripts/gcp-setup.sh` creates the five topics, `docker-compose.gcp.yml` points Debezium at the project, and `scripts/gcp-show.sh` prints the BigQuery rows and the notify log. Four topics have one pull subscription. `db-inventory.inventory.customers` has the BigQuery subscription and the notify push subscription. `GCP_CREDENTIALS_FILE` in `postgresql-debezium/gcp.env` is the publisher credential. It is a service account key when the project allows one, and the signed-in user's application-default credentials when key creation is blocked.
- Do not add Pulumi, Terraform, or another deploy pipeline. Cloud resources are created by `scripts/gcp-setup.sh`.

## Secrets

Never commit `keys/`, service-account JSON, `postgresql-debezium/gcp.env`, or credentials. `.gitignore` already ignores `keys/` and `gcp.env`. A real GCP project mounts `postgresql-debezium/keys` at `/keys` inside the Debezium container. The emulator path does not use a key.

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

- Version bumps use `.venv/bin/bumpversion --config-file .bumpversion.cfg <part>`. Python tools run from the project `.venv`.
- An origin authentication failure stops the command. Leave git config and SSH keys as they are.
- `.venv/bin/mypy` applies to PoC Python.

## Versions

[Semantic versioning](https://semver.org/). Current version is in `version.txt` and the `Version:` line in `README.md`. `bumpversion` rewrites those files and `.bumpversion.cfg`.

- `patch` — fixes and small wording
- `minor` — a new deliverable or an architecture decision
- `major` — a breaking change

Every pull request includes one bump, made by bumpversion, not by hand. If several slices branch from the same trunk version, increment them in order so the version files do not collide.

## Python

Format PoC Python with `.venv/bin/autopep8` and check it with `.venv/bin/mypy` before committing. Type-annotate new Python.

## When docs and Compose drift

Topic names are `{topic.prefix}.{schema}.{table}` with prefix `db-inventory` and schema `inventory`. The captured tables are `customers`, `geom`, `orders`, `products`, and `products_on_hand`. Only `customers` has two subscriptions. If a table, the project id, or the key path changes, update `postgresql-debezium/docker-compose.yml`, `postgresql-debezium/docker-compose.gcp.yml`, `postgresql-debezium/init-pubsub.sh`, `scripts/gcp-setup.sh`, and `README.md` together.
