# Reproducible free5GC Quality-on-Demand Enforcement Experiment

Este repositório contém uma **sanitized repository snapshot** do ambiente
utilizado para reproduzir, corrigir e validar um experimento de
Quality-on-Demand sobre o free5GC.

A snapshot foi criada com histórico Git novo e sem:

- chaves privadas;
- certificados de laboratório;
- arquivos `.env` reais;
- tokens;
- credenciais;
- bancos de dados de execução;
- binários compilados;
- artefatos temporários do ambiente original.

O objetivo principal é permitir a análise do fluxo:

```text
Application
    |
    v
Open QoD Gateway
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
UERANSIM UE traffic
```

O experimento demonstrou **policing de taxa no datapath do UPF**, com
tráfego UDP oferecido a aproximadamente 40 Mbit/s e recebido a
aproximadamente 20 Mbit/s quando um QER com MBR de 20 Mbit/s estava
corretamente associado ao PDR de uplink.

> O resultado não comprova reserva de recursos no enlace rádio nem
> garantia de GBR pelo scheduler de uma RAN real.

---

## 1. Escopo do projeto

Este projeto investiga como uma aplicação externa pode solicitar QoS
dinamicamente e como essa solicitação é propagada pelo core 5G até o
plano de dados.

Foram analisados e utilizados:

- free5GC;
- UERANSIM;
- NEF;
- PCF;
- SMF;
- UPF;
- gtp5g;
- PFCP;
- PDR;
- FAR;
- QER;
- OAuth2;
- JWT;
- Open QoD Gateway;
- conceitos da API CAMARA Quality-on-Demand;
- arquitetura IEAM apresentada pela Infosys.

---

## 2. Conceitos principais

### 2.1 CAMARA

CAMARA define APIs padronizadas para exposição de capacidades de rede a
aplicações.

No contexto deste experimento, CAMARA representa o **contrato externo de
API** pelo qual uma aplicação solicita determinado tratamento de QoS.

CAMARA não é o core 5G e não aplica diretamente regras no UPF.

Uma implementação típica precisa traduzir a solicitação CAMARA para a
interface interna utilizada pelo operador ou pelo core 5G.

---

### 2.2 IEAM

Na arquitetura descrita pela Infosys, o IEAM aparece como uma camada
intermediária entre a aplicação que consome uma API de QoD e o NEF do
core 5G.

As responsabilidades esperadas dessa camada incluem:

1. receber a solicitação da aplicação;
2. autenticar e autorizar o cliente;
3. interpretar o perfil de QoS solicitado;
4. validar o dispositivo e o servidor de aplicação;
5. converter o pedido para o modelo aceito pelo NEF;
6. criar uma assinatura `AS Session with QoS`;
7. manter a correspondência entre a sessão externa e o recurso interno;
8. atualizar ou excluir a sessão;
9. controlar sua duração;
10. retornar à aplicação o estado da solicitação.

O repositório público analisado não continha uma implementação completa e
reproduzível do IEAM com código, imagem, configuração e procedimento de
inicialização suficientes para executar todas essas funções.

Por esse motivo, o IEAM não foi diretamente reproduzido.

---

### 2.3 Open QoD Gateway

O Open QoD Gateway foi desenvolvido como uma substituição funcional para
o subconjunto de funções do IEAM necessário ao experimento.

Repositório:

```text
https://github.com/riosspedro/open-qod-gateway
```

O gateway foi implementado em Python e FastAPI e realiza:

- OAuth2 `client_credentials`;
- emissão e validação de JWT;
- escopos `qod:read` e `qod:write`;
- criação de sessões;
- consulta de sessões;
- atualização de sessões;
- exclusão de sessões;
- expiração automática;
- persistência em SQLite;
- tradução de perfis de QoS;
- obtenção de token OAuth2 do NEF;
- criação de recursos `AS Session with QoS`;
- associação entre o identificador público e o identificador do NEF.

O gateway não substitui o NEF.

Ele recebe a solicitação externa e chama o próprio NEF do free5GC.

#### Limites do gateway

O Open QoD Gateway:

- não é uma reprodução integral do produto IEAM da Infosys;
- não implementa todas as funções possivelmente existentes no IEAM;
- não declara conformidade integral com todas as versões da API CAMARA;
- não executa orquestração de infraestrutura;
- não gerencia PCF, SMF ou UPF diretamente;
- não substitui o core 5G;
- não implementa Nephio;
- utiliza um modo de compatibilidade de filtro para o ambiente analisado.

No ambiente reproduzido, o filtro amplo compatível com a implementação
Infosys foi necessário para gerar um PDR de uplink que realmente
correspondesse ao tráfego medido.

Isso comprova o enforcement no UPF, mas não representa ainda uma
classificação completa e específica por servidor de aplicação conforme
a semântica final esperada de uma implementação CAMARA comercial.

---

### 2.4 NEF

O Network Exposure Function é o ponto de exposição do core 5G.

Neste projeto, o NEF:

- recebe a solicitação `AS Session with QoS`;
- autentica o cliente;
- identifica a PDU Session do UE;
- envia a solicitação ao PCF;
- mantém o recurso da assinatura;
- processa criação, atualização e exclusão.

