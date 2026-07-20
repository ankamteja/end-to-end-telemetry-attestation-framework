# Step 1 — Building the Network

This is the **first** thing we build: the lab network the whole framework will
later run on. At this stage there is **no telemetry software and no
cryptography** anywhere. We are only standing up machines and wiring them
together so that, later, we have somewhere realistic to run and attack the
attestation framework.

Think of it like building the rooms and hallways of a building before moving
any furniture in. Get the structure right first; the software moves in later.

---

## 1. What the network represents

The framework's job (in later steps) is to make sure telemetry — the security
logs machines produce — is **genuine** before a SIEM (a security monitoring
dashboard) trusts it. To test that honestly, we need four kinds of machine and
a realistic path between them:

| Role | Node(s) | What it is |
|------|---------|------------|
| Telemetry source | `src1`, `src2`, `src3` | Machines that produce logs |
| Router | `r1` | Forwards traffic between network segments |
| Gateway | `gateway` | The box that will guard the SIEM |
| SIEM | `siem` | The security dashboard |
| Attacker | `attacker` | The machine that will try to cheat |
| Switch | `lan-sw` | Connects everything on the local network |

In this step these are just plain Linux boxes with IP addresses. Their special
jobs arrive later.

---

## 2. The shape of the network

The network has **three segments** (think of a segment as one "street" that
machines sit on):

```
        UNTRUSTED LAN  —  10.0.10.0/24
   ┌───────┬───────┬───────┬──────────┐
 src1    src2    src3   attacker    r1(eth1)
 .11     .12     .13     .20         .1
   └───────┴──[ lan-sw ]──┴──────────┘
                              │
                          r1 (router)
                              │  eth2 .1
        TRANSIT  —  10.0.20.0/24
                              │  gateway(eth1) .2
                         gateway (guards SIEM)
                              │  eth2 .1
        SIEM-NET  —  10.0.30.0/24
                              │  siem(eth1) .2
                            siem
```

Reading it top to bottom: a source's log has to travel **down** through the
router `r1`, then through the `gateway`, before it can reach the `siem`. There
is no shortcut. That matters because later the `gateway` is where every log
gets checked — putting it physically in the path means nothing can skip it.

### Why three segments and not one flat network?

Two reasons:

1. **Realism.** Real networks are routed, not one big flat wire. Making the
   log cross a router (`r1`) and a gateway means our later man-in-the-middle
   test is genuine network interception, not a localhost trick.

2. **A believable attacker position.** The `attacker` sits on the **same LAN
   segment** (10.0.10.0/24) as the sources and `r1`. On a shared segment, a
   machine can run **ARP spoofing** to trick its neighbours into sending
   traffic through it — that is the classic man-in-the-middle setup we will
   use in a later step. The attacker deliberately does **not** sit on the
   transit or SIEM segments, because a real attacker who has phished one
   employee laptop would be on the LAN, not inside the security infrastructure.

---

## 3. Addresses (the IP plan)

| Segment | Subnet | Machines |
|---------|--------|----------|
| Untrusted LAN | `10.0.10.0/24` | src1 `.11`, src2 `.12`, src3 `.13`, attacker `.20`, r1 `.1` |
| Transit | `10.0.20.0/24` | r1 `.1`, gateway `.2` |
| SIEM network | `10.0.30.0/24` | gateway `.1`, siem `.2` |

Routing (how each machine knows where to send traffic it can't reach directly):

- **Sources** send anything not on their own street to `r1` (`10.0.10.1`).
- **r1** knows the SIEM street is reached via the `gateway` (`10.0.20.2`).
- **gateway** knows the LAN street is reached back through `r1` (`10.0.20.1`),
  and has IP forwarding turned on so it can pass traffic between its two sides.
- **siem** sends everything back out via the `gateway` (`10.0.30.1`).

`r1` and `gateway` both have `net.ipv4.ip_forward=1` set — without it, a Linux
box drops traffic that isn't addressed to itself instead of forwarding it.

---

## 4. The `lan-sw` switch — and why it's a container, not a setting

The three sources, the attacker, and `r1` all need to be on **one shared
broadcast segment** (so ARP spoofing is possible later). Containerlab normally
links two nodes with a point-to-point virtual cable, which is *not* a shared
segment and *cannot* be man-in-the-middled.

To get a real shared segment without needing root on the host or a pre-created
host bridge, we add a dedicated **switch node** (`lan-sw`). It's an ordinary
container that, on boot, creates an internal Linux bridge (`br0`) and attaches
all five of its ports to it:

```yaml
exec:
  - ip link add name br0 type bridge
  - ip link set br0 up
  - ip link set eth1 master br0   # src1
  - ip link set eth2 master br0   # src2
  - ip link set eth3 master br0   # src3
  - ip link set eth4 master br0   # attacker
  - ip link set eth5 master br0   # r1
```

Now anything sent on the LAN is seen by every machine on it — exactly like a
real dumb switch, and exactly what ARP spoofing needs.

---

## 5. Running it

Prerequisites: **Docker** and **Containerlab** installed, Docker daemon
running.

```bash
# boot the network  (drop SUDO= if you run containerlab rootless)
make net-up SUDO=

# see the nodes and their addresses
make net-inspect SUDO=

# tear it down when done
make net-down SUDO=
```

`make net-up` runs `containerlab deploy -t clab/telemetry.clab.yml`, which
pulls the images (Alpine for hosts, FRRouting for the router, netshoot for the
switch), starts each node, assigns the IPs above, and wires the links.

---

## 6. How to know it actually works

Step 1 is "done" when a **source can reach the SIEM across all three
segments**. That single ping proves the switch, the router, the gateway
forwarding, and every route are all correct:

```bash
make net-test SUDO=
```

which runs:

```bash
docker exec clab-telemetry-attestation-src1 ping -c 3 10.0.30.2
```

If `src1` (on the LAN) gets replies from `siem` (`10.0.30.2`, two segments
away), the packet successfully went:

```
src1 → lan-sw → r1 → gateway → siem   and back
```

That end-to-end path is the foundation everything else is built on.

---

## 7. What this step is NOT

- No telemetry is generated yet.
- No signing, no verification, no SIEM software — the `gateway` and `siem`
  nodes are just routed boxes for now.
- No attacks are run yet.

Those arrive in later steps, on top of this network. Keeping them out for now
means that when something breaks later, we already know the **network** itself
is solid.

---

## 8. File map for this step

| File | Purpose |
|------|---------|
| `clab/telemetry.clab.yml` | The whole network definition (nodes, images, IPs, links) |
| `Makefile` | `net-up` / `net-down` / `net-inspect` / `net-test` shortcuts |
| `docs/network.md` | This document |

Everything else (`agent/`, `gateway/`, `siem/`, `attacker/`, `pki/`,
`common/`) is an empty placeholder describing what will live there in later
steps.
