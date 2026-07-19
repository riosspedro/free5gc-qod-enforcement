#!/usr/bin/env bash

set +e

UPF_CONTAINER="${UPF_CONTAINER:-upf}"
GTP5G_TOOL="${GTP5G_TOOL:-/free5gc/gtp5g-tunnel}"

if ! sudo docker exec "$UPF_CONTAINER" test -x "$GTP5G_TOOL" 2>/dev/null; then
    if sudo docker exec "$UPF_CONTAINER" test -x /tmp/gogtp5g-tunnel 2>/dev/null; then
        GTP5G_TOOL="/tmp/gogtp5g-tunnel"
        echo "AVISO: usando ferramenta temporaria em $GTP5G_TOOL"
    else
        echo "ERRO: gtp5g-tunnel nao encontrado no container $UPF_CONTAINER"
        GTP5G_TOOL=""
    fi
fi

echo "========== GTP5G QOS =========="

cat /proc/gtp5g/qos 2>&1

echo
echo "========== QER =========="

if [ -n "$GTP5G_TOOL" ]; then
    sudo docker exec "$UPF_CONTAINER" "$GTP5G_TOOL" list qer 2>&1
else
    echo "INDISPONIVEL"
fi

echo
echo "========== PDR =========="

if [ -n "$GTP5G_TOOL" ]; then
    sudo docker exec "$UPF_CONTAINER" "$GTP5G_TOOL" list pdr 2>&1
else
    echo "INDISPONIVEL"
fi