---

### 2.5 PCF

O Policy Control Function cria a política de controle correspondente à
solicitação recebida.

O PCF produz estruturas como:

- PCC Rule;
- QoS Data;
- Traffic Control Data;
- referência ao 5QI;
- parâmetros de MBR e GBR.

Foi observado que pedidos do tipo `DATA`, associados ao 5QI 9, podiam
produzir `QosData` sem valores efetivos de MBR e GBR.

Nenhuma correção de código do PCF é declarada neste repositório.

O caminho validado utilizou uma combinação compatível com o comportamento
existente do PCF, gerando valores efetivos de banda antes de o pedido
chegar ao SMF.

---

### 2.6 SMF

O Session Management Function transforma a política recebida em regras
que serão enviadas ao UPF por PFCP.

O SMF é responsável por criar, modificar e remover:

- PDR;
- FAR;
- QER;
- URR;
- associações entre QFI, regras PCC e sessões PFCP.

A correção incluída neste repositório remove QERs residuais e referências
obsoletas após a exclusão de uma sessão QoD.

---

### 2.7 UPF e gtp5g

O User Plane Function encaminha os pacotes reais do usuário.

No ambiente utilizado, o UPF usa o módulo de kernel `gtp5g`.

O `gtp5g` mantém as regras instaladas pelo SMF, incluindo:

- PDR, para identificar o tráfego;
- FAR, para definir encaminhamento;
- QER, para aplicar QoS;
- URR, para medição de uso.

O enforcement de MBR só ocorre quando:

1. o módulo `gtp5g` está carregado;
2. `/proc/gtp5g/qos` contém `1`;
3. o QER possui MBR válido;
4. o PDR referencia o QER correto;
5. o filtro do PDR corresponde ao tráfego real.

---

### 2.8 UERANSIM

O UERANSIM simula:

- um gNB;
- um ou mais UEs;
- registro 5G;
- estabelecimento de PDU Session;
- interfaces de túnel como `uesimtun0`.

O UERANSIM permite validar protocolos e integração do core, mas não
reproduz integralmente:

- espectro;
- fading;
- interferência;
- scheduler de rádio;
- potência;
- mobilidade física;
- capacidade real de uma RAN.

---

### 2.9 Nephio

Nephio é relacionado à automação de implantação e ciclo de vida de
funções de rede.

Ele pode ser relevante em uma reprodução completa de um blueprint com
orquestração declarativa de infraestrutura.

Nephio não participa obrigatoriamente do caminho de execução de uma
solicitação QoD já implantada.

O caminho de runtime validado neste projeto foi:

```text
Open QoD Gateway
    -> NEF
    -> PCF
    -> SMF
    -> UPF
```

Nephio não foi utilizado.

---

## 3. Resultado principal

O experimento controlado utilizou:

```text
Tráfego UDP oferecido:       aproximadamente 40 Mbit/s
MBR configurado no QER:      20 Mbit/s
GBR configurado no QER:      10 Mbit/s
Tráfego recebido:            aproximadamente 20 Mbit/s
Perda UDP observada:         aproximadamente 50%
```

A cadeia validada foi:

```text
POST da sessão QoD
    -> NEF cria AS Session with QoS
    -> PCF cria política
    -> SMF gera regras PFCP
    -> UPF instala QER e PDR
    -> gtp5g aplica o limite
```

Após a exclusão:

```text
DELETE da sessão QoD
    -> NEF remove a assinatura
    -> PCF remove a política
    -> SMF envia PFCP Session Modification
    -> UPF remove o PDR e QER dedicados
```

### Formulação técnica correta

> O experimento demonstra policing ou limitação de taxa no UPF por meio
> do gtp5g. Ele não demonstra reserva de recursos no enlace rádio nem
> garantia de GBR pelo escalonador da RAN.

---

## 4. Correções incluídas

A snapshot contém:

1. correção do SMF para remoção de QERs residuais após `DELETE`;
2. remoção de referências obsoletas em `QerUpfMap`;
3. deduplicação de QERs compartilhados;
4. testes do processamento PFCP;
5. remoção de uma rota inexistente no NEF;
6. correção da compilação do NEF;
7. configuração OAuth do NEF por variáveis de ambiente;
8. remoção de client secret fixo;
9. remoção de chave JWT fixa;
10. expiração de tokens JWT;
11. validação consistente entre emissão e leitura do JWT;
12. restrição do algoritmo JWT a HS256;
13. remoção de tokens dos logs;
14. testes unitários do OAuth;
15. testes unitários da validação JWT;
16. `.env.example` sem credenciais reais;
17. scripts para inspeção de PDR e QER;
18. script para habilitação de QoS no gtp5g;
19. evidências do experimento;
20. documentação das limitações.

---

## 5. Problemas identificados

Os seguintes problemas foram encontrados durante a reprodução:

### 5.1 Imagens customizadas não públicas

O Compose original fazia referência a imagens customizadas que não
estavam disponíveis publicamente.

A reprodução precisa usar imagens construídas localmente a partir do
código-fonte.

