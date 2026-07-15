#!/usr/bin/env bash

set +e

QOS_FILE="/proc/gtp5g/qos"

if [ ! -e "$QOS_FILE" ]; then
    echo "ERRO: $QOS_FILE não existe."
    echo "Confirme se o módulo gtp5g está carregado."
    exit 1
fi

echo "ESTADO_ANTES:"
cat "$QOS_FILE"

printf '1\n' \
    | sudo tee "$QOS_FILE" \
    >/dev/null

echo
echo "ESTADO_DEPOIS:"
cat "$QOS_FILE"

if grep -q 'QoS Enable: 1' "$QOS_FILE"; then
    echo "GTP5G_QOS_ATIVO=SIM"
else
    echo "GTP5G_QOS_ATIVO=NAO"
    exit 1
fi
