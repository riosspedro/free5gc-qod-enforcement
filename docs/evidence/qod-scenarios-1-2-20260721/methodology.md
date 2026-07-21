# Cenários experimentais 1 e 2

## Condições comuns

Os dois cenários utilizam a mesma fonte sintética H.264, o mesmo caminho
UE–UPF–servidor, transmissão UDP uniformemente espaçada, 300 frames,
resolução 1280x720, 30 fps e validação por decodificação e SHA-256.

## Cenário 1 — best-effort

Nenhuma sessão QoD é solicitada, independentemente do bitrate observado.
O tráfego utiliza apenas o QER padrão da PDU Session.

## Cenário 2 — regras fixas

O bitrate da aplicação é medido com ffprobe antes da transmissão. Quando
o valor observado ultrapassa 4.000.000 bit/s, o executor solicita o perfil
QOS_M, mantém a sessão durante o vídeo e a exclui após a transmissão.

## Limitação metodológica

O gatilho do cenário 2 é uma métrica da aplicação medida antes da
transmissão. Ele representa uma política determinística por limiar, mas
não corresponde ainda a uma decisão baseada em degradação de rede
observada em tempo real. Essa distinção deve ser mantida na dissertação.