---

### 5.2 Rota inexistente no NEF

O servidor NEF registrava uma função `getQoSEndpoints()` que não existia
no código fornecido.

Essa chamada impedia a compilação completa da SBI.

A rota residual foi removida. A API utilizada no experimento é
`AS Session with QoS`.

---

### 5.3 Credenciais fixas no NEF

O código original continha:

- client ID fixo;
- client secret fixo;
- chave JWT fixa.

Esses valores foram substituídos por:

```text
NEF_OAUTH_CLIENT_ID
NEF_OAUTH_CLIENT_SECRET
NEF_OAUTH_JWT_SIGNING_KEY
```

---

### 5.4 Geração e validação JWT inconsistentes

A geração e a validação utilizavam chaves diferentes.

O NEF podia emitir um token que seria rejeitado pelo próprio validador.

A emissão e a validação agora usam a mesma variável de ambiente.

---

### 5.5 Tokens nos logs

O header `Authorization` e o token completo podiam aparecer nos logs.

Essas mensagens foram removidas.

---

### 5.6 DATA e 5QI 9 sem banda efetiva

Foi observado que uma solicitação com:

```text
medType: DATA
5QI: 9
```

podia criar a política sem preencher:

```text
MaxbrUl
MaxbrDl
GbrUl
GbrDl
```

O resultado era um QER com valores zerados e sem enforcement
quantitativo.

---

### 5.7 Direção do filtro

Um filtro aparentemente intuitivo para o fluxo UE-servidor produziu um
PDR que não correspondia ao tráfego real de uplink.

O tráfego continuava utilizando o QER default.

Um filtro compatível com a conversão implementada no ambiente Infosys
produziu o PDR de uplink correto.

---

### 5.8 QoS desabilitado no gtp5g

Mesmo com QER e PDR corretos, não há policing quando:

```text
QoS Enable: 0
```

O valor necessário é:

```text
QoS Enable: 1
```

---

### 5.9 QER residual após DELETE

O SMF removia a política, mas podia manter:

- QER residual;
- referência no PDR;
- referência em `QerUpfMap`.

A correção incluída remove esse estado residual.

---

## 6. Estrutura do repositório

```text
.
├── Free5gc_Source_code/
│   ├── amf/
│   ├── ausf/
│   ├── chf/
│   ├── go-upf/
│   ├── n3iwf/
│   ├── nef/
│   ├── nrf/
│   ├── nssf/
│   ├── pcf/
│   ├── smf/
│   ├── tngf/
│   ├── udm/
│   └── udr/
├── free5gc-compose-UERANSIM/
├── free5gc-compose-external_gNB/
├── docs/
│   ├── evidence/
│   └── qod-enforcement-analysis.md
├── scripts/
│   ├── enable-gtp5g-qos.sh
│   └── inspect-qod-rules.sh
├── README.md
├── README-INFOSYS.md
├── SECURITY.md
└── .gitignore
```

`README-INFOSYS.md` preserva as instruções fornecidas no repositório de
origem.

---

# 7. Tutorial completo de instalação

## 7.1 Ambiente recomendado

O ambiente reproduzido utilizou:

```text
Sistema operacional: Ubuntu 22.04
Kernel:              Linux 5.15
Docker:              27.5.0
Docker Compose:      plugin docker compose
Go:                  1.25.4
gtp5g:               v0.9.11
UERANSIM:             v3.2.8
```

Recursos recomendados:

```text
CPU:       8 vCPUs ou mais
Memória:   16 GB ou mais
Disco:     100 GB ou mais
```

O repositório original recomenda até 16 vCPUs, 16 GB de memória e
250 GB de armazenamento para builds e execução completos.

---

## 7.2 Instalar pacotes básicos

```bash
sudo apt update

sudo apt install -y \
  ca-certificates \
  curl \
  wget \
  git \
  jq \
  openssl \
  make \
  gcc-12 \
  g++-12 \
  build-essential \
  linux-headers-$(uname -r) \
  iproute2 \
  iptables \
  iperf3 \
  tcpdump \
  net-tools \
  python3 \
  python3-venv \
  python3-pip
```

---

## 7.3 Instalar Docker

```bash
sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor \
  -o /etc/apt/keyrings/docker.gpg

sudo chmod a+r /etc/apt/keyrings/docker.gpg

. /etc/os-release

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list \
  >/dev/null

sudo apt update

sudo apt install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

sudo usermod -aG docker "$USER"
```

Reconecte a sessão SSH para que o grupo `docker` seja aplicado.

Valide:

```bash
docker version
docker compose version
```

---

## 7.4 Instalar Go

```bash
cd /tmp

GO_VERSION="1.25.4"

wget \
  "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"

sudo rm -rf /usr/local/go

sudo tar \
  -C /usr/local \
  -xzf "go${GO_VERSION}.linux-amd64.tar.gz"

echo 'export PATH=/usr/local/go/bin:$PATH' \
  | sudo tee /etc/profile.d/go.sh

source /etc/profile.d/go.sh

go version
```

---

## 7.5 Instalar gtp5g

