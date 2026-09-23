# PoC for Debezium CDC

Version: 0.4.0

This project is a PoC that shows how to do CDC from a PostgreSQL database to Pub/Sub
topics using Debezium.

CDC stands for [Change Data Capture](https://en.wikipedia.org/wiki/Change_data_capture), from Wikipedia:

>In databases, change data capture (CDC) is a set of software design patterns used to determine and track the data that has changed so that action can be taken using the changed data.

[Debezium](https://debezium.io/) is an open source distributed platform for change data capture. Start it up, point it at your databases, and your apps can start responding to all of the inserts, updates, and deletes that other apps commit to your databases. Debezium is durable and fast, so your apps can respond quickly and never miss an event, even when things go wrong.

![Architecture](architecture/postgres_debezium_pubsub.png)

Debezium Server reads the PostgreSQL write-ahead log and publishes each change to a Pub/Sub topic named `{server}.{schema}.{table}`. In this PoC the server name is `db-inventory` and the schema is `inventory`.

GCP is set up by hand in the Cloud Console. The `infra/` folder is leftover from an earlier Pulumi and Cloud Build setup and will be removed.

## Prerequisites

- Docker, with Compose (`docker-compose` or `docker compose`)
- A Google Cloud project where you can enable APIs, create Pub/Sub resources, and create a service account
- A project virtual environment named `.venv`:

```
python3 -m venv .venv
.venv/bin/pip install bumpversion mypy types-setuptools autopep8
```

## Set up GCP in the console

Do this before starting Compose. Debezium publishes with a service account that has `Pub/Sub Publisher` only, so the topics and subscriptions must already exist.

### 1. Project and API

1. Open the [Google Cloud Console](https://console.cloud.google.com/) and select the project that will receive the events. Copy its **Project ID**.
2. Go to **APIs & Services → Library**, search for **Cloud Pub/Sub API**, and enable it.

### 2. Topics and subscriptions

For each name in [Pub/Sub topics](#pubsub-topics):

1. Go to **Pub/Sub → Topics → Create topic**.
2. Set **Topic ID** to that exact name (for example `db-inventory.inventory.customers`). Leave the other topic settings at their defaults.
3. Open the topic and choose **Create subscription**.
4. Set **Subscription ID** to the same name as the topic.
5. Set **Delivery type** to **Pull**.
6. Set **Message retention duration** to **7 days**, so unread change events stay available for a week.
7. Set **Expiration period** to **Never expire**. A quiet PoC subscription would otherwise be deleted after inactivity.

Your user account needs permission to view those subscriptions (a project Owner or Editor already has it). Pull messages from the subscription page to watch the stream.

### 3. Service account

1. Go to **IAM & Admin → Service Accounts → Create service account**.
2. Name it something like `debezium-pubsub-publisher`.
3. Grant the role **Pub/Sub Publisher** (`roles/pubsub.publisher`) on this project.
4. Open the new account, go to **Keys → Add key → Create new key → JSON**, and download the key.
5. Move the JSON file to `postgresql-debezium/keys/`. That directory is gitignored. Do not commit the key.

### 4. Point Compose at your project

In `postgresql-debezium/docker-compose.yml`, set:

- `debezium.sink.pubsub.project.id` to the Project ID from step 1
- `GOOGLE_APPLICATION_CREDENTIALS` to `/keys/` plus the JSON file name

The Compose file bind-mounts `postgresql-debezium/keys` at `/keys` inside the Debezium container. The sample values in the file (`datapool-prt-dsi-dev` and `sa-datapool-prt-dsi-dev.json`) are placeholders from an earlier environment.

## Running this example

From the project root:

```
docker-compose -f postgresql-debezium/docker-compose.yml up
```

Inserts, updates, and deletes in the `inventory` schema are published to the topics above. Open each subscription in the console and pull messages to see them.

To explore the PostgreSQL inventory database open `http://localhost:8080` in a browser
and fill the following values: `System -> PostgreSQL`, `Server -> db-inventory`,
`Username -> postgres`, `Password -> example` and `Database -> postgres`. After login
you need to choose `Schema -> inventory`.

## Pub/Sub topics

There is one topic, and one pull subscription of the same name, for each table Debezium watches:

- db-inventory.inventory.customers
- db-inventory.inventory.geography_columns
- db-inventory.inventory.geom
- db-inventory.inventory.geometry_columns
- db-inventory.inventory.orders
- db-inventory.inventory.products
- db-inventory.inventory.products_on_hand
- db-inventory.inventory.raster_columns
- db-inventory.inventory.raster_overviews
- db-inventory.inventory.spatial_ref_sys

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
