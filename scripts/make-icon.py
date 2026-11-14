#!/usr/bin/env python3
"""Generate the QuickTab macOS app icon (1024x1024 RGBA PNG).

Motif: fanned window cards (Alt+Tab switcher) with a bright selection
marquee on the front card (screenshot tool). Follows the macOS Big Sur+
icon grid: 824x824 squircle body centred on a 1024 canvas.

Requires Python 3 + Pillow only. Writes Resources/AppIcon-1024.png
relative to the repository root.
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SS = 4                      # supersampling factor
SIZE = 1024
W = SIZE * SS


def s(v):
    return int(round(v * SS))


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def diagonal_gradient(size, c0, c1):
    """Top-left c0 -> bottom-right c1."""
    w, h = size
    hor = Image.linear_gradient("L").transpose(Image.Transpose.ROTATE_90).resize((w, h))
    if hor.getpixel((0, 0)) > 128:                                # ensure 0 left..255 right
        hor = ImageChops.invert(hor)
    ver = Image.linear_gradient("L").resize((w, h))               # 0 top..255 bottom
    t = ImageChops.add(hor, ver, scale=2.0)
    a = Image.new("RGB", (w, h), c0)
    b = Image.new("RGB", (w, h), c1)
    return Image.composite(b, a, t)


def rr_mask(size, box, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def make_card(cw, ch, radius, body, bar, dots, shadow_alpha):
    """Return an RGBA layer containing one window card plus its soft shadow."""
    pad = s(70)
    lw, lh = cw + 2 * pad, ch + 2 * pad
    layer = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))

    # shadow
    sh = Image.new("L", (lw, lh), 0)
    ImageDraw.Draw(sh).rounded_rectangle(
        (pad, pad + s(14), pad + cw, pad + ch + s(14)), radius=radius,
        fill=shadow_alpha)
    sh = sh.filter(ImageFilter.GaussianBlur(s(22)))
    layer.paste((10, 12, 50, 255), (0, 0), sh)

    box = (pad, pad, pad + cw, pad + ch)
    card_mask = rr_mask((lw, lh), box, radius)
    card = Image.new("RGBA", (lw, lh), body)
    # title bar
    bar_h = s(62)
    d = ImageDraw.Draw(card)
    d.rectangle((pad, pad, pad + cw, pad + bar_h), fill=bar)
    # three dots
    r = s(11)
    cy = pad + bar_h // 2
    for i, col in enumerate(dots):
        cx = pad + s(40) + i * s(36)
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=col)
    layer.paste(card, (0, 0), card_mask)
    return layer, pad, bar_h


def main():
    root = Path(__file__).resolve().parent.parent
    out = root / "Resources" / "AppIcon-1024.png"
    out.parent.mkdir(parents=True, exist_ok=True)

    canvas = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    body_box = (s(100), s(100), s(924), s(924))
    radius = s(185)

    # --- drop shadow of the squircle body
    sh = Image.new("L", (W, W), 0)
    ImageDraw.Draw(sh).rounded_rectangle(
        (body_box[0], body_box[1] + s(10), body_box[2], body_box[3] + s(10)),
        radius=radius, fill=90)
    sh = sh.filter(ImageFilter.GaussianBlur(s(12)))
    canvas.paste((0, 0, 30, 255), (0, 0), sh)

    # --- body: diagonal gradient
    bw = body_box[2] - body_box[0]
    body = diagonal_gradient((bw, bw), hex_rgb("#5E6EFF"), hex_rgb("#252F86")).convert("RGBA")

    # faint top highlight (soft glow, upper area)
    hl = Image.new("L", (bw, bw), 0)
    ImageDraw.Draw(hl).ellipse((-s(200), -s(560), bw + s(200), s(330)), fill=42)
    hl = hl.filter(ImageFilter.GaussianBlur(s(60)))
    body.paste((255, 255, 255, 255), (0, 0), hl)

    # --- window cards (back -> front)
    cw, ch, cr = s(500), s(380), s(46)
    centre = bw // 2

    def place(layer, cx, cy, angle):
        cx, cy = cx + s(32), cy + s(12)          # optically centre the group
        rot = layer.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
        body.alpha_composite(rot, (cx - rot.width // 2, cy - rot.height // 2))

    # back card
    lay, _, _ = make_card(cw, ch, cr, (164, 176, 236, 255), (138, 150, 218, 255),
                          [(110, 122, 196, 255)] * 3, 120)
    place(lay, centre - s(70), centre - s(95), 14)
    # middle card
    lay, _, _ = make_card(cw, ch, cr, (214, 220, 250, 255), (190, 198, 240, 255),
                          [(150, 160, 215, 255)] * 3, 130)
    place(lay, centre - s(20), centre - s(35), 6)

    # front card (upright), with traffic-light dots and selection marquee
    lay, pad, bar_h = make_card(
        cw, ch, cr, (255, 255, 255, 255), (234, 237, 250, 255),
        [hex_rgb("#FF5F57") + (255,), hex_rgb("#FEBC2E") + (255,),
         hex_rgb("#28C840") + (255,)], 150)
    d = ImageDraw.Draw(lay)
    # selection rectangle inside the card content area
    x0 = pad + s(78)
    y0 = pad + bar_h + s(58)
    x1 = pad + cw - s(78)
    y1 = pad + ch - s(58)
    # tinted selected area
    sel = Image.new("RGBA", lay.size, (0, 0, 0, 0))
    ImageDraw.Draw(sel).rounded_rectangle((x0, y0, x1, y1), radius=s(10),
                                          fill=(255, 214, 10, 60))
    lay.alpha_composite(sel)
    # corner brackets
    accent = hex_rgb("#FFC400") + (255,)
    t = s(22)          # stroke
    L = s(78)          # bracket arm length
    o = t // 2
    for (cx, cy, sx, sy) in ((x0, y0, 1, 1), (x1, y0, -1, 1),
                             (x0, y1, 1, -1), (x1, y1, -1, -1)):
        # horizontal arm
        hx = sorted((cx - sx * o, cx + sx * L))
        hy = sorted((cy - sy * o, cy + sy * o))
        d.rounded_rectangle((hx[0], hy[0], hx[1], hy[1]), radius=o, fill=accent)
        vx = sorted((cx - sx * o, cx + sx * o))
        vy = sorted((cy - sy * o, cy + sy * L))
        d.rounded_rectangle((vx[0], vy[0], vx[1], vy[1]), radius=o, fill=accent)
    # crosshair centre mark
    mx, my = (x0 + x1) // 2, (y0 + y1) // 2
    ct, cl = s(9), s(26)
    d.rounded_rectangle((mx - cl, my - ct // 2, mx + cl, my + ct // 2), radius=ct // 2, fill=accent)
    d.rounded_rectangle((mx - ct // 2, my - cl, mx + ct // 2, my + cl), radius=ct // 2, fill=accent)

    place(lay, centre + s(30), centre + s(55), 0)

    # --- clip body to squircle and composite
    mask = rr_mask((bw, bw), (0, 0, bw - 1, bw - 1), radius)
    a = ImageChops.multiply(body.getchannel("A"), mask)
    body.putalpha(a)
    canvas.alpha_composite(body, (body_box[0], body_box[1]))

    icon = canvas.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    icon.save(out, "PNG")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
