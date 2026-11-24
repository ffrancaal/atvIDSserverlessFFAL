import base64
import json

from hello_world import app


def evento(body):
    return {"httpMethod": "POST", "path": "/guias", "body": json.dumps(body) if body is not None else None}


def test_gera_guia():
    ret = app.lambda_handler(evento({"requisicaoId": "R-001", "hospital": "H-Recife", "bolsas": ["O-NEG-0142"]}), None)
    data = json.loads(ret["body"])
    assert ret["statusCode"] == 201
    assert data["guia"] == "G-R-001"
    assert data["hospital"] == "H-Recife"
    assert data["bolsas"] == ["O-NEG-0142"]


def test_sem_requisicao_id():
    ret = app.lambda_handler(evento({"hospital": "H-Recife"}), None)
    assert ret["statusCode"] == 400


def test_body_vazio():
    assert app.lambda_handler(evento(None), None)["statusCode"] == 400


def test_contador_cresce_no_mesmo_processo():
    a = json.loads(app.lambda_handler(evento({"requisicaoId": "A"}), None)["body"])["invocacaoNesteAmbiente"]
    b = json.loads(app.lambda_handler(evento({"requisicaoId": "B"}), None)["body"])["invocacaoNesteAmbiente"]
    assert b == a + 1


def test_body_base64():
    raw = base64.b64encode(json.dumps({"requisicaoId": "R-9"}).encode()).decode()
    ret = app.lambda_handler({"body": raw, "isBase64Encoded": True}, None)
    assert ret["statusCode"] == 201
    assert json.loads(ret["body"])["guia"] == "G-R-9"
