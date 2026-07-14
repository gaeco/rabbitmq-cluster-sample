# Native 3-node RabbitMQ cluster (Ubuntu 24.04)

Bash scripts to stand up a **3-node RabbitMQ cluster** on three **Ubuntu 24.04**
hosts with **no containers** — Erlang and RabbitMQ are installed as native apt
packages.

> **Air-gapped:** the nodes have no internet access (only an internal apt
> mirror). These scripts never contact the RabbitMQ key servers or
> `ppa*.rabbitmq.com`. Packages come from either a pre-staged local `.deb`
> bundle (default) or your internal apt mirror. See **Installing offline** below.

This is the bare-metal counterpart to the Podman `compose.yaml` in the repo root.
It uses the same idea for cluster formation: **static (`classic_config`) peer
discovery**, where every node knows the full member list and forms/joins the
cluster automatically on boot.

## Nodes

| Node    | IP             | RabbitMQ node name | Role |
|---------|----------------|--------------------|------|
| rabbit1 | 10.194.178.93  | `rabbit@rabbit1`   | seed |
| rabbit2 | 10.194.178.87  | `rabbit@rabbit2`   |      |
| rabbit3 | 10.194.179.85  | `rabbit@rabbit3`   |      |

All settings (IPs, hostnames, Erlang cookie, admin credentials) live in
[`cluster.env`](./cluster.env). **Edit it first** — at minimum change
`ERLANG_COOKIE` and `RABBITMQ_ADMIN_PASS`.

## Files

- `cluster.env` — configuration (node list, cookie, admin user).
- `lib.sh` — shared helpers; auto-detects which node a script runs on by matching the machine's IP against `NODE_IPS`.
- `fetch-packages.sh` — run on an **internet-connected** staging host to download the RabbitMQ + Erlang `.deb` bundle into `packages/`. Not run on the nodes.
- `01-install.sh` — install Erlang + RabbitMQ (pinned to `RABBITMQ_VERSION`, default **4.3.2**, and `apt-mark hold`ed) from the offline bundle or internal mirror. Run on **every** node.
- `02-configure.sh` — hostname, `/etc/hosts`, shared cookie, `rabbitmq.conf`, management plugin, firewall, restart. Run on **every** node (seed first).
- `03-verify.sh` — print `cluster_status`. Run anywhere.
- `create-admin.sh` — create the cluster-wide admin user. Run **once**, on the seed node.
- `deploy-all.sh` — optional orchestrator that SSHes into all three nodes and runs the above in order.

## Installing offline (air-gapped)

`INSTALL_SOURCE` in `cluster.env` picks where packages come from:

- **`offline-debs`** (default) — install from a local `.deb` bundle. Build it once
  on an internet-connected **Ubuntu 24.04 (noble) amd64** staging host (must match
  the nodes' release + architecture):

  ```bash
  cd native-cluster
  sudo ./fetch-packages.sh        # downloads RabbitMQ 4.3.2 + Erlang + deps into packages/
  ```

  Then transfer the whole `native-cluster/` directory (now including `packages/`)
  to each air-gapped node — via `deploy-all.sh`, or manually (USB/scp within the
  enclave). `01-install.sh` installs from `packages/` with no internet; base OS
  dependencies (libc, etc.) come from the internal apt mirror.

- **`apt-repo`** — skip the bundle and install straight from the internal apt
  mirror, if it already carries `rabbitmq-server` + `erlang` for noble. No
  `fetch-packages.sh` needed.

The `packages/` directory is git-ignored (it holds binaries).

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

- http://10.194.178.93:15672
- http://10.194.178.87:15672
- http://10.194.179.85:15672

## Ports that must be open between nodes

| Port  | Purpose |
|-------|---------|
| 4369  | epmd (Erlang port mapper) |
| 25672 | inter-node + CLI Erlang distribution |
| 5672  | AMQP (clients) |
| 15672 | management UI (clients) |

`02-configure.sh` opens these in `ufw` **only if ufw is already active**; otherwise
make sure your network/security groups allow them.

## Notes

- **Version pin:** `RABBITMQ_VERSION` in `cluster.env` (default `4.3.2`) is
  prefix-matched against the apt repo, so it resolves to the exact package (e.g.
  `4.3.2-1`), installs it, and `apt-mark hold`s it so upgrades won't move off it.
  Erlang is installed unpinned from the same repo — that repo only carries Erlang
  releases compatible with the RabbitMQ it ships, so this is normally fine. Set
  `RABBITMQ_VERSION=""` to install the latest instead.
- The shared `ERLANG_COOKIE` and matching hostname list are what let the cluster
  form. Changing hostnames means updating `NODE_HOSTS` in `cluster.env` (the
  `rabbitmq.conf` node list and `/etc/hosts` are generated from it).
- `02-configure.sh` clears `/var/lib/rabbitmq/mnesia` so each node starts clean
  under its new node name. **This wipes local broker data** — intended for a
  fresh build, not for reconfiguring a cluster that already holds data.
- `guest` is loopback-only by design; use the admin user from `create-admin.sh`
  to connect from other machines.
- To point the Spring Boot app (`app/`) at this cluster, set
  `spring.rabbitmq.addresses: 10.194.178.93:5672,10.194.178.87:5672,10.194.179.85:5672`
  and use the admin credentials.
