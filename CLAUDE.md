# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

A sample setup demonstrating a **3-node RabbitMQ cluster** run on **Podman** locally, with a **Spring Boot 3** application that publishes/consumes messages against the cluster to test it.

Two parts:
1. **RabbitMQ cluster** — three broker nodes clustered together, each exposing distinct host ports so they can coexist on a single local Podman host.
2. **Spring Boot 3 app** — a simple producer/consumer that connects to the cluster (typically via all three AMQP endpoints for failover) to verify messaging works.

Layout:
- `compose.yaml`, `rabbitmq/`, `scripts/` — the RabbitMQ cluster on Podman (repo root).
- `native-cluster/` — bash scripts to stand up the same 3-node cluster on three bare Ubuntu 24.04 hosts (no containers).
- `app/` — the Spring Boot 3 Gradle project.

## RabbitMQ cluster (Podman)

Three nodes clustered via a shared Erlang cookie. Because all nodes run on one local host, each gets a **unique host port mapping** (container ports stay at the RabbitMQ defaults — 5672 AMQP, 15672 management):

| Node   | AMQP (host→container) | Management UI (host→container) |
|--------|-----------------------|--------------------------------|
| rabbit1 | 5672 → 5672          | 15672 → 15672                  |
| rabbit2 | 5673 → 5672          | 15673 → 15672                  |
| rabbit3 | 5674 → 5672          | 15674 → 15672                  |

Files:
- `compose.yaml` — the 3-node cluster, declarative. Nodes share `RABBITMQ_ERLANG_COOKIE`, each has a durable data volume, and `rabbit2`/`rabbit3` wait on `rabbit1` being healthy.
- `rabbitmq/rabbitmq.conf` — mounted into every node. Uses **static (`classic_config`) peer discovery**: each node knows the full member list (`rabbit@rabbit1/2/3`) and forms/joins the cluster automatically on boot — no manual `join_cluster`. Also sets `cluster_partition_handling = pause_minority` and `loopback_users = none` (local testing only, so `guest` can log in through published ports).
- `rabbitmq/enabled_plugins` — enables `rabbitmq_management`.
- `scripts/` — wrappers around `podman compose`.

Commands (from repo root):
- Up (and wait for the cluster to form): `./scripts/up.sh` — or `podman compose up -d`.
- Down: `./scripts/down.sh` — add `--volumes` to also delete data.
- Status: `./scripts/status.sh` — or `podman exec rabbit1 rabbitmqctl cluster_status`.
- Logs: `./scripts/logs.sh [rabbit1|rabbit2|rabbit3]`.

Notes when editing the setup:
- The shared Erlang cookie and matching member list are what let the cluster form; changing hostnames means updating both `compose.yaml` (`hostname:`) and the `classic_config.nodes.*` list in `rabbitmq.conf`.
- Management UI per node: `http://localhost:15672` / `15673` / `15674` (login `guest`/`guest`).

## RabbitMQ cluster (native, Ubuntu 24.04)

`native-cluster/` stands up the **same 3-node cluster** on three bare **Ubuntu 24.04** hosts with **no containers** — Erlang and RabbitMQ are installed as native apt packages. It uses the same cluster-formation model as the Podman setup: **static (`classic_config`) peer discovery** plus `cluster_partition_handling = pause_minority`.

Because these are separate machines (not one host), each node uses the **default** RabbitMQ ports (no per-node remapping like Podman). Nodes and their fixed IPs:

| Node    | IP             | RabbitMQ node name | Role |
|---------|----------------|--------------------|------|
| rabbit1 | 10.194.178.81  | `rabbit@rabbit1`   | seed |
| rabbit2 | 10.194.179.88  | `rabbit@rabbit2`   |      |
| rabbit3 | 10.194.179.89  | `rabbit@rabbit3`   |      |