```bash
cd "$HOME"

git clone \
  --branch v0.9.11 \
  --depth 1 \
  https://github.com/free5gc/gtp5g.git

cd gtp5g

make clean
make -j"$(nproc)"

sudo make install
sudo depmod -a
sudo modprobe gtp5g
```

Valide:

```bash
lsmod | grep gtp5g

modinfo gtp5g \
  | grep -E 'version|filename'

ls -la /proc/gtp5g
```

Habilite QoS:

```bash
echo 1 \
  | sudo tee /proc/gtp5g/qos

cat /proc/gtp5g/qos
```

O resultado deve ser:

```text
1
```

### Persistir após reinicialização

```bash
echo gtp5g \
  | sudo tee /etc/modules-load.d/gtp5g.conf
```

Crie o serviço:

```bash
sudo tee \
  /etc/systemd/system/gtp5g-qos.service \
  >/dev/null <<'UNIT'
[Unit]
Description=Enable QoS in gtp5g
After=systemd-modules-load.service
Requires=systemd-modules-load.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo 1 > /proc/gtp5g/qos'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
```

Ative:

```bash
sudo systemctl daemon-reload

sudo systemctl enable \
  --now \
  gtp5g-qos.service

cat /proc/gtp5g/qos
```

O repositório também contém:

```bash
sudo ./scripts/enable-gtp5g-qos.sh
```

---

## 7.6 Clonar este repositório

```bash
mkdir -p "$HOME/dissertacao_repos"

cd "$HOME/dissertacao_repos"

git clone \
  git@github.com:riosspedro/free5gc-qod-enforcement.git

cd free5gc-qod-enforcement
```

---

## 7.7 Configurar credenciais OAuth do NEF

Entre no diretório do Compose:

```bash
cd free5gc-compose-UERANSIM
```

Crie o `.env` local:

```bash
NEF_CLIENT_SECRET="$(openssl rand -hex 32)"
NEF_JWT_KEY="$(openssl rand -hex 48)"

cat > .env <<EOF
NEF_OAUTH_CLIENT_ID=open-qod-gateway
NEF_OAUTH_CLIENT_SECRET=${NEF_CLIENT_SECRET}
NEF_OAUTH_JWT_SIGNING_KEY=${NEF_JWT_KEY}
EOF

chmod 600 .env
```

Confirme que o arquivo não será rastreado:

```bash
git check-ignore -v .env
```

Nunca envie `.env` ao GitHub.

---

## 7.8 Gerar certificados locais para o NEF

Os certificados não são distribuídos no repositório.

Crie o diretório:

```bash
COMPOSE_DIR="$PWD"
CERT_DIR="$COMPOSE_DIR/cert"

mkdir -p "$CERT_DIR"

cd "$CERT_DIR"
```

Crie uma autoridade certificadora local:

```bash
openssl req \
  -x509 \
  -newkey rsa:4096 \
  -sha256 \
  -nodes \
  -days 3650 \
  -keyout ca.key \
  -out ca.pem \
  -subj "/CN=free5gc-lab-ca"
```

Crie a chave e o CSR do NEF:

```bash
openssl genrsa \
  -out nef.key \
  2048

openssl req \
  -new \
  -key nef.key \
  -out nef.csr \
  -subj "/CN=nef.free5gc.org"
```

Crie a extensão SAN:

```bash
cat > nef.ext <<'EOF'
subjectAltName=DNS:nef.free5gc.org,IP:10.100.200.9
extendedKeyUsage=serverAuth
EOF
```

Assine o certificado:

```bash
openssl x509 \
  -req \
  -in nef.csr \
  -CA ca.pem \
  -CAkey ca.key \
  -CAcreateserial \
  -out nef.pem \
  -days 825 \
  -sha256 \
  -extfile nef.ext
```

Proteja as chaves:

```bash
chmod 600 \
  ca.key \
  nef.key
```

O endereço `10.100.200.9` deve ser conferido no
`docker-compose-build.yaml`. Caso o endereço do NEF seja diferente,
ajuste o SAN antes de assinar o certificado.

### Modo de laboratório

Para a reprodução mínima, pode-se utilizar TLS do servidor sem exigir
certificado de cliente.

Confira em:

```text
free5gc-compose-UERANSIM/config/nefcfg.yaml
```

O bloco deve conter os arquivos corretos e, no modo de laboratório:

```yaml
tls:
  pem: cert/nef.pem
  key: cert/nef.key
  caPem: cert/ca.pem
  verifyClient: false
```

A validação mTLS completa deve ser tratada como uma etapa adicional de
hardening.

---

## 7.9 Preparar o contexto de build

Retorne ao diretório do Compose:

```bash
cd "$COMPOSE_DIR"
```

Copie o código-fonte para o contexto esperado pelos Dockerfiles:

```bash
rm -rf base/free5gc

mkdir -p base

cp -a \
  ../Free5gc_Source_code \
  base/free5gc
```

---

## 7.10 Construir as imagens

Use o arquivo de build. O `docker-compose.yaml` tradicional pode
referenciar imagens customizadas que não estão disponíveis publicamente.

