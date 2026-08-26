# Home Assistant: srv4 VM -> Kubernetes migration plan

## Current state (surveyed 2026-08-26)
- libvirt VM `homeassistant` on srv4 (RHEL9), bridged to br-vlan12 (IoT VLAN)
- Zigbee coordinator: Silicon Labs CP210x USB stick attached to srv4
- Target stack (deployed, running): namespace `home-automation` on srv9 —
  Home Assistant (hostNetwork, ha.h4xx.io, own auth), Mosquitto (ClusterIP),
  zigbee2mqtt (scaled to 0 until the dongle moves)

## Phase 1 — restore HA identity (no downtime, reversible)
1. On the VM: Settings -> System -> Backups -> create full backup, download.
2. Open ha.h4xx.io (fresh instance, onboarding screen) -> "Restore from
   backup" -> upload. Automations, integrations, users and history come along.
3. Sanity-check dashboards/integrations. The VM keeps running untouched —
   both instances can coexist while you compare (they poll devices
   independently; avoid enabling duplicate MQTT/Zigbee yet).

## Phase 2 — MQTT
- If the VM runs a Mosquitto add-on: repoint HA's MQTT integration to
  `mosquitto.home-automation.svc.cluster.local:1883` (in-cluster HA reaches
  it directly).
- IoT devices that publish to the broker from vlan12 need a reachable
  address: expose mosquitto with a hostPort/NodePort on srv9 and allow
  vlan12 -> 10.1.30.31:1883 on the MikroTik, then update device configs.

## Phase 3 — Zigbee cutover (the only real downtime, ~15 min)
1. Export the Zigbee network backup from the VM (ZHA: integration -> download
   backup; z2m: copy `coordinator_backup.json`).
2. Shut down Zigbee on the VM (disable ZHA / stop z2m add-on).
3. Move the CP210x stick from srv4 to srv9.
4. `ls /dev/serial/by-id/` on srv9 -> set `ha_zigbee_serial` to that path and
   `ha_zigbee2mqtt_replicas: "1"` in overlays/homelab/cluster-patch.yaml.
5. If coming from ZHA: place the exported backup as
   `coordinator_backup.json` in the zigbee2mqtt data volume before first
   start so the mesh (PAN ID, network key) survives without re-pairing.
6. Pair check at zigbee.h4xx.io; add the MQTT integration in HA if absent.

## Phase 4 — decommission
- Disable VM autostart (`virsh autostart --disable homeassistant`), keep it
  as rollback for ~2 weeks, then delete. srv4 keeps only the docker-host VM.

## Known limitation
srv9's hostNetwork puts HA on the mgmt VLAN; mDNS/SSDP discovery across to
vlan12 does not traverse VLANs. Zigbee and MQTT are unaffected. For
discovery-dependent integrations either add an mDNS repeater on the MikroTik
or configure those integrations by IP.