Key facts:
- **Version:** installs `rabbitmq-server` straight from Ubuntu's own apt repo (`apt-get install rabbitmq-server`) — **RabbitMQ 3.12.x** on stock 24.04, Erlang pulled in as a dependency. This is deliberately **air-gapped friendly**: no external RabbitMQ repos, signing keys, or offline bundles. RabbitMQ 4.x is *not* in Ubuntu's archive and would need the Team RabbitMQ repo, which an air-gapped host can't reach.
- **Config** lives in `native-cluster/cluster.env`: `NODE_IPS`/`NODE_HOSTS` (position-matched), `SEED_INDEX`, the shared `ERLANG_COOKIE`, and the admin `RABBITMQ_ADMIN_USER`/`RABBITMQ_ADMIN_PASS`. Change the cookie and admin password before real use.
- Scripts **auto-detect which node they run on** by matching the host's IP against `NODE_IPS` (`lib.sh`); override with `SELF_INDEX=<0-based>`.
- `guest` is loopback-only, so remote AMQP/management access uses the admin user from `create-admin.sh` (not `guest`).
- Ports between nodes: `4369` (epmd) + `25672` (inter-node) for clustering; `5672` (AMQP) + `15672` (management UI) for clients. `02-configure.sh` opens these in `ufw` only if ufw is active.

Scripts (all in `native-cluster/`, run with `sudo` where they change the system):
- `01-install.sh` — `apt-get install rabbitmq-server`. Run on **every** node.
- `02-configure.sh` — hostname, `/etc/hosts` (all three nodes), shared Erlang cookie, `rabbitmq.conf` (classic_config peer discovery, generated from `cluster.env`), management plugin, firewall, restart. Run on **every** node, **seed first**. Note: it clears `/var/lib/rabbitmq/mnesia`, so it's for a **fresh build**, not reconfiguring a cluster with data.
- `create-admin.sh` — create the cluster-wide admin user. Run **once**, on the seed node.
- `setup-test-queue.sh` — declare the app's exchange/queue/binding (optionally `--publish` a test message) via the management HTTP API. Idempotent; matches `RabbitConfig`. Run **once**, anywhere, after `create-admin.sh`.
- `03-verify.sh` — print `cluster_status`.
- `deploy-all.sh` — optional orchestrator that SSHes into all three nodes (needs passwordless SSH + sudo) and runs install → configure → create-admin → verify in the right order.
- `lib.sh` — shared helpers (sources `cluster.env`, node detection, `rmqctl` wrapper that runs `rabbitmqctl` with the rabbitmq user's cookie).

Typical run (manual): on each node, seed first, `sudo ./01-install.sh` then `sudo ./02-configure.sh`; then once on the seed, `sudo ./create-admin.sh`, `sudo ./03-verify.sh`, `./setup-test-queue.sh --publish`.

## Spring Boot 3 application

Lives in `app/` (Spring Boot 3.3.x, `spring-boot-starter-amqp` + `-web`). A minimal producer/consumer.

- Runs on **JDK 21** — the Gradle Java toolchain in `app/build.gradle` pins language version 21.
- **Gradle** (not Maven), via the committed wrapper. All commands run **from `app/`**:
  - Build + test: `./gradlew build`.
  - Run the app: `./gradlew bootRun`.
  - All tests: `./gradlew test`.
  - Single test: `./gradlew test --tests 'com.example.rabbitmqsample.MessageProducerTest'` (append `.methodName` for one method).
- Connects to all three nodes via `spring.rabbitmq.addresses` (in `application.yml`) for failover, not a single `host`/`port`. The default now targets the **native cluster** IPs (`10.194.178.81:5672,10.194.179.88:5672,10.194.179.89:5672`) with the admin user, all env-overridable (`RABBITMQ_ADDRESSES`, `RABBITMQ_USERNAME`, `RABBITMQ_PASSWORD`). For the local Podman cluster instead, override with `RABBITMQ_ADDRESSES=localhost:5672,localhost:5673,localhost:5674` and `guest`/`guest`.
- Messaging topology is declared in `RabbitConfig` from `app.rabbitmq.*` properties (`RabbitProperties`): a durable topic exchange, durable queue, and binding. Payloads (`SampleMessage`) are JSON via `Jackson2JsonMessageConverter`.
- Manual smoke test once the cluster and app are up: `curl -X POST 'http://localhost:8080/messages?content=hi'` — `MessageConsumer` (`@RabbitListener`) logs what it receives.
- Note: tests must not require a running broker — `MessageProducerTest` mocks `RabbitTemplate`. A full `@SpringBootTest` would try to connect on startup, so keep broker-dependent checks out of the default `test` task.

## Typical workflow

1. `./scripts/up.sh` and confirm all three nodes joined.
2. `cd app && ./gradlew bootRun`.
3. `curl -X POST 'http://localhost:8080/messages?content=hi'` and watch the consumer log the delivery; optionally stop a node (`podman stop rabbit1`) to verify failover.