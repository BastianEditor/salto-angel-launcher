# Genera las imágenes del instalador (NSIS) con la marca de Salto Ángel.
# Uso: C:\Python314\python.exe -I generar_imagenes.py   (necesita Pillow)
# Salen: lateral.bmp (164x314, pantallas de bienvenida y final) y encabezado.bmp (150x57, resto de pasos).
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

AQUI = Path(__file__).resolve().parent
IMG = AQUI.parent.parent / "src" / "img"
FONDO = (6, 10, 18)
ORO = (245, 197, 66)
ORO_CLARO = (255, 224, 138)
VIOLETA = (139, 92, 246)
VIOLETA_CLARO = (196, 181, 253)
FUENTES = Path(r"C:\Windows\Fonts")
ESCALA = 4  # se dibuja grande y se reduce: bordes y letras más finos


def fuente(nombre, tam):
    try:
        return ImageFont.truetype(str(FUENTES / nombre), tam * ESCALA)
    except OSError:
        return ImageFont.load_default()


def degradado_vertical(ancho, alto, arriba, abajo):
    capa = Image.new("RGBA", (ancho, alto))
    d = ImageDraw.Draw(capa)
    for y in range(alto):
        t = y / max(alto - 1, 1)
        color = tuple(int(arriba[i] + (abajo[i] - arriba[i]) * t) for i in range(4))
        d.line([(0, y), (ancho, y)], fill=color)
    return capa


def brillo(lienzo, centro, radio, color, fuerza):
    capa = Image.new("RGBA", lienzo.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(capa)
    x, y = centro
    d.ellipse([x - radio, y - radio, x + radio, y + radio], fill=color + (fuerza,))
    capa = capa.filter(ImageFilter.GaussianBlur(radio * 0.6))
    lienzo.alpha_composite(capa)


def texto_centrado(d, ancho, y, texto, f, color, espaciado=0):
    letras = list(texto)
    anchos = [d.textlength(c, font=f) for c in letras]
    total = sum(anchos) + espaciado * ESCALA * (len(letras) - 1)
    x = (ancho - total) / 2
    for c, w in zip(letras, anchos):
        d.text((x, y), c, font=f, fill=color)
        x += w + espaciado * ESCALA


def lateral():
    W, H = 164 * ESCALA, 314 * ESCALA
    lienzo = Image.new("RGBA", (W, H), FONDO + (255,))

    lienzo.alpha_composite(degradado_vertical(W, H, (20, 16, 42, 255), (6, 10, 18, 255)))

    brillo(lienzo, (W // 2, int(H * 0.40)), int(W * 0.42), VIOLETA, 90)
    brillo(lienzo, (W // 2, int(H * 0.40)), int(W * 0.25), ORO, 60)

    # Emblema
    emb = Image.open(IMG / "emblema.webp").convert("RGBA")
    tam = int(W * 0.62)
    emb = emb.resize((tam, tam), Image.LANCZOS)
    lienzo.alpha_composite(emb, ((W - tam) // 2, int(H * 0.40) - tam // 2))

    d = ImageDraw.Draw(lienzo)
    y = int(H * 0.66)
    texto_centrado(d, W, y, "SALTO ÁNGEL", fuente("bahnschrift.ttf", 17), ORO, 1.2)
    y += 24 * ESCALA
    texto_centrado(d, W, y, "LAUNCHER", fuente("seguisb.ttf", 10), VIOLETA_CLARO, 3)

    # Línea dorada a violeta
    y += 22 * ESCALA
    linea = Image.new("RGBA", (W, 2 * ESCALA))
    ld = ImageDraw.Draw(linea)
    for x in range(W):
        t = x / (W - 1)
        borde = min(t, 1 - t) * 2  # se apaga en las puntas
        c = tuple(int(ORO[i] + (VIOLETA[i] - ORO[i]) * t) for i in range(3))
        ld.line([(x, 0), (x, 2 * ESCALA)], fill=c + (int(230 * min(1, borde * 2.2)),))
    lienzo.alpha_composite(linea.crop((W // 6, 0, W - W // 6, 2 * ESCALA)), (W // 6, y))

    y += 12 * ESCALA
    texto_centrado(d, W, y, "Rol venezolano", fuente("segoeui.ttf", 9), (200, 205, 215))
    texto_centrado(d, W, H - 22 * ESCALA, "cfx.re/join/m4qzz8q", fuente("segoeui.ttf", 7), (120, 128, 145))

    lienzo.resize((164, 314), Image.LANCZOS).convert("RGB").save(AQUI / "lateral.bmp")


def encabezado():
    W, H = 150 * ESCALA, 57 * ESCALA
    lienzo = Image.new("RGBA", (W, H), FONDO + (255,))
    lienzo.alpha_composite(degradado_vertical(W, H, (20, 16, 42, 255), (6, 10, 18, 255)))
    brillo(lienzo, (int(W * 0.22), H // 2), int(H * 0.7), VIOLETA, 110)

    emb = Image.open(IMG / "emblema.webp").convert("RGBA")
    tam = int(H * 0.86)
    emb = emb.resize((tam, tam), Image.LANCZOS)
    lienzo.alpha_composite(emb, (int(W * 0.04), (H - tam) // 2))

    d = ImageDraw.Draw(lienzo)
    x = int(W * 0.04) + tam + 6 * ESCALA
    d.text((x, 14 * ESCALA), "SALTO ÁNGEL", font=fuente("bahnschrift.ttf", 12), fill=ORO)
    d.text((x + ESCALA, 31 * ESCALA), "LAUNCHER", font=fuente("seguisb.ttf", 8), fill=VIOLETA_CLARO)
    # Línea dorada abajo
    d.rectangle([0, H - 2 * ESCALA, W, H], fill=ORO_CLARO)

    lienzo.resize((150, 57), Image.LANCZOS).convert("RGB").save(AQUI / "encabezado.bmp")


if __name__ == "__main__":
    lateral()
    encabezado()
    print("ok", AQUI / "lateral.bmp", AQUI / "encabezado.bmp")
