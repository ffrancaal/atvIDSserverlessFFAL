import base64, json, time

contador = 0  # variável global: só sobrevive se o ambiente for reaproveitado

def lambda_handler(event, context):
    global contador
    contador += 1
    body = event.get("body") or "{}"
    if event.get("isBase64Encoded"):  # sam local generate-event codifica o body em base64
        body = base64.b64decode(body).decode("utf-8")
    pedido = json.loads(body)
    if "requisicaoId" not in pedido:
        return {"statusCode": 400,
                "body": json.dumps({"erro": "requisicaoId obrigatório"})}
    if pedido.get("demorar"):
        time.sleep(5)  # passa do Timeout de 3 s do template
    guia = {"guia": "G-" + pedido["requisicaoId"],
            "hospital": pedido.get("hospital"),
            "bolsas": pedido.get("bolsas", []),
            "invocacaoNesteAmbiente": contador}
    return {"statusCode": 201, "body": json.dumps(guia)}
