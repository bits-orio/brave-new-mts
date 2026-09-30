#!/usr/bin/env python3
"""Generate thumbnail.png: the mod-portal card, in the house style shared with
Multi-Team Support, Research Cost Shaper and the other family cards: 512x512,
charcoal ground, a dark frame, the three-letter mark, and a grey subtitle in
caps, at the same heights so the cards line up in a row on the author page.

Three layers, back to front, inside the frame:

  - The Brave New Roboport seen up close: the vanilla roboport's sprite layers
    (base, patch, antenna, doors) put together as the game draws them, with
    the mod's uranium-green tint and additive glow (prototypes/bnm_roboport.lua)
    at full brightness, zoomed in so its hatch and the machinery around it
    fill the card.
  - The mark, BNM: blue and red as the card has always had them, and a yellow
    N (Multi-Team Support's yellow), since a green N vanishes into the glow.
  - The subtitle, in its grey.
The text is separated from the glow the family way: a centred black halo
behind it, no offset to one side (land-title-registry and multi-team-support
explain why). Over a busy picture the halo alone isn't enough, so, exactly as
on Research Cost Shaper's card, a thin dark outline hugs every glyph and a
soft dark band sits behind the subtitle.

Needs the Factorio install for the roboport sprites (FACTORIO_DATA below) and
DejaVu Sans Bold.

Run from the repo root:  python3 tools/gen_thumbnail.py [out.png]
"""

import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

SIZE = 512
BG = (43, 43, 43)
FRAME = (26, 26, 26)
FRAME_OUTER = 16          # the frame's outer edge, from the card's edge
FRAME_WIDTH = 12
FRAME_RADIUS = 14

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# The mark, where the card has always had it: each letter's inked box, left
# edge and top, and the shared cap height, measured off the previous card.
LETTERS = (("B", (66, 133, 244), 44), ("N", (245, 184, 46), 175), ("M", (234, 67, 53), 316))
LETTER_TOP, LETTER_HEIGHT = 151, 139
SUBTITLE = "BRAVE NEW MTS"
SUBTITLE_FILL = (146, 146, 146)
SUBTITLE_BOX = (77, 402, 436, 431)   # left, top, right, bottom of its ink

# Readability over the glow, as on Research Cost Shaper's card (the family's
# card with a picture behind the text): a centred black halo, a thin dark
# outline on every glyph, and a dark band fading in behind the subtitle.
HALO = (0, 0, 0)
HALO_RADIUS = 10
HALO_STRENGTH = 2.0
INK = (14, 16, 22)
LETTER_OUTLINE = 4
SUBTITLE_OUTLINE = 3
SUBTITLE_BAND = (360, 490, 150)  # top, bottom (the frame), peak darkness (0-255)

# The background roboport.
FACTORIO_DATA = Path.home() / "factorio" / "data"
ROBOPORT = FACTORIO_DATA / "base" / "graphics" / "entity" / "roboport"
# (file, frame width, frame height, shift in game pixels at scale 0.5), from
# data.raw.roboport.roboport; the sheets are high-res, so a shift is doubled.
ROBOPORT_LAYERS = (
    ("roboport-base.png", 228, 277, (2, -2.25)),
    ("roboport-base-patch.png", 138, 100, (1.5, -5)),
    ("roboport-base-animation.png", 83, 59, (-17.75, -71.25)),
    ("roboport-door-up.png", 97, 38, (-0.25, -39.5)),
    ("roboport-door-down.png", 97, 41, (-0.25, -19.75)),
)
BNM_TINT = (0.15, 1.0, 0.15)      # prototypes/bnm_roboport.lua
# The close-up: a square of the sprite, in sprite pixels around the entity's
# centre, scaled up to fill the frame. Smaller = closer.
ZOOM_CENTRE = (0, -16)
ZOOM_SIZE = 139
# The glow at full strength, only a touch soft so the mark stays the
# sharpest thing on the card.
BACKGROUND_BRIGHTNESS = 1.0
BACKGROUND_SATURATION = 1.0
BACKGROUND_BLUR = 0.4


def roboport_sprite():
    """The roboport as the game stacks its layers, on a transparent canvas
    centred on the entity (first frame of each animation)."""
    w = h = 480
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for name, fw, fh, (sx, sy) in ROBOPORT_LAYERS:
        frame = Image.open(ROBOPORT / name).convert("RGBA").crop((0, 0, fw, fh))
        canvas.alpha_composite(frame, (round(w / 2 + sx * 2 - fw / 2), round(h / 2 + sy * 2 - fh / 2)))
    return canvas


def bnm_tinted(sprite):
    """The mod's look: the sprite multiplied by the uranium tint, plus an
    additive copy of itself as the glow layer."""
    r, g, b, a = sprite.split()
    tr, tg, tb = BNM_TINT
    rgb = Image.merge("RGB", (r.point(lambda v: int(v * tr)), g.point(lambda v: int(v * tg)),
                              b.point(lambda v: int(v * tb))))
    lit = ImageChops.add(rgb, rgb)
    out = Image.new("RGBA", sprite.size, (0, 0, 0, 0))
    out.paste(lit, (0, 0), a)
    return out


