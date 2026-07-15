#!/usr/bin/env bash

set +e

UPF_CONTAINER="${UPF_CONTAINER:-upf}"
GTP5G_TOOL="${GTP5G_TOOL:-/tmp/gogtp5g-tunnel}"

echo "========== GTP5G QOS =========="

cat /proc/gtp5g/qos 2>&1

echo
echo "========== QER =========="

sudo docker exec \
    "$UPF_CONTAINER" \
    "$GTP5G_TOOL" \
    list qer 2>&1

echo
echo "========== PDR =========="

sudo docker exec \
    "$UPF_CONTAINER" \
    "$GTP5G_TOOL" \
    list pdr 2>&1
