#!/bin/sh
set -eu
image=$1
expected=$2
cid=$(docker run -d -p 127.0.0.1::80 "$image")
trap 'docker rm -f "$cid" >/dev/null' EXIT
port=$(docker port "$cid" 80/tcp | awk -F: '{print $NF}')
i=0
until curl -fsS "http://127.0.0.1:$port/healthz" >/dev/null; do
  i=$((i+1)); [ "$i" -lt 20 ] || exit 1; sleep 1
done
curl -fsS "http://127.0.0.1:$port/" > /tmp/assess-page-"$cid".html
grep -q "$expected" /tmp/assess-page-"$cid".html
rm /tmp/assess-page-"$cid".html
printf 'PASS HTTP health and content: %s\n' "$image"
