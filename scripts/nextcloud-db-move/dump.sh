#!/bin/sh
# Dump the ddnss Nextcloud DB from the docker-host. NOTE: do NOT use
# --routines/--triggers (the nextcloud DB user lacks the privilege and mysqldump
# silently produces 0 bytes). Streaming through `kubectl exec` mangles the
# binary gzip — dump to a source file, then have the migration pod rsync it in.
set -e
DBPW=$(grep dbpassword /mnt/dockerstorage/nextcloud/config/config.php | sed -E "s/.*=> '([^']*)'.*/\1/")
docker exec nextcloud-db-1 mysqldump -u nextcloud -p"$DBPW" \
  --single-transaction --quick --default-character-set=utf8mb4 nextcloud \
  2>/tmp/dumperr | gzip -1 > /root/ddnss.sql.gz
echo "rc=$? size=$(stat -c %s /root/ddnss.sql.gz) err=$(head -1 /tmp/dumperr)"