def close_up(inner):
    """The zoomed square of the tinted roboport, `inner` pixels wide."""
    sprite = bnm_tinted(roboport_sprite())
    cx, cy = sprite.width / 2 + ZOOM_CENTRE[0], sprite.height / 2 + ZOOM_CENTRE[1]
    half = ZOOM_SIZE / 2
    crop = sprite.crop((round(cx - half), round(cy - half), round(cx + half), round(cy + half)))
    flat = Image.new("RGB", crop.size, BG)
    flat.paste(crop, (0, 0), crop)
    big = flat.resize((inner, inner), Image.Resampling.LANCZOS)
    big = ImageEnhance.Color(big).enhance(BACKGROUND_SATURATION)
    big = ImageEnhance.Brightness(big).enhance(BACKGROUND_BRIGHTNESS)
    return big.filter(ImageFilter.GaussianBlur(BACKGROUND_BLUR))


def paste_background(card):
    inner_lo = FRAME_OUTER + FRAME_WIDTH
    inner = SIZE - 2 * inner_lo
    mask = Image.new("L", (inner, inner), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, inner - 1, inner - 1], radius=4, fill=255)
    card.paste(close_up(inner), (inner_lo, inner_lo), mask)


def draw_frame(card):
    far = SIZE - 1 - FRAME_OUTER
    ImageDraw.Draw(card).rounded_rectangle([FRAME_OUTER, FRAME_OUTER, far, far], radius=FRAME_RADIUS,
                                           outline=FRAME, width=FRAME_WIDTH)


def ink_box(text, font):
    """The inked box of `text` drawn at the origin: rendered and measured,
    since a font's reported box includes side bearings, not just ink."""
    pad = font.size
    mask = Image.new("L", (round(font.getlength(text)) + 2 * pad, 3 * pad), 0)
    ImageDraw.Draw(mask).text((pad, pad), text, font=font, fill=255)
    left, top, right, bottom = mask.getbbox()
    return left - pad, top - pad, right - pad, bottom - pad


def font_for_cap_height(text, height):
    """The font whose inked `text` is `height` pixels tall (binary search)."""
    lo, hi = height // 2, height * 3
    while lo < hi:
        size = (lo + hi) // 2
        _, top, _, bottom = ink_box(text, ImageFont.truetype(FONT, size))
        if bottom - top < height:
            lo = size + 1
        else:
            hi = size
    return ImageFont.truetype(FONT, lo)


def text_layer():
    """Both text layers on one transparent card-sized layer, each glyph placed
    by its inked box so the layout matches the previous card exactly."""
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    font = font_for_cap_height("BNM", LETTER_HEIGHT)
    for ch, color, left in LETTERS:
        x0, y0, _, _ = ink_box(ch, font)
        d.text((left - x0, LETTER_TOP - y0), ch, font=font, fill=color,
               stroke_width=LETTER_OUTLINE, stroke_fill=INK)
    left, top, right, bottom = SUBTITLE_BOX
    sub_font = font_for_cap_height(SUBTITLE, bottom - top)
    draw_tracked(d, SUBTITLE, sub_font, (left, top), right - left, SUBTITLE_FILL)
    return layer


def draw_tracked(d, text, font, at, width, fill):
    """`text` spread with even letter spacing so its ink spans `width`: from
    the first glyph's ink to the last glyph's, advances in between."""
    first_left, top = ink_box(text[0], font)[0], ink_box(text, font)[1]
    last_right = ink_box(text[-1], font)[2]
    advances = sum(d.textlength(ch, font=font) for ch in text[:-1])
    gap = (width - (advances + last_right - first_left)) / (len(text) - 1)
    x, y = at[0] - first_left, at[1] - top
    for ch in text:
        d.text((x, y), ch, font=font, fill=fill, stroke_width=SUBTITLE_OUTLINE, stroke_fill=INK)
        x += d.textlength(ch, font=font) + gap


def halo_for(layer):
    """A centred black halo from the layer's own shape: blurred, no offset."""
    alpha = layer.getchannel("A").filter(ImageFilter.GaussianBlur(HALO_RADIUS))
    alpha = alpha.point(lambda v: min(255, int(v * HALO_STRENGTH)))
    halo = Image.new("RGBA", layer.size, HALO + (0,))
    halo.putalpha(alpha)
    return halo


def darken_subtitle_band(card):
    """A dark band fading in behind the subtitle, inside the frame only."""
    top, bottom, peak = SUBTITLE_BAND
    lo, hi = FRAME_OUTER + FRAME_WIDTH, SIZE - FRAME_OUTER - FRAME_WIDTH
    band = Image.new("L", card.size, 0)
    d = ImageDraw.Draw(band)
    for y in range(top, min(bottom, hi)):
        t = (y - top) / (bottom - top)
        d.line([(lo, y), (hi - 1, y)], fill=round(peak * min(1.0, t * 2.2)))
    card.paste(Image.new("RGB", card.size, INK), (0, 0), band)


def build():
    card = Image.new("RGB", (SIZE, SIZE), BG)
    paste_background(card)
    darken_subtitle_band(card)
    draw_frame(card)
    text = text_layer()
    card = card.convert("RGBA")
    card.alpha_composite(halo_for(text))
    card.alpha_composite(text)
    return card.convert("RGB")


def main():
    root = Path(__file__).resolve().parent.parent
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "thumbnail.png"
    build().save(out, optimize=True)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
