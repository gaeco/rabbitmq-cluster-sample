# Native 3-node RabbitMQ cluster (Ubuntu 24.04)

Bash scripts to stand up a **3-node RabbitMQ cluster** on three **Ubuntu 24.04**
hosts with **no containers** — Erlang and RabbitMQ are installed as native apt
packages.

> **Air-gapped:** the nodes have no internet access, only an internal apt
> mirror. RabbitMQ is installed with a plain `apt-get install rabbitmq-server`
> from that mirror — no external RabbitMQ repos, signing keys, or offline
> bundles. This installs the version Ubuntu 24.04 ships (**RabbitMQ 3.12.x**,
> Erlang 25); newer releases like 4.x are only in the Team RabbitMQ repo, which
> an air-gapped host can't reach.

This is the bare-metal counterpart to the Podman `compose.yaml` in the repo root.
It uses the same idea for cluster formation: **static (`classic_config`) peer
discovery**, where every node knows the full member list and forms/joins the
cluster automatically on boot.

## Nodes

| Node    | IP             | RabbitMQ node name | Role |
|---------|----------------|--------------------|------|
| rabbit1 | 10.194.178.81  | `rabbit@rabbit1`   | seed |
| rabbit2 | 10.194.179.88  | `rabbit@rabbit2`   |      |
| rabbit3 | 10.194.179.89  | `rabbit@rabbit3`   |      |

All settings (IPs, hostnames, Erlang cookie, admin credentials) live in
[`cluster.env`](./cluster.env). **Edit it first** — at minimum change
`ERLANG_COOKIE` and `RABBITMQ_ADMIN_PASS`.

## Files

- `cluster.env` — configuration (node list, cookie, admin user).
- `lib.sh` — shared helpers; auto-detects which node a script runs on by matching the machine's IP against `NODE_IPS`.
- `01-install.sh` — `apt-get install rabbitmq-server` (Erlang pulled in automatically). Run on **every** node.
- `02-configure.sh` — hostname, `/etc/hosts`, shared cookie, `rabbitmq.conf`, management plugin, firewall, restart. Run on **every** node (seed first).
- `03-verify.sh` — print `cluster_status`. Run anywhere.
- `create-admin.sh` — create the cluster-wide admin user. Run **once**, on the seed node.
- `setup-test-queue.sh` — declare the Spring Boot app's exchange/queue/binding (and optionally publish a test message) via the management API. Run **once**, anywhere, after `create-admin.sh`.
- `deploy-all.sh` — optional orchestrator that SSHes into all three nodes and runs the above in order.

## Option A — orchestrated from one control machine

From a machine that can SSH into all three nodes as a sudo-capable user:

```bash
cd native-cluster
# edit cluster.env first (cookie, admin password)
SSH_USER=ubuntu ./deploy-all.sh
# or with an explicit key:
SSH_USER=ubuntu SSH_KEY=~/.ssh/id_ed25519 ./deploy-all.sh
```

Requires passwordless (or ssh-agent) SSH and passwordless sudo on each node.

## Option B — manually, node by node

Copy this directory to each node, then on **each** node:

```bash
sudo ./01-install.sh
sudo ./02-configure.sh     # do the seed node (rabbit1) first
```

Then **once**, on the seed node:

```bash
sudo ./create-admin.sh
sudo ./03-verify.sh
./setup-test-queue.sh --publish   # declare the app's queue + send a test message
```

`02-configure.sh` figures out which node it's on from the host's IP. If a node's
IP isn't in `NODE_IPS` (e.g. NAT), set it explicitly: `sudo SELF_INDEX=1 ./02-configure.sh`.

## Verify

```bash
sudo ./03-verify.sh
# or directly:
sudo -u rabbitmq rabbitmqctl cluster_status
```

You should see all three `rabbit@rabbitN` nodes under *Running Nodes*.

Management UI (log in with the admin user from `cluster.env`):

- http://10.194.178.81:15672
- http://10.194.179.88:15672
- http://10.194.179.89:15672

## Ports that must be open between nodes

| Port  | Purpose |
|-------|---------|
| 4369  | epmd (Erlang port mapper) |
| 25672 | inter-node + CLI Erlang distribution |
| 5672  | AMQP (clients) |
| 15672 | management UI (clients) |

These nodes run no local firewall, so `02-configure.sh` doesn't touch one — just
make sure the network path / security groups between nodes allow these ports.

## Notes

- **Version:** this installs whatever `rabbitmq-server` the internal apt mirror
  carries — on stock Ubuntu 24.04 that's **3.12.x** (Erlang 25). RabbitMQ 4.x is
  not in Ubuntu's archive; getting it would require the Team RabbitMQ apt repo,
  which an air-gapped host can't reach.
- The shared `ERLANG_COOKIE` and matching hostname list are what let the cluster
  form. Changing hostnames means updating `NODE_HOSTS` in `cluster.env` (the
  `rabbitmq.conf` node list and `/etc/hosts` are generated from it).
- **Data directory:** `02-configure.sh` relocates RabbitMQ's home (Erlang cookie,
  mnesia data, logs) to `RABBITMQ_HOME` from `cluster.env` — default
  `/data/rabbitmq` — via the rabbitmq user's home, `rabbitmq-env.conf`
  (`RABBITMQ_MNESIA_BASE`/`RABBITMQ_LOG_BASE`), and a systemd unit drop-in. Make
  sure that path exists on a suitable disk/mount on each node.
- `02-configure.sh` clears `${RABBITMQ_HOME}/mnesia` so each node starts clean
  under its new node name. **This wipes local broker data** — intended for a
  fresh build, not for reconfiguring a cluster that already holds data.
- `guest` is loopback-only by design; use the admin user from `create-admin.sh`
  to connect from other machines.
- To point the Spring Boot app (`app/`) at this cluster, set
  `spring.rabbitmq.addresses: 10.194.178.81:5672,10.194.179.88:5672,10.194.179.89:5672`
  and use the admin credentials.