```bash
docker compose \
  --env-file .env \
  -f docker-compose-build.yaml \
  build
```

O processo pode levar vários minutos.

---

## 7.11 Subir o core 5G

```bash
docker compose \
  --env-file .env \
  -f docker-compose-build.yaml \
  up -d
```

Confira:

```bash
docker compose \
  --env-file .env \
  -f docker-compose-build.yaml \
  ps
```

Confira os containers:

```bash
docker ps \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
```

Os componentes principais devem incluir:

```text
db
nrf
amf
ausf
udm
udr
nssf
pcf
smf
upf
nef
webui
ueransim
```

---

## 7.12 Verificar logs do core

```bash
docker logs \
  --tail=100 \
  nrf

docker logs \
  --tail=100 \
  amf

docker logs \
  --tail=100 \
  smf

docker logs \
  --tail=100 \
  upf

docker logs \
  --tail=100 \
  nef
```

---

## 7.13 Cadastrar o subscriber

A forma mais simples é utilizar o WebUI.

Abra:

```text
http://IP_DA_VM:5000
```

Credenciais padrão:

```text
Username: admin
Password: free5gc
```

Cadastre um subscriber de laboratório com valores coerentes com o
`uecfg.yaml`.

Exemplo validado:

```text
PLMN:       20893
SUPI/IMSI:  208930000000001
K:          8baf473f2f8fd09487cccbd7097c6862
OPc:        8e27b6af0e692e750f32667a3b14605d
AMF:        8000
DNN:        internet
SST:        1
SD:         112233
```

Esses valores são exclusivamente de laboratório.

O subscriber e o arquivo do UE precisam utilizar exatamente os mesmos:

- IMSI;
- K;
- OP ou OPc;
- AMF;
- MCC;
- MNC;
- SST;
- SD;
- DNN.

---

## 7.14 Verificar a configuração do UE

```bash
grep -nE \
  'supi|key|op|opType|amf|configured-nssai|default-nssai|sessions|gnbSearchList' \
  config/uecfg.yaml
```

Os valores esperados incluem:

```yaml
supi: imsi-208930000000001
mcc: "208"
mnc: "93"
key: 8baf473f2f8fd09487cccbd7097c6862
opType: OPC
op: 8e27b6af0e692e750f32667a3b14605d
amf: "8000"
```

O slice deve conter:

```yaml
sst: 1
sd: 112233
```

A sessão deve utilizar:

```yaml
type: IPv4
apn: internet
```

---

## 7.15 Verificar a configuração do gNB

```bash
grep -nE \
  'mcc|mnc|tac|linkIp|ngapIp|gtpIp|amfConfigs|slices' \
  config/gnbcfg.yaml
```

Campos principais:

```yaml
mcc: "208"
mnc: "93"
tac: 1

linkIp: gnb.free5gc.org
ngapIp: gnb.free5gc.org
gtpIp: gnb.free5gc.org

amfConfigs:
  - address: amf.free5gc.org
    port: 38412
```

---

## 7.16 Iniciar e validar o UERANSIM

Reinicie o container:

```bash
docker restart ueransim
```

Confira o gNB:

```bash
docker logs \
  --tail=100 \
  ueransim
```

O resultado esperado contém:

```text
NG Setup procedure is successful
```

Se o UE não iniciar automaticamente:

```bash
docker exec \
  -d \
  ueransim \
  sh -c \
  'cd /ueransim && ./nr-ue -c ./config/uecfg.yaml >/tmp/nr-ue.log 2>&1'
```

Confira:

```bash
docker exec \
  ueransim \
  tail -n 100 \
  /tmp/nr-ue.log
```

O resultado esperado contém:

```text
Registration accept received
PDU Session establishment is successful
```

---

## 7.17 Verificar a interface do UE

```bash
docker exec \
  ueransim \
  ip address show \
  uesimtun0
```

Resultado esperado:

```text
10.61.0.1/16
```

Teste o bridge do host:

```bash
docker exec \
  ueransim \
  ping \
  -I uesimtun0 \
  -c 3 \
  10.100.200.1
```

A conectividade com a Internet depende da configuração de NAT e
roteamento do host. O teste com `10.100.200.1` é suficiente para o
experimento local de `iperf3`.

---

## 7.18 Iniciar servidor iperf3 no host

No host:

```bash
nohup iperf3 \
  -s \
  -B 10.100.200.1 \
  -p 5201 \
  >/tmp/iperf3-qod-server.log \
  2>&1 &

echo $! \
  >/tmp/iperf3-qod-server.pid
```

Confira:

```bash
ss -lntup \
  | grep 5201
```

---

## 7.19 Executar o baseline sem QoD

```bash
docker exec \
  ueransim \
  iperf3 \
  -c 10.100.200.1 \
  -B 10.61.0.1 \
  -p 5201 \
  -u \
  -b 40M \
  -t 20 \
  -i 1
```

Sem um QER dedicado de 20 Mbit/s, o receptor deve observar valor próximo
da taxa oferecida, desde que não exista outro gargalo.

---

# 8. Instalar o Open QoD Gateway

## 8.1 Clonar e instalar

