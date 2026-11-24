"""Adaptador do Google Cloud Functions Framework para o handler do Lambda.

A regra de negócio é a MESMA do projeto SAM (rota-vital-guias/hello_world/app.py):
este arquivo só traduz a requisição HTTP / o CloudEvent para o formato de evento
do API Gateway e devolve a resposta. Também imprime linhas parecidas com as do
Lambda (INIT / REPORT) para enxergar o cold start.
"""
import json
import os
import sys
import time

_t0 = time.perf_counter()

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "rota-vital-guias", "hello_world"))
import app  # noqa: E402  (handler do Lambda, sem alterações)
import functions_framework  # noqa: E402

INIT_MS = (time.perf_counter() - _t0) * 1000
_primeira = True
print(f"INIT pid={os.getpid()} módulo da função carregado em {INIT_MS:.1f} ms", flush=True)


def _executar(event):
    global _primeira
    inicio = time.perf_counter()
    resp = app.lambda_handler(event, None)
    dur = (time.perf_counter() - inicio) * 1000
    extra = f" Init Duration: {INIT_MS:.1f} ms" if _primeira else ""
    _primeira = False
    print(f"REPORT pid={os.getpid()} Duration: {dur:.2f} ms{extra} status={resp['statusCode']}", flush=True)
    return resp


@functions_framework.http
def guias(request):
    """Gatilho HTTP: POST /guias com o pedido em JSON no corpo."""
    event = {"httpMethod": request.method, "path": request.path,
             "headers": dict(request.headers), "body": request.get_data(as_text=True)}
    resp = _executar(event)
    return resp["body"], resp["statusCode"], {"Content-Type": "application/json",
                                              "X-Instancia-Pid": str(os.getpid())}


@functions_framework.cloud_event
def guias_evento(cloud_event):
    """Gatilho por evento: o `data` do CloudEvent é o evento do API Gateway
    (o mesmo events/pedido.json usado no `sam local invoke`)."""
    resp = _executar(cloud_event.data)
    print(f"RESULTADO {json.dumps(resp, ensure_ascii=False)}", flush=True)
