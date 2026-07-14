# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

A sample setup demonstrating a **3-node RabbitMQ cluster** run on **Podman** locally, with a **Spring Boot 3** application that publishes/consumes messages against the cluster to test it.

Two parts:
1. **RabbitMQ cluster** — three broker nodes clustered together, each exposing distinct host ports so they can coexist on a single local Podman host.
2. **Spring Boot 3 app** — a simple producer/consumer that connects to the cluster (typically via all three AMQP endpoints for failover) to verify messaging works.

Layout:
- `compose.yaml`, `rabbitmq/`, `scripts/` — the RabbitMQ cluster on Podman (repo root).
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

## Spring Boot 3 application

Lives in `app/` (Spring Boot 3.3.x, `spring-boot-starter-amqp` + `-web`). A minimal producer/consumer.

- Runs on **JDK 21** — the Gradle Java toolchain in `app/build.gradle` pins language version 21.
- **Gradle** (not Maven), via the committed wrapper. All commands run **from `app/`**:
  - Build + test: `./gradlew build`.
  - Run the app: `./gradlew bootRun`.
  - All tests: `./gradlew test`.
  - Single test: `./gradlew test --tests 'com.example.rabbitmqsample.MessageProducerTest'` (append `.methodName` for one method).
- Connects to all three nodes via `spring.rabbitmq.addresses: localhost:5672,localhost:5673,localhost:5674` (in `application.yml`) for failover, not a single `host`/`port`.
- Messaging topology is declared in `RabbitConfig` from `app.rabbitmq.*` properties (`RabbitProperties`): a durable topic exchange, durable queue, and binding. Payloads (`SampleMessage`) are JSON via `Jackson2JsonMessageConverter`.
- Manual smoke test once the cluster and app are up: `curl -X POST 'http://localhost:8080/messages?content=hi'` — `MessageConsumer` (`@RabbitListener`) logs what it receives.
- Note: tests must not require a running broker — `MessageProducerTest` mocks `RabbitTemplate`. A full `@SpringBootTest` would try to connect on startup, so keep broker-dependent checks out of the default `test` task.

## Typical workflow

1. `./scripts/up.sh` and confirm all three nodes joined.
2. `cd app && ./gradlew bootRun`.
3. `curl -X POST 'http://localhost:8080/messages?content=hi'` and watch the consumer log the delivery; optionally stop a node (`podman stop rabbit1`) to verify failover.