```bash
cd "$HOME"

git clone \
  https://github.com/riosspedro/open-qod-gateway.git

cd open-qod-gateway

python3 -m venv .venv

source .venv/bin/activate

python -m pip install \
  --upgrade pip

python -m pip install \
  -r requirements.txt

cp .env.example .env
```

---

## 8.2 Descobrir o endereço do NEF

```bash
NEF_IP="$(
  docker inspect \
    -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
    nef
)"

echo "NEF_IP=$NEF_IP"
```

---

## 8.3 Carregar as credenciais do NEF

```bash
COMPOSE_ENV="$HOME/dissertacao_repos/free5gc-qod-enforcement/free5gc-compose-UERANSIM/.env"

set -a
. "$COMPOSE_ENV"
set +a
```

Gere as credenciais do gateway:

```bash
GATEWAY_CLIENT_SECRET="$(openssl rand -hex 32)"
GATEWAY_SIGNING_SECRET="$(openssl rand -hex 32)"
```

Crie o `.env` do gateway:

```bash
cat > .env <<EOF
NEF_BASE_URL=https://${NEF_IP}:8000
NEF_SCS_AS_ID=open-qod-gateway
NEF_CLIENT_ID=${NEF_OAUTH_CLIENT_ID}
NEF_CLIENT_SECRET=${NEF_OAUTH_CLIENT_SECRET}
NEF_VERIFY_TLS=false

GATEWAY_OAUTH_CLIENT_ID=local-client
GATEWAY_OAUTH_CLIENT_SECRET=${GATEWAY_CLIENT_SECRET}
GATEWAY_OAUTH_SIGNING_SECRET=${GATEWAY_SIGNING_SECRET}
GATEWAY_OAUTH_TOKEN_TTL_SECONDS=3600
EOF

chmod 600 .env
```

Guarde o valor de `GATEWAY_CLIENT_SECRET`. Ele será utilizado para
obter o token do gateway.

Nunca envie o `.env` ao GitHub.

---

## 8.4 Executar os testes

```bash
source .venv/bin/activate

python -m compileall \
  app \
  tests

pytest -q
```

---

## 8.5 Iniciar o gateway

```bash
nohup uvicorn \
  app.main:app \
  --host 0.0.0.0 \
  --port 8080 \
  >/tmp/open-qod-gateway.log \
  2>&1 &

echo $! \
  >/tmp/open-qod-gateway.pid

sleep 2
```

Verifique:

```bash
curl -sS \
  http://127.0.0.1:8080/health \
  | jq .
```

Documentação interativa:

```text
http://IP_DA_VM:8080/docs
```

---

# 9. Executar uma sessão QoD

## 9.1 Obter token do gateway

```bash
GATEWAY_TOKEN_JSON="$(
  curl -sS \
    -X POST \
    http://127.0.0.1:8080/oauth2/token \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data 'grant_type=client_credentials' \
    --data 'client_id=local-client' \
    --data "client_secret=${GATEWAY_CLIENT_SECRET}" \
    --data 'scope=qod:read qod:write'
)"

echo "$GATEWAY_TOKEN_JSON" \
  | jq .

GATEWAY_TOKEN="$(
  echo "$GATEWAY_TOKEN_JSON" \
  | jq -r '.access_token'
)"
```

Confirme:

```bash
test \
  -n "$GATEWAY_TOKEN"

echo "TOKEN_OBTIDO"
```

---

## 9.2 Criar a solicitação

```bash
cat > /tmp/gateway-session.json <<'JSON'
{
  "device": {
    "ipv4Address": {
      "publicAddress": "10.61.0.1"
    }
  },
  "applicationServer": {
    "ipv4Address": "10.100.200.1"
  },
  "qosProfile": "QOS_M",
  "duration": 300
}
JSON
```

O perfil `QOS_M` representa:

```text
GBR: 10 Mbit/s
MBR: 20 Mbit/s
```

Crie a sessão:

```bash
curl -sS \
  -X POST \
  http://127.0.0.1:8080/sessions \
  -H "Authorization: Bearer ${GATEWAY_TOKEN}" \
  -H 'Content-Type: application/json' \
  --data-binary @/tmp/gateway-session.json \
  | tee /tmp/gateway-session-response.json \
  | jq .
```

Obtenha o ID:

```bash
SESSION_ID="$(
  jq -r \
    '.sessionId // .id' \
    /tmp/gateway-session-response.json
)"

echo "SESSION_ID=$SESSION_ID"
```

---

## 9.3 Consultar a sessão

```bash
curl -sS \
  -H "Authorization: Bearer ${GATEWAY_TOKEN}" \
  "http://127.0.0.1:8080/sessions/${SESSION_ID}" \
  | jq .
```

---

## 9.4 Inspecionar QER e PDR

Verifique se QoS está habilitado:

```bash
cat /proc/gtp5g/qos
```

Liste os QERs:

```bash
docker exec \
  upf \
  /free5gc/gtp5g-tunnel \
  list qer \
  | jq .
```

Liste os PDRs:

```bash
docker exec \
  upf \
  /free5gc/gtp5g-tunnel \
  list pdr \
  | jq .
```

