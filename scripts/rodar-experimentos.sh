#!/usr/bin/env bash
# Roda os Passos 3, 4 e 5 da atividade e grava as saídas em evidencias/.
# Pré-requisitos: Docker rodando e SAM CLI (no PATH ou em .venv/bin/sam).
set -uo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$RAIZ/rota-vital-guias"
EVID="$RAIZ/evidencias"
SAM="$(command -v sam || echo "$RAIZ/.venv/bin/sam")"
export SAM_CLI_TELEMETRY=0
mkdir -p "$EVID"
cd "$PROJ"

titulo() { printf '\n===== %s =====\n' "$*"; }
cmd() { printf '$ %s\n' "$*"; }

set_timeout() { sed -i.bak -E "s/^    Timeout: [0-9]+/    Timeout: $1/" template.yaml && rm -f template.yaml.bak; }

esperar_api() {
  for _ in $(seq 1 60); do
    curl -s -o /dev/null http://127.0.0.1:3000/ && return 0
    sleep 1
  done
  echo "start-api não respondeu" >&2; return 1
}

chamar() {  # $1 = corpo JSON
  cmd "curl -X POST http://127.0.0.1:3000/guias -H 'Content-Type: application/json' -d '$1'"
  curl -s -w '\n[HTTP %{http_code} em %{time_total}s]\n' -X POST http://127.0.0.1:3000/guias \
    -H "Content-Type: application/json" -d "$1"
}

subir_api() {  # $@ = flags extras; log em $EVID/$LOGAPI
  "$SAM" local start-api "$@" >"$EVID/$LOGAPI" 2>&1 &
  API_PID=$!
  esperar_api
}

parar_api() { kill "$API_PID" 2>/dev/null; wait "$API_PID" 2>/dev/null; sleep 2; }

# ---------------------------------------------------------------- Passo 1/2
{
  titulo "Passo 1 - ferramentas"
  cmd "sam --version";    "$SAM" --version
  cmd "docker --version"; docker --version
  cmd "python3 --version"; python3 --version
  titulo "Passo 2 - template validado"
  cmd "sam validate --lint"; "$SAM" validate --lint
} 2>&1 | tee "$EVID/01-ambiente.txt"

set_timeout 3

# ---------------------------------------------------------------- Passo 3
{
  titulo "Passo 3 - sam build"
  cmd "sam build"; "$SAM" build
  for i in 1 2; do
    titulo "Passo 3 - invocação $i com evento"
    cmd "time sam local invoke -e events/pedido.json"
    inicio=$(python3 -c 'import time;print(time.time())')
    "$SAM" local invoke -e events/pedido.json
    fim=$(python3 -c 'import time;print(time.time())')
    python3 -c "print(f'>> tempo total da invocação $i: {$fim-$inicio:.2f} s')"
  done
} 2>&1 | tee "$EVID/03-invoke-evento.txt"

# ---------------------------------------------------------------- Passo 4
LOGAPI=04a-start-api-servidor.txt
subir_api
{
  titulo "Passo 4a - sam local start-api (sem warm containers)"
  for _ in 1 2 3; do chamar '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'; done
} 2>&1 | tee "$EVID/04a-http-sem-warm.txt"
parar_api

LOGAPI=04b-start-api-lazy-servidor.txt
subir_api --warm-containers LAZY
{
  titulo "Passo 4b - sam local start-api --warm-containers LAZY"
  for _ in 1 2 3; do chamar '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'; done
  titulo "Passo 4b - requisição sem requisicaoId (esperado 400)"
  chamar '{"hospital":"H-Caruaru"}'
} 2>&1 | tee "$EVID/04b-http-warm-lazy.txt"
parar_api

# ---------------------------------------------------------------- Passo 5
LOGAPI=05a-start-api-timeout3-servidor.txt
subir_api
{
  titulo "Passo 5a - demorar=true com Timeout: 3 (HTTP)"
  grep -n 'Timeout' template.yaml
  chamar '{"requisicaoId":"R-003","demorar":true}'
  titulo "Passo 5a - demorar=true com Timeout: 3 (invoke com evento)"
  cmd "sam local invoke -e events/pedido-demorado.json"
  "$SAM" local invoke -e events/pedido-demorado.json
} 2>&1 | tee "$EVID/05a-timeout-3s.txt"
parar_api
{ titulo "Log do servidor (trecho do timeout)"; grep -i -E 'timed out|timeout|error|502' "$EVID/$LOGAPI"; } \
  2>&1 | tee -a "$EVID/05a-timeout-3s.txt"

set_timeout 10
{
  titulo "Passo 5b - Timeout aumentado para 10 + sam build"
  grep -n 'Timeout' template.yaml
  cmd "sam build"; "$SAM" build
} 2>&1 | tee "$EVID/05b-timeout-10s.txt"

LOGAPI=05b-start-api-timeout10-servidor.txt
subir_api
{
  titulo "Passo 5b - demorar=true com Timeout: 10 (HTTP)"
  chamar '{"requisicaoId":"R-003","demorar":true}'
} 2>&1 | tee -a "$EVID/05b-timeout-10s.txt"
parar_api

echo; echo "Evidências gravadas em $EVID"
