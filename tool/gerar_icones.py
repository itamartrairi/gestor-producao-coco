"""Gera os ícones dos apps (arte original, desenhada em código).

Uso: python3 tool/gerar_icones.py coco|revenda assets/icon

Para cada app produz:
  icone.png        1024x1024, fundo cheio (iOS e Android legado)
  icone_frente.png 1024x1024, fundo transparente, desenho na zona segura (Android adaptativo)
"""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONTE = str(__import__('pathlib').Path(__file__).resolve().parent.parent / 'assets' / 'fonts' / 'NotoSans-Bold.ttf')

S = 4  # superamostragem
N = 1024 * S


def novo(transparente=False):
    return Image.new('RGBA', (N, N), (0, 0, 0, 0) if transparente else (0, 0, 0, 255))


def fundo_gradiente(img, c1, c2):
    d = ImageDraw.Draw(img)
    for y in range(N):
        t = y / (N - 1)
        c = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)) + (255,)
        d.line([(0, y), (N, y)], fill=c)


def finalizar(img):
    return img.resize((1024, 1024), Image.LANCZOS)


def p(x, y, escala, cx=512, cy=512):
    """Converte coordenadas do desenho (0..1024) aplicando escala em torno do centro."""
    return ((cx + (x - cx) * escala) * S, (cy + (y - cy) * escala) * S)


# ---------------- Coqueiro ----------------
def desenhar_coqueiro(img, escala):
    d = ImageDraw.Draw(img)
    # Areia / chão
    d.ellipse([*p(250, 800, escala), *p(800, 900, escala)], fill=(233, 201, 139, 255))
    # Tronco curvo (segmentos)
    pts = []
    for i in range(0, 21):
        t = i / 20
        x = 560 - 90 * math.sin(t * math.pi * 0.9) + 40 * t
        y = 850 - 460 * t
        pts.append((x, y))
    for i, (x, y) in enumerate(pts[:-1]):
        larg = 46 - 18 * (i / 20)
        x2, y2 = pts[i + 1]
        cor = (166, 112, 62, 255) if i % 2 == 0 else (140, 92, 50, 255)
        d.polygon([p(x - larg, y, escala), p(x + larg, y, escala), p(x2 + larg - 2, y2, escala), p(x2 - larg + 2, y2, escala)],
                  fill=cor)
    topo = pts[-1]
    # Folhas (palmas)
    folhas = [(-165, 40), (-120, -55), (-45, -110), (45, -115), (125, -60), (170, 35), (-10, -125)]
    for ang_x, ang_y in folhas:
        fx, fy = topo[0] + ang_x * 1.6, topo[1] + ang_y * 1.4
        cx, cy = (topo[0] + fx) / 2, min(topo[1], fy) - 70
        curva = []
        for k in range(0, 31):
            t = k / 30
            x = (1 - t) ** 2 * topo[0] + 2 * (1 - t) * t * cx + t ** 2 * fx
            y = (1 - t) ** 2 * topo[1] + 2 * (1 - t) * t * cy + t ** 2 * fy
            curva.append((x, y))
        # contorno da folha com largura variável
        lado_a, lado_b = [], []
        for k, (x, y) in enumerate(curva):
            t = k / 30
            w = 34 * math.sin(math.pi * min(1, t * 1.1))
            if k < 30:
                nx, ny = curva[k + 1][0] - x, curva[k + 1][1] - y
            else:
                nx, ny = x - curva[k - 1][0], y - curva[k - 1][1]
            n = math.hypot(nx, ny) or 1
            ox, oy = -ny / n * w, nx / n * w
            lado_a.append(p(x + ox, y + oy, escala))
            lado_b.append(p(x - ox, y - oy, escala))
        d.polygon(lado_a + lado_b[::-1], fill=(132, 196, 74, 255))
        d.line([p(x, y, escala) for x, y in curva], fill=(92, 150, 46, 255), width=int(6 * S * escala))
    # Cocos
    for dx, dy, cor in [(-38, 30, (122, 74, 36, 255)), (30, 34, (102, 60, 28, 255)), (-2, 66, (96, 158, 58, 255))]:
        x, y = topo[0] + dx, topo[1] + dy
        r = 38
        d.ellipse([*p(x - r, y - r, escala), *p(x + r, y + r, escala)], fill=cor)
        d.ellipse([*p(x - r * 0.45, y - r * 0.6, escala), *p(x - r * 0.05, y - r * 0.25, escala)], fill=(255, 255, 255, 60))


