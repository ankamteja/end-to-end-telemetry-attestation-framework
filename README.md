# End-to-End Telemetry Attestation Framework

A Zero Trust framework that verifies the **integrity, authenticity, and freshness** of security telemetry *before* it reaches the SIEM. Instead of trusting telemetry the moment it arrives, every record is cryptographically attested at the source and validated at an ingest gateway, so tampered, replayed, injected, or dropped events are rejected before they can poison detection.

## Problem

Modern SIEM pipelines implicitly trust the telemetry they receive. Tamper-evident logging protects logs *at rest*, after generation — but nothing verifies telemetry *in transit*, before it is indexed and correlated. An attacker positioned on the telemetry path can:

- **Modify** events to erase traces of malicious activity
- **Replay** old benign events to mask a live attack
- **Inject** fabricated events to mislead analysts or bury real alerts
- **Delete** events to create blind spots
- **Man-in-the-middle** the channel to do any of the above

This framework closes that gap: telemetry is untrusted by default and only processed after attestation succeeds.

## Approach

Each telemetry record is wrapped in a signed attestation envelope:

| Property | Mechanism |
|----------|-----------|
| Integrity | Ed25519 signature over the canonical record |
| Authenticity | Per-source signing key / workload identity |
| Freshness | Monotonic sequence number + timestamp within a skew window |
| Anti-replay | Nonce cache at the verifier |
| Deletion detection | Sequence-gap analysis |

An **attestation sidecar** signs records at the source. An **ingest gateway (verifier)** validates every envelope and forwards only trusted telemetry to the SIEM. All hops use mutual TLS — the gateway trusts the *signature*, never the source IP.

## Architecture

```
[source + sidecar] ─┐
[source + sidecar] ─┼─ [router] ─ [gateway / verifier] ─ [SIEM]
[source + sidecar] ─┤        │
      [attacker] ───────────┘   (MITM / replay / injection segment)
```

- **Sources** — hosts emitting telemetry (auditd, fluent-bit, custom agents), each paired with a signing sidecar
- **Gateway / verifier** — enforces integrity, authenticity, freshness, replay, and deletion checks
- **SIEM** — consumes only the verified stream (Wazuh / Elastic)
- **Attacker** — positioned on the transit segment to exercise the threat model

## Testbed

The network is built with **Docker** and **Containerlab**, giving a realistic routed fabric so man-in-the-middle attacks are genuine L2/L3 interception rather than a localhost shortcut.

| Component | Image / Tool |
|-----------|--------------|
| Telemetry source | Alpine + fluent-bit / auditd |
| Sidecar + gateway | Python (`cryptography`) |
| Router / fabric | FRRouting |
| SIEM | Wazuh (single-node) |
| Attacker | Kali (scapy, bettercap, tcpreplay) |

## Evaluation

The framework is validated through penetration testing, mapping each attack to the defense that must fire:

| Attack | Tooling | Expected defense |
|--------|---------|------------------|
| Telemetry tampering | scapy (edit-in-flight) | Signature verification fails |
| Replay | tcpreplay | Nonce cache + sequence check |
| Fake injection | custom injector | No valid signing key |
| Man-in-the-middle | bettercap (ARP spoof) | mTLS + signature |
| Deletion | packet drop | Sequence-gap detection |

## Status

Early development — topology and attestation prototype in progress.

## License

To be added.
