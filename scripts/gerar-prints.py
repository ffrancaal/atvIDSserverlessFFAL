"""Renderiza as saídas de evidencias/gcp/*.txt como imagens PNG estilo terminal.

Uso: .venv/bin/python scripts/gerar-prints.py
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

RAIZ = Path(__file__).resolve().parent.parent
PASTA = RAIZ / "evidencias" / "gcp"
ARQUIVOS = ["01-ambiente", "03-evento", "04a-http-sem-reaproveitamento",
            "04b-http-com-reaproveitamento", "05a-timeout-3s", "05b-timeout-10s"]

FONTE = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 15)
FUNDO, TEXTO, CMD, TIT, OK, ERRO = "#1e1e1e", "#d4d4d4", "#4ec9b0", "#dcdcaa", "#6a9955", "#f44747"


def cor(linha):
    if linha.startswith("$ "):
        return CMD
    if linha.startswith("====="):
        return TIT
    if "HTTP 5" in linha or "Exception" in linha or "ERROR" in linha or "Error" in linha:
        return ERRO
    if "HTTP 2" in linha or linha.startswith(">>") or "passed" in linha:
        return OK
    return TEXTO


def quebrar(linha, largura=140):
    return [linha[i:i + largura] for i in range(0, max(len(linha), 1), largura)]


def render(nome):
    linhas = []
    for l in (PASTA / f"{nome}.txt").read_text().splitlines():
        linhas += quebrar(l)
    alt_linha = 20
    w = 1400
    h = 40 + alt_linha * len(linhas) + 20
    img = Image.new("RGB", (w, h), FUNDO)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w, 28], fill="#323233")
    for i, c in enumerate(["#ff5f56", "#ffbd2e", "#27c93f"]):
        d.ellipse([12 + i * 20, 8, 24 + i * 20, 20], fill=c)
    d.text((90, 6), f"zsh — atvIDSserverlessFFAL — {nome}", font=FONTE, fill="#9d9d9d")
    y = 40
    for l in linhas:
        d.text((14, y), l, font=FONTE, fill=cor(l))
        y += alt_linha
    destino = RAIZ / "evidencias" / f"{nome}.png"
    img.save(destino)
    print(destino.relative_to(RAIZ))


if __name__ == "__main__":
    for n in (sys.argv[1:] or ARQUIVOS):
        render(n)
