# Atividade individual 1 · Serverless — Rota Vital

Infraestrutura de Software · ADS · CESAR School · 2026.2
Aluno: Felipe Franca Alves de Lima

Função serverless que gera a **guia de transporte** de uma requisição do Rota Vital, acionada por
**evento** e por **HTTP** (`POST /guias`), rodando no meu computador.

## Caminho escolhido

**Alternativa equivalente: Google Cloud Functions Framework (Python), rodando local.**

Comecei pelo Caminho A (AWS SAM CLI): a SAM CLI está instalada (1.155.2) e o projeto foi criado com
`sam init` em [`rota-vital-guias/`](rota-vital-guias/). Porém o `sam local invoke` / `start-api`
precisa de Docker para criar o container do Lambda, e **não tenho Docker instalado nesta máquina**
(e não consigo instalar agora). O enunciado aceita o Functions Framework do Google Cloud como
alternativa equivalente, e ele roda sem Docker e sem conta em provedor — então foi por ele que
executei os Passos 3, 4 e 5.

O ponto importante: **o código da função é o mesmo do enunciado** (`rota-vital-guias/hello_world/app.py`,
o handler do Lambda). O arquivo [`funcao-gcp/main.py`](funcao-gcp/main.py) é só um adaptador: recebe
a requisição HTTP ou o CloudEvent, monta o evento no formato do API Gateway, chama
`lambda_handler(event, context)` e devolve a resposta. Assim que eu tiver Docker, o mesmo projeto roda
no SAM com [`scripts/rodar-experimentos.sh`](scripts/rodar-experimentos.sh) (já pronto).

| Ferramenta | Versão usada |
|---|---|
| Google Cloud Functions Framework (Python) | 3.10.2 (servidor gunicorn 23) |
| AWS SAM CLI | 1.155.2 (projeto criado e template validado; execução local depende de Docker) |
| Python | 3.9.6 (o do macOS; o código da função não usa nada específico do 3.12) |
| Máquina | macOS, Apple Silicon (arm64) |

### Como cada passo do Caminho A foi mapeado

| Enunciado (SAM) | O que usei (Functions Framework) |
|---|---|
| `sam local invoke -e events/pedido.json` | função `guias_evento` com `--signature-type cloudevent`, recebendo um CloudEvent cujo `data` é **o mesmo** `events/pedido.json` gerado pelo `sam local generate-event` |
| `sam local start-api` + `curl POST /guias` | função `guias` com `--signature-type http`, `curl POST http://127.0.0.1:8080/guias` |
| `start-api` sem warm containers (um container novo por chamada) | uma instância nova (processo novo) por chamada |
| `start-api --warm-containers LAZY` | uma única instância que atende todas as chamadas |
| `Timeout: 3` / `Timeout: 10` em `Globals` | `CLOUD_RUN_TIMEOUT_SECONDS=3` / `=10` (limite de execução do Functions Framework / Cloud Run) |

## Estrutura

```
rota-vital-guias/              projeto do `sam init` (Hello World, Python 3.12, zip)
├── template.yaml              API em POST /guias, Timeout em Globals
├── samconfig.toml
├── hello_world/app.py         handler da guia de transporte (código do enunciado)
├── events/pedido.json         evento API Gateway gerado com `sam local generate-event`
├── events/pedido-demorado.json
└── tests/unit/                testes do handler (pytest)
funcao-gcp/main.py             adaptador Functions Framework -> lambda_handler
scripts/rodar-experimentos-gcp.sh  roda os Passos 3–5 com o Functions Framework (usado)
scripts/rodar-experimentos.sh      roda os Passos 3–5 com o SAM (precisa de Docker)
scripts/gerar-prints.py        transforma as saídas em imagens PNG
evidencias/*.png               prints das saídas de cada passo
evidencias/gcp/*.txt           saídas completas (cliente e log da função)
```

### Ajustes em relação ao template gerado / ao enunciado

1. `template.yaml`: caminho `/hello` → `/guias`, método `get` → `post`; `Architectures: arm64`
   (Mac Apple Silicon, evita emulação x86 no Docker).
2. `hello_world/app.py`: código do enunciado + decodificação do body quando o evento vem com
   `isBase64Encoded: true`. Nesta versão do SAM, `sam local generate-event ... --body` grava o body em
   base64, e o código original quebrava com `JSONDecodeError` ao ler `events/pedido.json`.
3. `samconfig.toml`: o `sam init` gerou `warm_containers = "EAGER"` como padrão do `start-api`. Tirei,
   senão a rodada "sem reaproveitamento" do Passo 4 no SAM já viria com container quente.
4. `Timeout` em `Globals` ficou em 10 (estado final pedido no Passo 5).

## Como rodar

```bash
# 1. Ambiente (na raiz do repositório)
python3 -m venv .venv
.venv/bin/pip install functions-framework==3.10.2 pytest pillow aws-sam-cli
```

```bash
# 2. Todos os passos de uma vez (gera evidencias/gcp/*.txt)
./scripts/rodar-experimentos-gcp.sh
```

