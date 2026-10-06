"""Gera o cartaz de divulgacao (1600 x 900) a partir das capturas de docs/images.

    python tools/make-cartaz.py 1.0.2 pt     -> docs/divulgacao/cartaz-1.0.2.png
    python tools/make-cartaz.py 1.0.2 en     -> docs/divulgacao/cartaz-1.0.2-en.png

Precisa do Pillow e das fontes Segoe UI do Windows. Os textos de cada idioma estao em TEXTS; ao mudar de versao
actualiza-os (as novidades vem do CHANGELOG) e escolhe as duas capturas em SHOTS.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
FONTS = r'C:\Windows\Fonts'
W, H = 1600, 900

# a captura de tras e a da frente (dentro de docs/images)
SHOTS = ('10-mapa-metricas.png', '20-relatorio-dependencias.png')

TEXTS = {
    'pt': {
        'subtitle': 'Mais métricas e o Mercurial',
        'headline': ['Mapa e checklist de', 'código-fonte Delphi'],
        'bullets': [
            'Complexidade cognitiva por método',
            'Parâmetros e aninhamento no Mapa e no Painel',
            'Mercurial, Git e Subversion: o que mudou',
            'Relatório de dependências em 4 idiomas',
            'Traduções revistas · PT · EN · FR · DE',
        ],
        'footer': ['Windows 10/11', 'gratuito', 'código aberto'],
        'suffix': '',
    },
    'en': {
        'subtitle': 'More metrics and Mercurial',
        'headline': ['Delphi source-code', 'map and checklist'],
        'bullets': [
            'Cognitive complexity per method',
            'Parameters and nesting on Map and Dashboard',
            'Mercurial, Git and Subversion: what changed',
            'Dependency report in 4 languages',
            'Translations reviewed · PT · EN · FR · DE',
        ],
        'footer': ['Windows 10/11', 'free', 'open source'],
        'suffix': '-en',
    },
}


def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)


def gradient():
    top, bottom = (22, 77, 65), (35, 112, 95)
    img = Image.new('RGB', (W, H))
    px = img.load()
    for y in range(H):
        for x in range(W):
            t = (0.7 * y / H) + (0.3 * x / W)
            px[x, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return img


def card(path, width):
    """A captura com cantos redondos e sombra."""
    shot = Image.open(os.path.join(ROOT, 'docs', 'images', path)).convert('RGB')
    height = int(shot.height * width / shot.width)
    shot = shot.resize((width, height), Image.LANCZOS)
    mask = Image.new('L', shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, shot.width, shot.height), 22, fill=255)
    pad = 40
    layer = Image.new('RGBA', (shot.width + 2 * pad, shot.height + 2 * pad), (0, 0, 0, 0))
    shadow = Image.new('RGBA', layer.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((pad, pad + 10, pad + shot.width, pad + 10 + shot.height), 22,
                                             fill=(0, 0, 0, 110))
    layer = Image.alpha_composite(layer, shadow.filter(ImageFilter.GaussianBlur(16)))
    layer.paste(shot, (pad, pad), mask)
    return layer, pad


def main():
    version = sys.argv[1] if len(sys.argv) > 1 else '1.0.2'
    lang = sys.argv[2] if len(sys.argv) > 2 else 'pt'
    t = TEXTS[lang]
    img = gradient().convert('RGBA')
    d = ImageDraw.Draw(img)

    # o logotipo e o nome
    d.rounded_rectangle((80, 80, 165, 165), 18, fill='white')
    d.text((122, 122), '[ ]', font=font('segoeuib.ttf', 44), fill=(35, 112, 95), anchor='mm')
    d.text((192, 126), 'CodeManager', font=font('segoeuib.ttf', 74), fill='white', anchor='lm')

    # a versao
    d.rounded_rectangle((80, 200, 231, 253), 26, fill='white')
    d.text((155, 227), 'v' + version, font=font('segoeuib.ttf', 32), fill=(22, 77, 65), anchor='mm')
    d.text((252, 227), t['subtitle'], font=font('segoeui.ttf', 31), fill=(226, 238, 233), anchor='lm')

    # o titulo
    y = 318
    for line in t['headline']:
        d.text((80, y), line, font=font('segoeuib.ttf', 52), fill='white')
        y += 57
    # os pontos
    y = 480
    for text in t['bullets']:
        d.ellipse((80, y - 9, 98, y + 9), fill='white')
        d.text((115, y), text, font=font('segoeui.ttf', 29), fill='white', anchor='lm')
        y += 54
    # o rodape
    x = 80
    for i, part in enumerate(t['footer']):
        f = font('segoeuib.ttf', 27)
        d.text((x, 805), part, font=f, fill='white', anchor='lm')
        x += int(d.textlength(part, font=f))
        if i < len(t['footer']) - 1:
            d.text((x + 18, 805), '·', font=f, fill=(226, 238, 233), anchor='mm')
            x += 36
    d.text((80, 853), 'github.com/JFSF/CodeManager', font=font('segoeui.ttf', 26), fill=(226, 238, 233), anchor='lm')

    # as capturas: a de tras mais acima e a da frente mais abaixo
    back, pad = card(SHOTS[0], 640)
    img.alpha_composite(back, (840 - pad, 56 - pad))
    front, pad = card(SHOTS[1], 700)
    img.alpha_composite(front, (780 - pad, 420 - pad))

    out = os.path.join(ROOT, 'docs', 'divulgacao', 'cartaz-%s%s.png' % (version, t['suffix']))
    img.convert('RGB').save(out, optimize=True)
    print(out)


if __name__ == '__main__':
    main()
