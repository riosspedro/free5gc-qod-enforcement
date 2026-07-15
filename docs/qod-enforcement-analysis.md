# Análise e reprodução do enforcement de QoS

## Resultado validado

O experimento demonstrou policing de taxa no uplink pelo UPF e pelo
módulo de kernel gtp5g.

Parâmetros utilizados:

| Parâmetro | Valor |
|---|---:|
| Endereço do UE | 10.61.0.1 |
| Servidor iperf3 | 10.100.200.1 |
| Tráfego UDP oferecido | 40 Mbps |
| MBR configurado | 20 Mbps |
| GBR configurado | 10 Mbps |
| Taxa recebida | 20 Mbps |
| Perda UDP | aproximadamente 50% |

A perda de aproximadamente 50% é compatível com um emissor oferecendo
40 Mbps a um fluxo limitado a 20 Mbps.

## Fluxo funcional

O caminho testado foi:

    Cliente QoD
        |
        v
       NEF
        |
        v
       PCF
        |
        v
       SMF
        |
        v
    UPF / gtp5g
        |
        v
    UE UERANSIM

## Problema 1: perda dos valores de banda no PCF

O NEF encaminhava corretamente os seguintes valores:

    mirBwUl: 10 Mbps
    mirBwDl: 10 Mbps
    marBwUl: 20 Mbps
    marBwDl: 20 Mbps

Quando o componente era enviado com `medType: DATA`, o PCF selecionava
5QI 9.

Nesse caminho, o PCF criava o objeto de QoS com os seguintes campos
vazios:

    MaxbrUl
    MaxbrDl
    GbrUl
    GbrDl

Consequentemente, o SMF criava um QER dedicado com MBR e GBR iguais a
zero. A sessão era criada com sucesso, mas nenhuma limitação de banda
era aplicada.

Esse comportamento é inadequado porque a API aceita os valores de banda,
mas a implementação os descarta silenciosamente.

### Correção validada

O uso de `medType: VIDEO` fez o PCF selecionar 5QI 2 e preencher:

    MaxbrUl: 20 Mbps
    MaxbrDl: 20 Mbps
    GbrUl: 10 Mbps
    GbrDl: 10 Mbps

O SMF então gerou um QER com:

    UL MBR: 20000 kbps
    DL MBR: 20000 kbps
    UL GBR: 10000 kbps
    DL GBR: 10000 kbps

### Correção estrutural recomendada

O PCF deve:

1. Validar a compatibilidade entre o 5QI selecionado e os valores de
   GBR e MBR solicitados.
2. Não aceitar uma solicitação de banda e depois gerar um QER com taxas
   iguais a zero.
3. Rejeitar explicitamente combinações incompatíveis ou selecionar um
   perfil de QoS adequado.
4. Separar a escolha do 5QI do texto literal utilizado em `medType`.
5. Adicionar testes unitários para DATA, VIDEO, GBR e non-GBR.

## Problema 2: direção do filtro de tráfego

O filtro inicialmente utilizado para representar o tráfego do UE para o
servidor foi:

    permit in ip from 10.61.0.1 to 10.100.200.1

Apesar de o PCF indicar direção UPLINK, os PDRs gerados não fizeram o
tráfego iperf3 passar pelo QER dedicado.

O tráfego continuou utilizando o PDR default associado ao QER de
1 Gbps. Por isso, o receptor obteve aproximadamente 39,9 Mbps.

### Filtro validado nesta implementação

O filtro que produziu o PDR de uplink funcional foi:

    permit out ip from any to 10.61.0.1

Esse filtro resultou em um PDR com:

    F-TEID presente
    origem: 10.61.0.1
    destino: any
    QER associado: QER dedicado de 20 Mbps

Essa interpretação é contraintuitiva e deve ser tratada como uma
particularidade da implementação analisada.

### Correção estrutural recomendada

A conversão entre FlowDescription, FlowDirection e PDR deve possuir
testes que verifiquem diretamente:

1. Tráfego uplink com origem no endereço do UE.
2. Tráfego downlink com destino no endereço do UE.
3. Presença de F-TEID no PDR do lado de acesso.
4. Associação do PDR ao QER dedicado.
5. Endereço e porta do servidor de aplicação.
6. Ausência de fallback indevido para o QER default.

## Problema 3: QoS desabilitado no gtp5g

A instalação de um QER não garante que o datapath aplicará a limitação.

O arquivo `/proc/gtp5g/qos` precisa indicar:

    QoS Enable: 1

Quando esse recurso está desabilitado, os QERs podem aparecer na
inspeção do UPF, mas a taxa não é limitada.

### Correção necessária

A inicialização do ambiente deve:

1. Confirmar que o módulo gtp5g está carregado.
2. Habilitar o mecanismo de QoS.
3. Ler novamente `/proc/gtp5g/qos`.
4. Interromper o teste caso o valor continue desabilitado.

## Problema 4: QERs residuais após o DELETE

Na implementação original, a exclusão da sessão QoD removia a PCC Rule
no PCF, mas o SMF não removia corretamente todos os QERs, PDRs e
mapeamentos associados.

Isso causava:

1. QERs dedicados residuais.
2. PDRs referenciando regras antigas.
3. resultados diferentes em execuções consecutivas;
4. crescimento indevido das estruturas internas do SMF.

### Correção implementada

O commit abaixo corrige a limpeza:

    670033b fix(smf): remove stale QERs after QoD deletion

A correção:

1. identifica PCC Rules removidas;
2. localiza os QERs associados;
3. remove associações entre PDR e QER;
4. remove QERs não utilizados;
5. limpa o mapa interno QerUpfMap;
6. preserva o QER default;
7. evita remover um QER ainda compartilhado por outra regra.

## Problema no Open QoD Gateway

O gateway atual recebe `applicationServer`, mas o endereço não é
utilizado na construção do filtro enviado ao NEF.

O filtro é montado somente com o endereço do UE:

    permit out ip from any to endereço-do-UE

Isso funcionou no experimento devido ao comportamento específico do PCF,
mas não representa corretamente o servidor de aplicação solicitado pela
API.

### Correção recomendada para o gateway

O gateway deve:

1. utilizar `applicationServer.ipv4Address`;
2. permitir selecionar uplink, downlink ou bidirecional;
3. construir o filtro de acordo com o comportamento validado do PCF;
4. verificar após a criação se o QER possui MBR e GBR;
5. retornar erro caso o NEF crie uma sessão sem enforcement efetivo;
6. registrar o ID da assinatura NEF e o perfil aplicado.

## Evidência do enforcement

Durante a sessão, o QER dedicado possuía:

    UL MBR: 20000 kbps
    DL MBR: 20000 kbps
    UL GBR: 10000 kbps
    DL GBR: 10000 kbps

O comando de tráfego foi:

    docker exec ueransim iperf3 \
        -c 10.100.200.1 \
        -B 10.61.0.1 \
        -p 5201 \
        -u \
        -b 40M \
        -t 20 \
        -i 1

Resultado:

    sender:   40.0 Mbits/sec
    receiver: 20.0 Mbits/sec
    loss:     approximately 50%

Após o DELETE, o QER dedicado e os PDRs específicos foram removidos,
enquanto o QER default permaneceu ativo.

## Limites da conclusão

O experimento comprova policing de MBR no datapath do UPF/gtp5g.

O experimento não comprova:

1. reserva de recursos no enlace rádio;
2. garantia de GBR pelo escalonador da RAN;
3. comportamento em uma estação rádio-base física;
4. conformidade completa com a API CAMARA QoD;
5. reprodução integral do componente proprietário IEAM.
