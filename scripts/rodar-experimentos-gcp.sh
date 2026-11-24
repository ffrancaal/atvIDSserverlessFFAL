#!/usr/bin/env bash
# Passos 3, 4 e 5 da atividade usando o Google Cloud Functions Framework (sem Docker).
# Grava tudo em evidencias/gcp/.  Uso: ./scripts/rodar-experimentos-gcp.sh
set -uo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
EVID="$RAIZ/evidencias/gcp"
FF="$(command -v functions-framework || echo "$RAIZ/.venv/bin/functions-framework")"
PY="$RAIZ/.venv/bin/python"; [ -x "$PY" ] || PY=python3
PORTA=8080
URL="http://127.0.0.1:$PORTA"
EVENTO="$RAIZ/rota-vital-guias/events/pedido.json"
mkdir -p "$EVID"
cd "$RAIZ"

agora() { "$PY" -c 'import time; print(time.time())'; }
dif()   { "$PY" -c "print(f'{($2-$1)*1000:.0f} ms')"; }
titulo() { printf '\n===== %s =====\n' "$*"; }
cmd() { printf '$ %s\n' "$*"; }

porta_aberta() { "$PY" -c "import socket,sys; s=socket.socket(); s.settimeout(0.2); sys.exit(s.connect_ex(('127.0.0.1',$PORTA)))"; }

subir() {  # $1 = target, $2 = signature-type, $3 = arquivo de log ; variáveis de ambiente extras antes
  cmd "functions-framework --source funcao-gcp/main.py --target $1 --signature-type $2 --port $PORTA"
  T_INICIO=$(agora)
  "$FF" --source funcao-gcp/main.py --target "$1" --signature-type "$2" --port "$PORTA" >"$3" 2>&1 &
  FF_PID=$!
  until porta_aberta; do sleep 0.05; done
  T_PRONTO=$(agora)
  echo ">> instância subiu (Init: processo + runtime + import da função) em $(dif "$T_INICIO" "$T_PRONTO")"
}

parar() { kill "$FF_PID" 2>/dev/null; wait "$FF_PID" 2>/dev/null; while porta_aberta; do sleep 0.1; done; }

http() {  # $1 = corpo JSON
  cmd "curl -X POST $URL/guias -H 'Content-Type: application/json' -d '$1'"
  curl -s -D - -o /tmp/.ff_body -w '[HTTP %{http_code} em %{time_total}s]\n' -X POST "$URL/guias" \
    -H "Content-Type: application/json" -d "$1" | grep -E '^\[HTTP|X-Instancia' | tr -d '\r'
  cat /tmp/.ff_body; echo
}

evento() {
  cmd "curl -X POST $URL -H 'ce-type: rotavital.requisicao.criada' ... -d @rota-vital-guias/events/pedido.json"
  curl -s -w '[HTTP %{http_code} em %{time_total}s]\n' -X POST "$URL" \
    -H "Content-Type: application/json" -H "ce-specversion: 1.0" -H "ce-id: $RANDOM" \
    -H "ce-type: rotavital.requisicao.criada" -H "ce-source: //rota-vital/requisicoes" \
    --data-binary @"$EVENTO"
}

# ------------------------------------------------------------------ Ambiente
{
  titulo "Ambiente"
  cmd "python --version"; "$PY" --version
  cmd "pip show functions-framework"; "$PY" -m pip show functions-framework 2>/dev/null | grep -E '^(Name|Version)' 
  cmd "sam --version"; "$RAIZ/.venv/bin/sam" --version
  cmd "docker --version"; docker --version 2>/dev/null || echo "docker não instalado nesta máquina -> sam local invoke/start-api não executam; usei o Functions Framework"
  titulo "Testes unitários do handler"
  cmd "python -m pytest -q rota-vital-guias/tests/unit"
  (cd rota-vital-guias && "$PY" -m pytest -q tests/unit 2>&1 | tail -2)
} 2>&1 | tee "$EVID/01-ambiente.txt"

# ------------------------------------------------------------------ Passo 3
LOG="$EVID/03-evento-servidor.txt"
{
  titulo "Passo 3 - invocação com evento (CloudEvent com o events/pedido.json do SAM)"
  subir guias_evento cloudevent "$LOG"
  titulo "Invocação 1 (cold start: instância recém-criada)"
  evento
  echo ">> tempo total da invocação 1 (subir instância + executar): $(dif "$T_INICIO" "$(agora)")"
  titulo "Invocação 2 (instância já existente)"
  T2=$(agora); evento
  echo ">> tempo total da invocação 2: $(dif "$T2" "$(agora)")"
  parar
  titulo "Log da função (INIT/REPORT/RESULTADO)"
  grep -E '^(INIT|REPORT|RESULTADO)' "$LOG"
} 2>&1 | tee "$EVID/03-evento.txt"

# ------------------------------------------------------------------ Passo 4a
{
  titulo "Passo 4a - HTTP SEM reaproveitamento (uma instância nova por chamada, como sam local start-api padrão)"
  for i in 1 2 3; do
    titulo "Chamada $i"
    subir guias http "$EVID/04a-servidor-$i.txt"
    http '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'
    parar
  done
} 2>&1 | tee "$EVID/04a-http-sem-reaproveitamento.txt"

# ------------------------------------------------------------------ Passo 4b
LOG="$EVID/04b-servidor.txt"
{
  titulo "Passo 4b - HTTP COM reaproveitamento (mesma instância, como --warm-containers LAZY)"
  subir guias http "$LOG"
  for i in 1 2 3; do titulo "Chamada $i"; http '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'; done
  titulo "Requisição sem requisicaoId (esperado 400)"
  http '{"hospital":"H-Caruaru"}'
  parar
  titulo "Instância reiniciada: o estado global some"
  subir guias http "$LOG.reinicio"
  http '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'
  parar
  titulo "Log da função"
  cat "$LOG" "$LOG.reinicio" | grep -E '^(INIT|REPORT)'
} 2>&1 | tee "$EVID/04b-http-com-reaproveitamento.txt"
rm -f "$LOG.reinicio"

# ------------------------------------------------------------------ Passo 5
export THREADED_TIMEOUT_ENABLED=true GUNICORN_LOG_LEVEL=info
LOG="$EVID/05a-servidor.txt"
{
  titulo "Passo 5a - demorar=true com limite de 3 s (CLOUD_RUN_TIMEOUT_SECONDS=3)"
  export CLOUD_RUN_TIMEOUT_SECONDS=3
  subir guias http "$LOG"
  http '{"requisicaoId":"R-003","demorar":true}'
  parar
  titulo "Erro registrado no log da função"
  grep -E 'RequestTimeoutException|ERROR|time.sleep' "$LOG"
} 2>&1 | tee "$EVID/05a-timeout-3s.txt"

LOG="$EVID/05b-servidor.txt"
{
  titulo "Passo 5b - limite aumentado para 10 s (CLOUD_RUN_TIMEOUT_SECONDS=10)"
  export CLOUD_RUN_TIMEOUT_SECONDS=10
  subir guias http "$LOG"
  http '{"requisicaoId":"R-003","demorar":true}'
  parar
  grep -E '^(INIT|REPORT)' "$LOG"
} 2>&1 | tee "$EVID/05b-timeout-10s.txt"

rm -f /tmp/.ff_body
echo; echo "Evidências gravadas em $EVID"