# ---------------- Sacola de compras ----------------
def desenhar_sacola(img, escala):
    d = ImageDraw.Draw(img)
    # Sombra
    sombra = Image.new('RGBA', img.size, (0, 0, 0, 0))
    ds = ImageDraw.Draw(sombra)
    ds.rounded_rectangle([*p(300, 400, escala), *p(740, 860, escala)], radius=int(40 * S * escala), fill=(0, 0, 0, 90))
    sombra = sombra.filter(ImageFilter.GaussianBlur(18 * S * escala))
    img.alpha_composite(sombra, (int(12 * S * escala), int(18 * S * escala)))
    d = ImageDraw.Draw(img)
    # Alça
    d.arc([*p(400, 250, escala), *p(640, 520, escala)], start=180, end=360, fill=(255, 255, 255, 255), width=int(34 * S * escala))
    # Corpo da sacola
    d.rounded_rectangle([*p(290, 380, escala), *p(730, 840, escala)], radius=int(40 * S * escala), fill=(255, 255, 255, 255))
    # Furos da alça
    for x in (420, 620):
        d.ellipse([*p(x - 16, 410, escala), *p(x + 16, 442, escala)], fill=(142, 59, 110, 255))
    # Faixa do catálogo
    d.rounded_rectangle([*p(340, 520, escala), *p(680, 560, escala)], radius=int(16 * S * escala), fill=(246, 214, 232, 255))
    d.rounded_rectangle([*p(340, 590, escala), *p(560, 625, escala)], radius=int(14 * S * escala), fill=(246, 214, 232, 255))
    # Etiqueta de preço (dourada), inclinada
    tag = Image.new('RGBA', img.size, (0, 0, 0, 0))
    dt = ImageDraw.Draw(tag)
    cx, cy = 640, 720
    dt.polygon([p(cx - 120, cy - 70, escala), p(cx + 60, cy - 70, escala), p(cx + 130, cy, escala),
                p(cx + 60, cy + 70, escala), p(cx - 120, cy + 70, escala)], fill=(242, 182, 50, 255))
    dt.ellipse([*p(cx + 38, cy - 16, escala), *p(cx + 70, cy + 16, escala)], fill=(255, 255, 255, 255))
    # "R$" com a fonte Noto Sans Bold do próprio app
    fonte = ImageFont.truetype(FONTE, int(78 * S * escala))
    dt.text(p(cx - 38, cy + 4, escala), 'R$', font=fonte, fill=(122, 46, 93, 255), anchor='mm')
    tag = tag.rotate(-14, center=p(cx, cy, escala), resample=Image.BICUBIC)
    img.alpha_composite(tag)


def gerar(app, destino):
    if app == 'coco':
        cor1, cor2, desenho = (46, 107, 58), (24, 74, 36), desenhar_coqueiro
    else:
        cor1, cor2, desenho = (176, 72, 136), (122, 46, 93), desenhar_sacola
    cheio = novo()
    fundo_gradiente(cheio, cor1, cor2)
    desenho(cheio, 0.92)
    finalizar(cheio).convert('RGB').save(f'{destino}/icone.png')
    frente = novo(transparente=True)
    desenho(frente, 0.62)  # zona segura do ícone adaptativo (~66%)
    finalizar(frente).save(f'{destino}/icone_frente.png')


if __name__ == '__main__':
    gerar(sys.argv[1], sys.argv[2])
