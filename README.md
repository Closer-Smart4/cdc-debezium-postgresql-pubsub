# PoC for Debezium CDC

Version: 0.6.0

This project is a PoC that shows how to do CDC from a PostgreSQL database to Pub/Sub
topics using Debezium.

CDC stands for [Change Data Capture](https://en.wikipedia.org/wiki/Change_data_capture), from Wikipedia:

>In databases, change data capture (CDC) is a set of software design patterns used to determine and track the data that has changed so that action can be taken using the changed data.

[Debezium](https://debezium.io/) is an open source distributed platform for change data capture. Start it up, point it at your databases, and your apps can start responding to all of the inserts, updates, and deletes that other apps commit to your databases. Debezium is durable and fast, so your apps can respond quickly and never miss an event, even when things go wrong.

![Architecture](architecture/postgres_debezium_pubsub.png)

Debezium Server reads the PostgreSQL write-ahead log and publishes each change to a Pub/Sub topic named `{topic.prefix}.{schema}.{table}`. In this PoC the topic prefix is `db-inventory` and the schema is `inventory`.

The Compose file runs a Pub/Sub emulator on your machine, so the example does not need a Google Cloud project. The `infra/` folder is leftover from an earlier Pulumi and Cloud Build setup and will be removed.

## Prerequisites

- Docker Engine and Compose v2 (`docker compose`)
- Your user in the `docker` group, so Compose does not use `sudo` and does not ask for a password. On this demo machine `sudo` is passwordless, but the commands below do not call it. If `docker compose` says permission denied, the shell was opened before the group was added; run `newgrp docker` or log in again.
- A project virtual environment named `.venv`, used for version bumps and Python checks:

```
python3 -m venv .venv
.venv/bin/pip install bumpversion mypy types-setuptools autopep8
```

## Running this example

From the project root:

```
sg docker -c "docker compose -f postgresql-debezium/docker-compose.yml up"
```

Compose starts five pieces:

- `db-inventory` — `debezium/example-postgres:3.0.0.Final`, the inventory database
- `adminer` — database UI on port 8080
- `pubsub-emulator` — Pub/Sub emulator on port 8085, project `local-debezium`
- `pubsub-init` — creates the topics and pull subscriptions, then exits
- `debezium` — `debezium/server:3.0.0.Final`, which streams the `inventory` schema

Wait until the Debezium log says `Processing messages`:

```
sg docker -c "docker compose -f postgresql-debezium/docker-compose.yml logs -f debezium"
```

The emulator does not create topics when the first message arrives, so Debezium stays stopped until `pubsub-init` has finished. Images are pinned to Debezium `3.0.0.Final` because that is the newest tag still published on Docker Hub.

Debezium reads configuration from environment variables whose names are the property in upper case, with dots turned into underscores. `debezium.sink.type` is `DEBEZIUM_SINK_TYPE`.

Open Adminer at `http://localhost:8080` and log in with:

| Field | Value |
| --- | --- |
| System | PostgreSQL |
| Server | `db-inventory` |
| Username | `postgres` |
| Password | `example` |
| Database | `postgres` |

After login choose `Schema -> inventory`.

To confirm a change from the shell, run Compose against the `db-inventory` service. `sg docker` uses the Docker group for that command, so it does not ask for a password. The generated container name is not stable across shells that cannot see the Docker socket.

```
sg docker -c "docker compose -f postgresql-debezium/docker-compose.yml exec db-inventory psql -U postgres -d postgres -c \"INSERT INTO inventory.customers (first_name, last_name, email) VALUES ('Ada', 'Lovelace', 'ada@example.com');\""

curl -s -X POST \
  "http://localhost:8085/v1/projects/local-debezium/subscriptions/db-inventory.inventory.customers:pull" \
  -H "Content-Type: application/json" \
  -d '{"maxMessages":10}' \
| python3 -c '
import json, sys, base64
data = json.load(sys.stdin)
for message in data.get("receivedMessages", []):
    payload = json.loads(base64.b64decode(message["message"]["data"]))["payload"]
    print(json.dumps({
        "op": payload.get("op"),
        "before": payload.get("before"),
        "after": payload.get("after"),
    }, indent=2))
'
```

The emulator returns each payload in `message.data` as base64. The Python above decodes it. `op` is `c` for a new row and `r` for a row from the first snapshot. `after` is the row Debezium sent.

## Pub/Sub topics

`pubsub-init` creates one topic and one pull subscription of the same name for each table in the `inventory` schema:

- db-inventory.inventory.customers
- db-inventory.inventory.geom
- db-inventory.inventory.orders
- db-inventory.inventory.products
- db-inventory.inventory.products_on_hand

Subscriptions keep messages for 7 days. The emulator listens on `localhost:8085`.

## Publish to a Google Cloud project

The emulator is still the default. This section is the other option: Debezium publishes to a real Pub/Sub topic, and a BigQuery subscription writes each `customers` change into a table.

You need a Google Cloud project. Create the resources in the console. This repo does not deploy them.

### Console setup

1. Open the [Google Cloud Console](https://console.cloud.google.com/), select the project, and copy its **Project ID**.
2. Go to **APIs & Services → Library** and enable **Cloud Pub/Sub API** and **BigQuery API**.
3. Go to **Pub/Sub → Topics** and create one topic for each name in [Pub/Sub topics](#pubsub-topics). Debezium stops if any of those topics is missing. No pull subscription is required for this path.
4. Go to **IAM & Admin → Service Accounts → Create service account**. Grant **Pub/Sub Publisher** (`roles/pubsub.publisher`). Create a JSON key and save it as `postgresql-debezium/keys/gcp-sa.json`. That directory is gitignored.
5. Go to **BigQuery** and create a dataset named `debezium_cdc`. Pick the location you want for the demo (for example `EU`).
6. Open a query in that dataset and run:

```
CREATE TABLE debezium_cdc.customers_changes (
  data JSON,
  subscription_name STRING,
  message_id STRING,
  publish_time TIMESTAMP,
  attributes JSON
);

CREATE VIEW debezium_cdc.customers AS
SELECT
  publish_time,
  JSON_VALUE(data, '$.payload.op') AS op,
  JSON_VALUE(data, '$.payload.after.id') AS id,
  JSON_VALUE(data, '$.payload.after.first_name') AS first_name,
  JSON_VALUE(data, '$.payload.after.last_name') AS last_name,
  JSON_VALUE(data, '$.payload.after.email') AS email
FROM debezium_cdc.customers_changes;
```

7. Go to **Pub/Sub → Subscriptions → Create subscription**:
   - **Subscription ID:** `db-inventory.inventory.customers-bq`
   - **Topic:** `db-inventory.inventory.customers`
   - **Delivery type:** **Write to BigQuery**
   - **Table:** `debezium_cdc.customers_changes`
   - Leave **Use topic schema** and **Use table schema** off. The whole Debezium JSON message is stored in the `data` column.
   - Turn **Write metadata** on, so `publish_time` is filled.
   - When the console offers to grant the Pub/Sub service agent access to the table, accept it.

Copy `postgresql-debezium/.env.example` to `postgresql-debezium/.env` and set `GCP_PROJECT_ID` to the Project ID. `.env` is gitignored.

### Run against the project

Stop the emulator stack, then start Compose with both files. The second file points Debezium at the project, mounts the key, and does not start the emulator.

```
sg docker -c "docker compose -f postgresql-debezium/docker-compose.yml down"
sg docker -c "docker compose --env-file postgresql-debezium/.env -f postgresql-debezium/docker-compose.yml -f postgresql-debezium/docker-compose.gcp.yml up"
```

Wait until the Debezium log says `Processing messages`. A new container has no offset file, so Debezium sends the current `inventory.customers` rows first (`op` = `r`). Then insert a row:

```
sg docker -c "docker compose -f postgresql-debezium/docker-compose.yml exec db-inventory psql -U postgres -d postgres -c \"INSERT INTO inventory.customers (first_name, last_name, email) VALUES ('Ada', 'Lovelace', 'ada@example.com');\""
```

In the BigQuery console, query the view. A new row has `op` = `c` and the name in `first_name` / `last_name` / `email`.

```
SELECT *
FROM debezium_cdc.customers
ORDER BY publish_time DESC
LIMIT 20
```

To go back to the emulator, stop Compose and start the base file only, as in [Running this example](#running-this-example).

## Trunk-based development

`main` is the trunk. Each change is a short-lived branch cut from the latest trunk, opened as a pull request, and deleted after it is fully merged. Branches are not stacked on each other.

Cursor commands in `.cursor/commands/` run that workflow:

- `/commit-work` splits the current work, bumps the version, commits, and pushes a branch
- `/sync-main` fast-forwards the local trunk to `origin`
- `/new-pr` opens the pull request

Agent rules for this repo are in `AGENTS.MD`.

## Manage versions

This repo uses [semantic versioning](https://semver.org/). Every pull request bumps the version with [bumpversion](https://pypi.org/project/bumpversion/):

```
.venv/bin/bumpversion --config-file .bumpversion.cfg major|minor|patch
```

`patch` is a fix or small wording change, `minor` is a new deliverable, and `major` is a breaking change. The command rewrites `version.txt`, the `Version:` line in this file, `.bumpversion.cfg`, and `setup.py`. Do not edit those version numbers by hand.

## Generate project documentation

To generate documentation on your local machine run on the project's root:

```
pydoc-markdown
```

The above command uses configurations stored on file `pydoc-markdown.yaml`. Documentation
will be created in folder `docs`. Refer to [pydoc-markdown](https://pypi.org/project/pydoc-markdown/)
for more information.

## Pep8 compliant code

Format PoC Python with [autopep8](https://pypi.org/project/autopep8/) from the project root, for example:

```
.venv/bin/autopep8 --in-place --exit-code --verbose path/to/module.py
```

It reformats code non-aggressively. Skip `infra/` until that folder is deleted.

## Type check

Type check PoC Python with [mypy](http://www.mypy-lang.org/) from the project root:

```
.venv/bin/mypy path/to/module.py
```

Skip `infra/`. New Python in this repo is type-annotated.