Também pode ser utilizado:

```bash
./scripts/inspect-qod-rules.sh
```

O QER dedicado deve apresentar aproximadamente:

```text
UL MBR: 20000 kbit/s
DL MBR: 20000 kbit/s
UL GBR: 10000 kbit/s
DL GBR: 10000 kbit/s
```

O PDR de uplink deve:

- conter F-TEID;
- identificar o UE `10.61.0.1`;
- referenciar o QER dedicado;
- corresponder ao tráfego medido.

---

## 9.5 Testar o enforcement

```bash
docker exec \
  ueransim \
  iperf3 \
  -c 10.100.200.1 \
  -B 10.61.0.1 \
  -p 5201 \
  -u \
  -b 40M \
  -t 20 \
  -i 1
```

Resultado esperado:

```text
Sender:   aproximadamente 40 Mbit/s
Receiver: aproximadamente 20 Mbit/s
```

A diferença ocorre porque o cliente tenta transmitir 40 Mbit/s, mas o
QER limita o fluxo a aproximadamente 20 Mbit/s.

---

## 9.6 Atualizar o perfil

O perfil `QOS_HIGH` representa:

```text
GBR: 12 Mbit/s
MBR: 24 Mbit/s
```

Atualize:

```bash
curl -sS \
  -X PATCH \
  -H "Authorization: Bearer ${GATEWAY_TOKEN}" \
  -H 'Content-Type: application/json' \
  --data '{"qosProfile":"QOS_HIGH"}' \
  "http://127.0.0.1:8080/sessions/${SESSION_ID}" \
  | jq .
```

Confira o novo QER:

```bash
docker exec \
  upf \
  /free5gc/gtp5g-tunnel \
  list qer \
  | jq .
```

---

## 9.7 Excluir a sessão

```bash
curl -sS \
  -o /tmp/gateway-delete.body \
  -w 'HTTP_CODE=%{http_code}\n' \
  -X DELETE \
  -H "Authorization: Bearer ${GATEWAY_TOKEN}" \
  "http://127.0.0.1:8080/sessions/${SESSION_ID}"
```

O código esperado é:

```text
HTTP_CODE=204
```

Aguarde a propagação:

```bash
sleep 3
```

Confira os QERs:

```bash
docker exec \
  upf \
  /free5gc/gtp5g-tunnel \
  list qer \
  | jq .
```

Confira os PDRs:

```bash
docker exec \
  upf \
  /free5gc/gtp5g-tunnel \
  list pdr \
  | jq .
```

Após o `DELETE`, o QER e o PDR dedicados devem ser removidos, restando
somente as regras default da PDU Session.

---

# 10. Validação dos logs

## NEF

```bash
docker logs \
  --since=10m \
  nef \
  2>&1 \
  | grep -Ei \
  'oauth|token|session|subscription|qos'
```

## PCF

```bash
docker logs \
  --since=10m \
  pcf \
  2>&1 \
  | grep -Ei \
  'app-session|pcc|qos|policy'
```

## SMF

```bash
docker logs \
  --since=10m \
  smf \
  2>&1 \
  | grep -Ei \
  'PccRule|QosData|QER|PFCP|Remove'
```

## UPF

```bash
docker logs \
  --since=10m \
  upf \
  2>&1 \
  | grep -Ei \
  'PFCP|QER|PDR|Session Modification'
```

---

# 11. Troubleshooting

## 11.1 `PDU_SESSION_NOT_AVAILABLE`

Causa provável:

- UE não registrado;
- subscriber inexistente;
- parâmetros do UE diferentes do WebUI;
- PDU Session ainda não estabelecida.

Verifique:

```bash
docker logs \
  --tail=200 \
  amf

docker logs \
  --tail=200 \
  smf

docker exec \
  ueransim \
  ip address show \
  uesimtun0
```

---

## 11.2 Erro de autenticação do subscriber

Mensagem típica:

```text
Nausf_UEAU Authenticate Request Error: 404
```

Isso indica que o subscriber não foi encontrado no UDR ou que os dados
não correspondem ao UE.

Confira:

- IMSI;
- K;
- OPc;
- AMF;
- MCC;
- MNC.

---

## 11.3 NEF retorna erro de configuração OAuth

Confira:

```bash
docker inspect \
  nef \
  | jq '.[0].Config.Env'
```

As três variáveis devem existir:

```text
NEF_OAUTH_CLIENT_ID
NEF_OAUTH_CLIENT_SECRET
NEF_OAUTH_JWT_SIGNING_KEY
```

---

## 11.4 Token emitido, mas rejeitado

Confirme que o container foi construído a partir desta snapshot.

O emissor e o validador precisam utilizar a mesma:

```text
NEF_OAUTH_JWT_SIGNING_KEY
```

---

## 11.5 QER com MBR igual a zero

Possível causa:

```text
medType: DATA
5QI: 9
```

Confira os logs do PCF e SMF.

Uma política criada não é suficiente. O `QosData` precisa conter valores
efetivos de banda.

---

## 11.6 QER correto, mas tráfego não limitado

Verifique:

```bash
cat /proc/gtp5g/qos
```

