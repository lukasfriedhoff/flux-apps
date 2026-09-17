#!/bin/sh
# Delta re-sync of ddnss user files -> data/<uid>/files (complete-DB-move layout,
# friendly uids incl h4xx). Resumable (--inplace --partial), 4-way parallel.
SRC=root@10.0.11.22:/mnt/dockerstorage/nextcloud/data
SSHO="ssh -i /root/id -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=30"
LOG=/data/.sync2
mkdir -p "$LOG"
echo "SYNC2_START $(date)" >> "$LOG/_ALL"
cat > /root/nc-sync-one.sh <<'ONE'
#!/bin/sh
u="$1"
SRC=root@10.0.11.22:/mnt/dockerstorage/nextcloud/data
SSHO="ssh -i /root/id -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=30"
LOG=/data/.sync2
mkdir -p "/data/data/$u/files"
echo "START $u $(date)" >> "$LOG/$u.st"
rsync -aH --numeric-ids --chown=33:33 --inplace --partial --whole-file --bwlimit=40960 \
  -e "$SSHO" "$SRC/$u/files/" "/data/data/$u/files/" >> "$LOG/$u.log" 2>&1
echo "DONE $u rc=$? $(date)" >> "$LOG/$u.st"
ONE
chmod +x /root/nc-sync-one.sh
printf "%s\n" h4xx bj vivian jascha annika christoph monika miro pascal friedhoff johanna mascha max landesverbandaphasienrw aphasieshgessen leon jmo jogi jens anni fredde hubi kevin marv milena timo fachschaft1 \
  | xargs -P 4 -I{} sh /root/nc-sync-one.sh {}
echo "SYNC2_DONE $(date)" >> "$LOG/_ALL"