```bash
# 3. Prints PNG a partir das saídas
.venv/bin/python scripts/gerar-prints.py
```

### Passo a passo manual

```bash
source .venv/bin/activate

# Passo 3 — invocação com evento (terminal 1)
functions-framework --source funcao-gcp/main.py --target guias_evento --signature-type cloudevent --port 8080
# terminal 2 (duas vezes):
curl -X POST http://127.0.0.1:8080 -H "Content-Type: application/json" \
  -H "ce-specversion: 1.0" -H "ce-id: 1" -H "ce-type: rotavital.requisicao.criada" \
  -H "ce-source: //rota-vital/requisicoes" --data-binary @rota-vital-guias/events/pedido.json
# a guia gerada aparece no log do terminal 1 (linhas REPORT e RESULTADO)

# Passo 4 — HTTP (terminal 1)
functions-framework --source funcao-gcp/main.py --target guias --port 8080
# terminal 2, três vezes:
curl -X POST http://127.0.0.1:8080/guias -H "Content-Type: application/json" \
  -d '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'
# para simular "sem reaproveitamento": Ctrl+C e subir de novo antes de cada curl

# Passo 5 — limite de tempo
CLOUD_RUN_TIMEOUT_SECONDS=3 THREADED_TIMEOUT_ENABLED=true \
  functions-framework --source funcao-gcp/main.py --target guias --port 8080
curl -X POST http://127.0.0.1:8080/guias -H "Content-Type: application/json" \
  -d '{"requisicaoId":"R-003","demorar":true}'
# depois repetir com CLOUD_RUN_TIMEOUT_SECONDS=10

# Testes unitários do handler
cd rota-vital-guias && python -m pytest -q tests/unit
```

### Com Docker (Caminho A original)

```bash
export PATH="$PWD/.venv/bin:$PATH"
./scripts/rodar-experimentos.sh
```

## Resultados observados

### Passo 3 — invocação com evento ([print](evidencias/03-evento.png), [saída](evidencias/gcp/03-evento.txt))

| Invocação | Tempo total | Duração do handler | `invocacaoNesteAmbiente` |
|---|---|---|---|
| 1ª (instância recém-criada) | **233 ms** (191 ms só para a instância subir) | 0,06 ms | 1 |
| 2ª (instância já existente) | **28 ms** | 0,02 ms | 2 |

Resposta da função: `201` com `{"guia": "G-R-001", "hospital": "H-Recife", "bolsas": ["O-NEG-0142"], ...}`.

### Passo 4 — HTTP e reaproveitamento do ambiente ([sem](evidencias/04a-http-sem-reaproveitamento.png), [com](evidencias/04b-http-com-reaproveitamento.png))

| Chamada | Sem reaproveitamento (instância nova a cada chamada) | Com reaproveitamento (mesma instância) |
|---|---|---|
| 1ª | `invocacaoNesteAmbiente: 1` · init 198 ms | `invocacaoNesteAmbiente: 1` · 2,6 ms |
| 2ª | `invocacaoNesteAmbiente: 1` · init 109 ms | `invocacaoNesteAmbiente: 2` · 0,9 ms |
| 3ª | `invocacaoNesteAmbiente: 1` · init 119 ms | `invocacaoNesteAmbiente: 3` · 0,8 ms |

Sem reaproveitamento cada chamada veio de um processo diferente (PIDs diferentes no cabeçalho
`X-Instancia-Pid`); com reaproveitamento o PID foi sempre o mesmo. Depois de reiniciar a instância, a
chamada seguinte voltou a mostrar `invocacaoNesteAmbiente: 1`. Um pedido sem `requisicaoId`
devolveu `400 {"erro": "requisicaoId obrigatório"}`.

### Passo 5 — limite de tempo ([3 s](evidencias/05a-timeout-3s.png), [10 s](evidencias/05b-timeout-10s.png))

- **Limite 3 s:** `HTTP 500` e no log `functions_framework.exceptions.RequestTimeoutException`
  apontando para o `time.sleep(5)`. A guia não foi gerada.
- **Limite 10 s:** `HTTP 201` em 5,01 s, `REPORT Duration: 5000.69 ms`, guia `G-R-003` gerada.

Diferença que notei em relação ao Lambda: no Functions Framework local a exceção de timeout só é
lançada quando o `sleep` devolve o controle, então o 500 chegou em ~5 s e não exatamente em 3 s. No
Lambda o ambiente é interrompido no limite (3 s) e a resposta é `Task timed out after 3.00 seconds`.

## Respostas

> Rascunho a partir dos meus resultados — revisar com as minhas palavras antes da entrega.

**1. Por que a primeira invocação demorou mais que a segunda? O que acontece na fase de Init?**