O resultado deve ser:

```text
1
```

Depois confira se o PDR utilizado pelo tráfego referencia o QER
dedicado.

---

## 11.7 PDR criado no sentido errado

Compare:

- origem do tráfego;
- destino do tráfego;
- interface de origem do PDR;
- F-TEID;
- SDF Filter;
- QER IDs associados.

O tráfego de teste deste projeto é:

```text
UE 10.61.0.1 -> host 10.100.200.1
```

Portanto, o PDR necessário para o teste deve corresponder ao uplink.

---

## 11.8 QER permanece depois do DELETE

Confirme que o SMF utilizado contém a correção de limpeza.

Verifique:

```bash
docker exec \
  upf \
  /free5gc/gtp5g-tunnel \
  list qer \
  | jq .

docker exec \
  upf \
  /free5gc/gtp5g-tunnel \
  list pdr \
  | jq .
```

---

## 11.9 Erro TLS

No ambiente de laboratório, verifique:

```text
NEF_VERIFY_TLS=false
```

e:

```yaml
verifyClient: false
```

Para uso fora do laboratório, gere certificados com SAN correto, ative
a verificação e configure autenticação mTLS.

---

# 12. Encerramento do ambiente

Pare o gateway:

```bash
GATEWAY_PID="$(
  cat /tmp/open-qod-gateway.pid \
  2>/dev/null
)"

if [ -n "$GATEWAY_PID" ]; then
  kill "$GATEWAY_PID"
fi
```

Pare os containers:

```bash
cd \
  "$HOME/dissertacao_repos/free5gc-qod-enforcement/free5gc-compose-UERANSIM"

docker compose \
  --env-file .env \
  -f docker-compose-build.yaml \
  down
```

---

# 13. Limitações metodológicas

## 13.1 Enforcement no UPF

O resultado demonstra enforcement no UPF/gtp5g.

Não demonstra isoladamente:

- reserva no enlace rádio;
- controle de espectro;
- scheduler do gNB;
- prioridade sob congestionamento real da RAN.

---

## 13.2 GBR

O QER contém valores de GBR.

Comprovar uma garantia de GBR exige:

- múltiplos fluxos concorrentes;
- congestionamento controlado;
- análise estatística;
- comparação entre fluxos;
- idealmente uma RAN física ou um simulador de rádio mais completo.

---

## 13.3 UERANSIM

O UERANSIM é adequado para:

- registro;
- autenticação;
- PDU Session;
- NAS;
- NGAP;
- tráfego IP;
- integração do core.

Ele não substitui um ensaio de rádio físico.

---

## 13.4 IEAM

O IEAM completo não foi reproduzido.

O Open QoD Gateway implementa somente a função de tradução e controle
necessária ao experimento.

---

## 13.5 CAMARA

A API do gateway é inspirada no modelo CAMARA QoD.

Não é declarada conformidade integral ou certificação oficial CAMARA.

---

## 13.6 Nephio

Nephio não foi utilizado.

Sua ausência não impede o teste do caminho de runtime NEF-PCF-SMF-UPF.

---

## 13.7 Classificação do fluxo

O modo de compatibilidade utiliza um filtro amplo necessário para o
comportamento observado no testbed.

Ainda é necessário implementar e validar uma tradução rigorosa de:

```text
device + application server + ports + protocol + direction
```

para filtros PFCP específicos e consistentes com a semântica CAMARA.

---

# 14. Segurança

Não devem ser adicionados ao repositório:

- `.env`;
- chaves privadas;
- certificados privados;
- access tokens;
- JWTs;
- client secrets;
- dumps do MongoDB;
- bancos SQLite de execução;
- logs com `Authorization`;
- binários compilados.

Antes de cada publicação, execute uma nova varredura.

---

# 15. Evidências

As evidências do experimento estão em:

```text
docs/evidence/qod-uplink-20mbps/
```

Elas incluem:

- payload utilizado;
- resposta do NEF;
- regras antes da sessão;
- regras durante a sessão;
- regras após a exclusão;
- logs;
- resultados do iperf3;
- hashes SHA-256.

---

# 16. Reprodutibilidade

A snapshot foi criada a partir de uma revisão local que continha:

```text
Correção do SMF:                 5a8c9dc
Documentação do enforcement:    d8f8679
Correção reproduzível do NEF:    30af2c3
```

Esses identificadores pertencem à árvore de preparação anterior.

O histórico antigo não foi importado porque continha:

- certificados privados;
- chaves privadas;
- credenciais fixas;
- binários;
- artefatos de laboratório.

A snapshot possui histórico Git novo.

---

# 17. Origem e atribuição

Este trabalho deriva de:

- componentes do free5GC;
- código e documentação do projeto Infosys 5G Quality On Demand;
- UERANSIM;
- gtp5g;
- bibliotecas open source utilizadas pelos projetos.

As licenças e atribuições originais foram preservadas nos respectivos
diretórios.

Este repositório documenta as correções, limitações e evidências do
ambiente reproduzido. Ele não representa uma versão oficial da Infosys,
do free5GC, da CAMARA ou de qualquer operadora.
