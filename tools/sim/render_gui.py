#!/usr/bin/env python3
"""Rasterise an exported ScreenGui layout (Sim.export_gui) to a PNG with PIL.

Approximates Roblox UI drawing: frames with corners/strokes/gradients, text with alignment, scaling
and wrapping. It verifies layout, overlap and readability at different viewport sizes; it is not a
pixel-exact Roblox renderer (fonts differ, no images).
"""
from PIL import Image, ImageDraw, ImageFont

FONT_REG = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
FONT_BOLD = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
_fonts = {}


def font(size, bold):
    key = (int(size), bold)
    if key not in _fonts:
        try:
            _fonts[key] = ImageFont.truetype(FONT_BOLD if bold else FONT_REG, max(6, int(size)))
        except OSError:
            _fonts[key] = ImageFont.load_default()
    return _fonts[key]


def rgba(c, t):
    r, g, b = [int(max(0, min(1, x)) * 255) for x in c[:3]]
    return (r, g, b, int(255 * (1 - max(0, min(1, t)))))


def wrap(draw, text, f, width):
    lines = []
    for para in text.split('\n'):
        words = para.split(' ')
        cur = ''
        for w in words:
            nxt = (cur + ' ' + w).strip()
            if draw.textlength(nxt, font=f) <= width or not cur:
                cur = nxt
            else:
                lines.append(cur)
                cur = w
        lines.append(cur)
    return lines


def render(items, size, background=None, out=None):
    w, h = size
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    if background is not None:
        bg = background.convert('RGBA').resize((w, h))
        img.alpha_composite(bg)
    else:
        # neutral sky-ish backdrop so translucent panels read
        base = Image.new('RGBA', (w, h), (58, 66, 86, 255))
        img.alpha_composite(base)
    items = sorted(items, key=lambda it: it['order'])
    for it in items:
        x, y, iw, ih = it['x'], it['y'], it['w'], it['h']
        if iw <= 0 or ih <= 0:
            continue
        layer = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        box = [x, y, x + iw, y + ih]
        rad = int(it.get('radius') or 0)
        if it.get('bgT', 1) < 1 and it['cls'] not in ('TextLabel',) or (it['cls'] == 'TextLabel' and it.get('bgT', 1) < 1):
            fill = rgba(it['bg'], it['bgT'])
            if it.get('grad'):
                # approximate gradient by fading alpha across the box
                g = Image.new('RGBA', (max(1, int(iw)), max(1, int(ih))), fill)
                gmask = Image.linear_gradient('L').resize((max(1, int(iw)), max(1, int(ih))))
                rot = it['grad'][2]
                if rot:
                    gmask = gmask.rotate(-rot, expand=False)
                alpha = Image.eval(gmask, lambda v: int(fill[3] * (1 - v / 255)))
                g.putalpha(alpha)
                layer.paste(g, (int(x), int(y)), g)
            elif rad > 0:
                d.rounded_rectangle(box, radius=rad, fill=fill)
            else:
                d.rectangle(box, fill=fill)
        if it.get('stroke'):
            col, th, tr = it['stroke']
            if tr < 1:
                d.rounded_rectangle(box, radius=rad, outline=rgba(col, tr), width=max(1, int(round(th))))
        text = it.get('text')
        if text and it.get('textT', 1) < 1:
            bold = 'Bold' in (it.get('font') or '') or 'Black' in (it.get('font') or '') or 'Heavy' in (it.get('font') or '')
            ts = it.get('textSize') or 14
            if it.get('scaled'):
                ts = max(8, min(ih * 0.9, 100))
                f = font(ts, bold)
                while ts > 8 and d.textlength(text.split('\n')[0], font=f) > iw:
                    ts -= 1
                    f = font(ts, bold)
            f = font(ts, bold)
            lines = wrap(d, text, f, iw) if it.get('wrap') else text.split('\n')
            lh = ts * 1.15
            total = lh * len(lines)
            ya = it.get('ya', 'Center')
            ty = y + (ih - total) / 2 if ya == 'Center' else (y if ya == 'Top' else y + ih - total)
            for line in lines:
                tw = d.textlength(line, font=f)
                xa = it.get('xa', 'Center')
                tx = x + (iw - tw) / 2 if xa == 'Center' else (x if xa == 'Left' else x + iw - tw)
                if it.get('strokeT', 1) < 1:
                    for ox, oy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                        d.text((tx + ox, ty + oy), line, font=f, fill=(0, 0, 0, int(255 * (1 - it['strokeT']))))
                d.text((tx, ty), line, font=f, fill=rgba(it['textColor'], it['textT']))
                ty += lh
        clip = it.get('clip')
        if clip:
            mask = Image.new('L', (w, h), 0)
            ImageDraw.Draw(mask).rectangle([clip[0], clip[1], clip[0] + clip[2], clip[1] + clip[3]], fill=255)
            layer.putalpha(Image.composite(layer.getchannel('A'), Image.new('L', (w, h), 0), mask))
        img.alpha_composite(layer)
    if out:
        img.convert('RGB').save(out)
    return img
