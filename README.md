# free5GC QoD enforcement experiment

Este repositório contém uma versão sanitizada do ambiente utilizado para
validar enforcement de banda no UPF do free5GC por meio do gtp5g.

## Resultado principal

O experimento controlado utilizou:

    tráfego UDP oferecido: 40 Mbps
    MBR solicitado: 20 Mbps
    GBR solicitado: 10 Mbps
    tráfego recebido: 20 Mbps
    perda UDP: aproximadamente 50%

O resultado demonstra policing de taxa no datapath do UPF/gtp5g.

O experimento não demonstra reserva de recursos no enlace rádio nem
garantia de GBR pelo escalonador da RAN.

## Correções incluídas

A árvore contém:

1. correção do SMF para remoção de QERs residuais após o DELETE;
2. correção da compilação do NEF;
3. configuração OAuth por variáveis de ambiente;
4. expiração e validação consistente do JWT;
5. remoção de tokens dos logs;
6. testes unitários do OAuth e da validação JWT;
7. documentação das condições necessárias para o enforcement;
8. evidências do teste de 40 Mbps limitado a 20 Mbps.

## Problemas identificados no código analisado

O enforcement falhava por causas independentes:

1. DATA selecionava 5QI 9 e produzia QER com MBR e GBR zerados.
2. O filtro aparentemente intuitivo não gerava um PDR que casava com o
   tráfego real de uplink.
3. O gtp5g precisava apresentar QoS Enable: 1.
4. O SMF mantinha QERs e referências residuais após a exclusão.
5. O NEF possuía uma chamada para uma função inexistente.
6. Credenciais e chave JWT estavam fixas no código.
7. Geração e validação do JWT utilizavam chaves diferentes.

## Segurança

Certificados, chaves privadas, credenciais locais e binários compilados
não estão incluídos.

O arquivo .env deve ser criado localmente a partir de:

    free5gc-compose-UERANSIM/.env.example

Os diretórios cert possuem somente arquivos .gitignore. Certificados
próprios devem ser gerados localmente antes da execução.

## Origem

O trabalho deriva do projeto 5G Quality On Demand da Infosys e de
componentes do free5GC. As licenças e atribuições originais foram
preservadas.

A árvore sanitizada foi criada a partir da revisão local que continha:

    documentação do enforcement: d8f8679
    correção do SMF: 5a8c9dc
    correção reproduzível do NEF: 30af2c3
