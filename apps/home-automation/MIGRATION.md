# Home Assistant migration: srv4 VM -> Kubernetes

The migration plan moved to the second-brain vault (private):
`second-brain/10 Projects/Active/Home Assistant k8s Migration.md`
(https://git.h4xx.io/lukasf/second-brain)

Survey correction 2026-09-19: the CP210x USB stick on srv4 is a **Thread
RCP radio, not a Zigbee coordinator** — the zigbee2mqtt deployment here was
built on the wrong assumption and stays at 0 replicas; the plan adds
OTBR + Matter server deployments instead. See the vault plan for phases.
