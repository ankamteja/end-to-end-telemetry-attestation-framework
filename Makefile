# Step 1 -- network lifecycle.
# Requires: docker + containerlab installed and the docker daemon reachable.
#
# Most containerlab installs need root, so commands default to `sudo`.
# If your user can run containerlab/docker rootless (e.g. in the `clab_admins`
# and `docker` groups), disable it:   make net-up SUDO=

SUDO ?= sudo
CLAB := clab/telemetry.clab.yml

.PHONY: net-up net-down net-test net-graph net-inspect

net-up:          ## boot the testbed network
	$(SUDO) containerlab deploy -t $(CLAB)

net-down:        ## tear the network down
	$(SUDO) containerlab destroy -t $(CLAB) --cleanup

net-inspect:     ## list running nodes and their addresses
	$(SUDO) containerlab inspect -t $(CLAB)

net-graph:       ## render the topology diagram in a browser
	$(SUDO) containerlab graph -t $(CLAB)

# End-to-end reachability: a source must reach the SIEM THROUGH r1 + gateway.
net-test:        ## ping src1 -> siem across all three segments
	@echo "src1 -> siem (10.0.30.2) via r1 + gateway:"
	$(SUDO) docker exec clab-telemetry-attestation-src1 ping -c 3 10.0.30.2
	@echo "src1 -> r1 LAN gateway (10.0.10.1):"
	$(SUDO) docker exec clab-telemetry-attestation-src1 ping -c 2 10.0.10.1