Na primeira chamada não existia nenhum ambiente pronto, então a plataforma teve que criar um: subir
o processo, carregar o runtime do Python, importar o meu código e rodar tudo que está fora do handler
(no meu caso o `contador = 0` e os imports). Isso é a fase de **Init**, o cold start. Só depois disso o
handler roda. Na segunda chamada o ambiente já estava de pé, então só o handler executou. Nos meus
números: 233 ms na primeira (191 ms só para a instância ficar pronta) contra 28 ms na segunda, sendo
que o handler em si leva menos de 0,1 ms nas duas. Ou seja, quase todo o tempo da primeira é Init. No
Lambda de verdade isso aparece como `Init Duration` no log do CloudWatch, e no SAM local o tempo é
ainda maior porque inclui criar o container Docker.

**2. O que o campo `invocacaoNesteAmbiente` mostrou com e sem `--warm-containers`? O que isso diz sobre
guardar estado numa variável global da função?**

Sem reaproveitamento, deu `1, 1, 1`: cada chamada caiu num ambiente novo, e o `contador` começava do
zero. Com reaproveitamento (equivalente ao `--warm-containers LAZY`), deu `1, 2, 3`, porque as três
chamadas usaram o mesmo processo e a variável global sobreviveu entre elas. Quando reiniciei a
instância, voltou para 1. Conclusão: variável global **não é lugar de guardar estado**. Ela só
"funciona" por acaso, quando a plataforma reaproveita o ambiente, e isso ninguém garante — o ambiente
pode ser destruído a qualquer momento, e com várias chamadas simultâneas existem vários ambientes,
cada um com seu próprio contador. Serve para cache (ex.: conexão com banco criada no Init), mas dado
que importa tem que ir para fora da função (DynamoDB, S3, banco, Redis).

**3. O que aconteceu com `demorar = true`? Qual é o tempo máximo de uma execução no Lambda, e o que
fazer com um trabalho mais longo?**

Com limite de 3 s a função foi interrompida por timeout (`RequestTimeoutException`, HTTP 500) e a guia
não foi gerada; ao subir o limite para 10 s, a mesma chamada terminou em ~5 s com 201. No Lambda o
máximo configurável é **900 segundos (15 minutos)**. Trabalho mais longo não deve ficar numa execução
só: dá para quebrar em etapas menores encadeadas por uma fila (SQS) ou orquestradas pelo **Step
Functions**, ou então rodar fora do Lambda, em container (ECS/Fargate) ou AWS Batch. Também vale lembrar
que, atrás do API Gateway, a resposta HTTP tem limite de 29 s, então chamada síncrona demorada deveria
virar assíncrona (responde 202 e processa depois).

**4. Quanto custa um milhão de execuções desta função com 128 MB e 100 ms (us-east-1)?**

Preços da aula: US$ 0,20 por milhão de requisições e US$ 0,0000166667 por GB-s.

```
Memória:            128 MB = 128 / 1024 GB = 0,125 GB
Duração:            100 ms = 0,1 s
GB-s por execução:  0,125 GB × 0,1 s = 0,0125 GB-s
GB-s no total:      0,0125 × 1.000.000 = 12.500 GB-s

Computação:   12.500 GB-s × US$ 0,0000166667 = US$ 0,2083
Requisições:  1.000.000 × (US$ 0,20 / 1.000.000) = US$ 0,20
Total:        US$ 0,2083 + US$ 0,20 = US$ 0,4083 ≈ US$ 0,41
```

Um milhão de guias custa cerca de **US$ 0,41**, sem considerar a faixa gratuita (com ela — 1 milhão de
requisições e 400 mil GB-s por mês — esse volume sairia de graça). Metade do custo é a cobrança por
requisição: numa função curta e pequena assim, a computação pesa pouco.

**5. Em que parte do Rota Vital uma função assim faria sentido, e em qual não faria?**

Faz sentido nas partes **orientadas a evento, curtas e com tráfego irregular**: gerar a guia de
transporte quando uma requisição de bolsa é aprovada (exatamente esta função), notificar o hospital e
o motorista, validar e registrar uma requisição que chega por API, ou gerar relatórios/PDFs sob
demanda. São tarefas de milissegundos a poucos segundos, que podem ficar paradas por horas e de
repente ter pico (um acidente com várias vítimas), e no serverless só pago pelo que rodar.

Não faz sentido no que é **contínuo, longo ou que precisa de estado em memória/conexão aberta**:
rastreamento em tempo real da viatura com conexão persistente (WebSocket aberto o tempo todo),
otimização de rotas pesada que pode passar dos 15 minutos, ou o controle de estoque de bolsas se a
ideia fosse manter esse estado dentro da função — como o experimento mostrou, o estado some quando o
ambiente muda. Também é ponto de atenção em fluxos de emergência onde um cold start extra pode pesar;
aí seria preciso concorrência provisionada ou um serviço sempre ligado.

## Uso de IA

Usei o Claude Code (Anthropic) como apoio para montar os scripts de execução dos experimentos e
organizar o README; validei rodando todos os passos na minha máquina e conferindo as saídas em
`evidencias/`. Declaração conforme PO-CESAR-021.

## Vídeo

Link do vídeo (até 3 min):
