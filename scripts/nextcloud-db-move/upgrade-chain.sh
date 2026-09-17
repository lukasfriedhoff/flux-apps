#!/bin/bash
C="kubectl --context homelab-prod"
for v in 33 34; do
  echo "=== BUMP to NC$v $(date +%T) ==="
  $C -n nextcloud set image deploy/conv-nc nc=nextcloud:$v-apache >/dev/null 2>&1
  $C -n nextcloud rollout status deploy/conv-nc --timeout=240s 2>&1 | tail -1
  NCP=$($C -n nextcloud get pods -l app=conv-nc --no-headers | awk '$3=="Running"{print $1;exit}')
  for i in $(seq 1 40); do $C -n nextcloud logs $NCP -c nc 2>/dev/null | grep -q NC_READY && break; sleep 3; done
  echo "code: $($C -n nextcloud exec $NCP -c nc -- sh -c 'grep OC_VersionString /var/www/html/version.php' 2>/dev/null)"
  $C -n nextcloud exec $NCP -c nc -- su -s /bin/sh www-data -c "setsid sh -c 'php /var/www/html/occ upgrade > /var/www/html/data/upg$v.log 2>&1; echo UPG_DONE rc=\$? >> /var/www/html/data/upg$v.log' >/dev/null 2>&1 &" 2>/dev/null
  for i in $(seq 1 80); do $C -n nextcloud exec $NCP -c nc -- grep -q UPG_DONE /var/www/html/data/upg$v.log 2>/dev/null && break; sleep 15; done
  echo "NC$v: $($C -n nextcloud exec $NCP -c nc -- sh -c "grep -iE 'update successful|UPG_DONE|Exception|fatal' /var/www/html/data/upg$v.log 2>/dev/null | tail -2" 2>/dev/null)"
  echo "status: $($C -n nextcloud exec $NCP -c nc -- su -s /bin/sh www-data -c 'php /var/www/html/occ status 2>&1' 2>/dev/null | grep versionstring)"
done
echo "CHAIN_DONE $(date +%T)"
