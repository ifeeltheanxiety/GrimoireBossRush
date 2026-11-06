# Generates the placeholder cel-shaded art used by GRIMOIRE: BOSS RUSH.
# Every character part is exported on the SAME canvas as the rest of its character,
# so a replacement drawn by an artist only has to keep the canvas size and pivots.
import math, random, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

OUT = sys.argv[1] if len(sys.argv) > 1 else "Art"
os.makedirs(OUT, exist_ok=True)
SS = 3
random.seed(7)

def cr(pts, n=8, closed=True):
    """Catmull-Rom spline through pts -> smooth polygon."""
    out, L = [], len(pts)
    rng = range(L) if closed else range(L - 1)
    for i in rng:
        p0 = pts[(i - 1) % L] if closed else pts[max(i - 1, 0)]
        p1, p2 = pts[i], pts[(i + 1) % L]
        p3 = pts[(i + 2) % L] if closed else pts[min(i + 2, L - 1)]
        for t in np.linspace(0, 1, n, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in (0, 1)))
    return out

class Canvas:
    def __init__(s, w, h):
        s.w, s.h = w, h
        s.img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))

    def mask(s, shapes):
        m = Image.new("L", s.img.size, 0)
        d = ImageDraw.Draw(m)
        for sh in shapes:
            k = sh[0]
            if k == "p":
                d.polygon([(x * SS, y * SS) for x, y in sh[1]], fill=255)
            elif k == "s":
                d.polygon([(x * SS, y * SS) for x, y in cr(sh[1])], fill=255)
            elif k == "e":
                d.ellipse([v * SS for v in sh[1]], fill=255)
            elif k == "l":
                d.line([(x * SS, y * SS) for x, y in sh[1]], fill=255, width=int(sh[2] * SS), joint="curve")
        return m

    def part(s, shapes, c1, c2, rim=(150, 110, 255), rim_k=3, shade=0.5, outline=(6, 5, 12), ow=2, rim_a=230):
        m = s.mask(shapes)
        bb = m.getbbox()
        if not bb:
            return m
        W, H = s.img.size
        # outline
        if ow:
            o = m.filter(ImageFilter.MaxFilter(int(ow * SS) * 2 + 1))
            s.img.alpha_composite(Image.composite(Image.new("RGBA", (W, H), outline + (255,)), Image.new("RGBA", (W, H)), o))
        # vertical gradient fill
        y0, y1 = bb[1], bb[3]
        t = np.clip((np.arange(H) - y0) / max(1, y1 - y0), 0, 1)[:, None]
        g = np.zeros((H, W, 4), np.uint8)
        for j in range(3):
            g[..., j] = (c1[j] * (1 - t) + c2[j] * t).astype(np.uint8)
        g[..., 3] = 255
        fill = Image.fromarray(g, "RGBA")
        # cel shadow (lower-left band) and rim light (upper-right band)
        k = int(rim_k * SS * 2)
        sh = ImageChops.subtract(m, ImageChops.offset(m, k, -k)).filter(ImageFilter.GaussianBlur(SS * 0.6))
        dark = Image.eval(fill, lambda v: int(v * shade))
        fill = Image.composite(dark, fill, sh)
        if rim:
            rk = max(1, int(rim_k * SS * 0.7))
            rm = ImageChops.subtract(m, ImageChops.offset(m, -rk, rk)).filter(ImageFilter.GaussianBlur(SS * 0.4))
            rm = Image.eval(rm, lambda v: int(v * rim_a / 255))
            fill = Image.composite(Image.new("RGBA", (W, H), rim + (255,)), fill, rm)
        s.img.alpha_composite(Image.composite(fill, Image.new("RGBA", (W, H)), m))
        return m

    def glow(s, shapes, color, blur=10, a=1.0, core=True):
        m = s.mask(shapes)
        g = m.filter(ImageFilter.GaussianBlur(blur * SS))
        g = Image.eval(g, lambda v: min(255, int(v * a * 1.6)))
        s.img.alpha_composite(Image.composite(Image.new("RGBA", s.img.size, color + (255,)), Image.new("RGBA", s.img.size), g))
        if core:
            c = tuple(min(255, int(v * 0.5 + 128)) for v in color)
            s.img.alpha_composite(Image.composite(Image.new("RGBA", s.img.size, c + (255,)), Image.new("RGBA", s.img.size), m))

    def flat(s, shapes, color, a=255, blur=0):
        m = s.mask(shapes)
        if blur:
            m = m.filter(ImageFilter.GaussianBlur(blur * SS))
        m = Image.eval(m, lambda v: v * a // 255)
        s.img.alpha_composite(Image.composite(Image.new("RGBA", s.img.size, color + (255,)), Image.new("RGBA", s.img.size), m))

    def result(s):
        return s.img.resize((s.w, s.h), Image.LANCZOS)

    def save(s, name):
        s.result().save(f"{OUT}/{name}.png", optimize=True)

def poly_blade(h, d, length, w0, w1, start=0):
    nx, ny = -d[1], d[0]
    a = (h[0] + d[0] * start, h[1] + d[1] * start)
    b = (h[0] + d[0] * length, h[1] + d[1] * length)
    m = (h[0] + d[0] * (length - w1 * 3), h[1] + d[1] * (length - w1 * 3))
    return [(a[0] + nx * w0, a[1] + ny * w0), (m[0] + nx * w1, m[1] + ny * w1), b,
            (m[0] - nx * w1, m[1] - ny * w1), (a[0] - nx * w0, a[1] - ny * w0)]

def unit(x, y):
    l = math.hypot(x, y); return (x / l, y / l)

# ---------------------------------------------------------------- DANIEL (512x768, feet 262,740)
DW, DH = 512, 768
COAT = ((34, 32, 46), (10, 9, 16)); STEEL = ((70, 70, 92), (22, 22, 32)); SKIN = ((250, 230, 218), (222, 190, 182))
VOID = (160, 100, 255); TRIM = (170, 160, 210)

def daniel_cape():
    c = Canvas(DW, DH)
    c.part([("s", [(215, 228), (252, 232), (262, 300), (256, 450), (246, 600), (236, 700), (190, 718), (140, 708),
                   (100, 692), (128, 600), (160, 450), (186, 320)])], (30, 24, 44), (8, 6, 12), rim=(110, 80, 200), rim_k=3)
    c.part([("s", [(100, 692), (140, 708), (190, 718), (176, 690), (140, 676), (114, 660)])], (90, 30, 120), (40, 10, 60), rim=None, ow=1)
    c.part([("l", [(200, 300), (160, 520), (130, 660)], 2)], (60, 50, 90), (40, 30, 70), rim=None, ow=0)
    return c

def daniel_body():
    c = Canvas(DW, DH)
    c.part([("p", [(210, 245), (228, 250), (222, 330), (214, 400), (198, 398), (196, 330)])], *COAT)          # back arm
    c.part([("e", (190, 390, 220, 420))], *STEEL)
    c.part([("p", [(232, 545), (258, 545), (252, 650), (248, 700), (226, 702), (228, 650)])], *COAT)           # back leg
    c.part([("p", [(220, 688), (254, 688), (258, 738), (204, 740), (208, 720)])], *STEEL)
    c.part([("p", [(262, 545), (292, 545), (300, 640), (306, 700), (280, 702), (272, 640)])], *COAT)           # front leg
    c.part([("p", [(274, 686), (310, 686), (334, 738), (270, 740)])], *STEEL)
    c.part([("p", [(276, 640), (302, 636), (306, 662), (280, 666)])], *STEEL)                                  # knee guard
    c.part([("p", [(212, 410), (305, 410), (318, 480), (338, 578), (302, 560), (278, 594), (256, 562), (226, 588),
                   (194, 566), (204, 480)])], (36, 34, 50), (10, 9, 16), rim=(130, 100, 230))                 # coat skirt
    c.part([("l", [(258, 420), (258, 560)], 3)], TRIM, (90, 80, 130), rim=None, ow=0)
    c.part([("p", [(218, 232), (306, 232), (316, 300), (304, 415), (214, 415), (206, 300)])], *COAT)           # torso
    c.part([("p", [(230, 252), (296, 252), (302, 330), (262, 356), (222, 330)])], *STEEL, rim=(170, 150, 240))  # chest plate
    c.part([("p", [(210, 398), (310, 398), (312, 420), (208, 420)])], (52, 38, 40), (24, 16, 18), rim=None)    # belt
    c.part([("e", (250, 400, 270, 420))], TRIM, (90, 80, 120), rim=None, ow=1)
    c.part([("s", [(196, 236), (228, 226), (236, 262), (200, 274)])], *STEEL)                                  # back pauldron
    c.part([("p", [(250, 196), (276, 196), (278, 226), (248, 226)])], *SKIN, rim=None)                         # neck
    c.part([("p", [(228, 210), (294, 210), (304, 244), (262, 252), (220, 244)])], (40, 36, 54), (14, 12, 20), rim=(150, 120, 240))  # collar
    # grimoire emblem
    c.glow([("e", (238, 272, 286, 320))], VOID, blur=9, a=0.6, core=False)
    c.part([("e", (244, 278, 280, 314))], (30, 20, 50), (12, 8, 22), rim=None, outline=(190, 150, 255), ow=1.2)
    c.glow([("p", [(254, 286), (262, 290), (270, 286), (270, 306), (262, 302), (254, 306)])], VOID, blur=3, a=0.9)
    c.glow([("l", [(262, 290), (262, 302)], 1)], (230, 210, 255), blur=1, a=0.5)
    return c

def daniel_head(back=True):
    c = Canvas(DW, DH)
    c.part([("s", [(214, 110), (262, 80), (300, 100), (296, 170), (250, 200), (216, 182)])], (22, 22, 32), (8, 8, 14), rim=(110, 90, 210))
    c.part([("s", [(232, 120), (296, 112), (308, 150), (302, 180), (286, 200), (266, 206), (246, 196), (234, 170)])], *SKIN, rim=(255, 240, 250), shade=0.82)
    c.part([("e", (236, 146, 252, 174))], *SKIN, rim=None, shade=0.8, ow=1.2)
    # eyes
    c.part([("p", [(277, 148), (299, 145), (301, 155), (281, 158)])], (240, 238, 248), (200, 198, 215), rim=None, ow=1.2)
    c.part([("e", (284, 145, 295, 158))], (90, 80, 130), (30, 26, 50), rim=None, ow=0.6, outline=(10, 8, 20))
    c.flat([("e", (289, 147, 292, 150))], (255, 255, 255))
    c.part([("p", [(250, 149), (266, 148), (267, 156), (253, 157)])], (240, 238, 248), (200, 198, 215), rim=None, ow=1.2)
    c.part([("e", (257, 148, 265, 157))], (90, 80, 130), (30, 26, 50), rim=None, ow=0.6, outline=(10, 8, 20))
    c.part([("l", [(277, 143), (301, 137)], 2.6)], (20, 18, 28), (20, 18, 28), rim=None, ow=0)
    c.part([("l", [(249, 140), (267, 144)], 2.4)], (20, 18, 28), (20, 18, 28), rim=None, ow=0)
    c.part([("l", [(301, 162), (298, 169), (302, 170)], 1.2)], (190, 150, 150), (190, 150, 150), rim=None, ow=0)
    c.part([("l", [(282, 185), (293, 183)], 1.6)], (120, 70, 80), (120, 70, 80), rim=None, ow=0)
    # hair
    c.part([("p", [(226, 174), (216, 186), (214, 150), (200, 120), (222, 110), (212, 84), (240, 92), (244, 62), (266, 84),
                   (286, 60), (294, 88), (320, 80), (310, 104), (330, 114), (308, 122), (314, 140), (298, 124), (293, 142),
                   (282, 122), (274, 143), (264, 120), (254, 141), (246, 124), (238, 160)])],
           (40, 38, 56), (10, 10, 16), rim=(130, 110, 230), rim_k=2.5)
    c.part([("l", [(250, 90), (262, 110), (270, 118)], 1.5)], (80, 70, 120), (80, 70, 120), rim=None, ow=0)
    c.part([("l", [(286, 80), (290, 104)], 1.5)], (80, 70, 120), (80, 70, 120), rim=None, ow=0)
    return c

def daniel_eyes():
    c = Canvas(DW, DH)
    c.glow([("e", (284, 145, 295, 158)), ("e", (257, 148, 265, 157))], (190, 80, 255), blur=4, a=1.0)
    return c

def blade_dir():
    return unit(0.6, 0.8)

def daniel_arm():
    c = Canvas(DW, DH)
    c.part([("p", [(290, 240), (314, 244), (334, 320), (316, 328)])], *COAT)
    c.part([("p", [(316, 318), (336, 314), (354, 392), (334, 398)])], *COAT)
    c.part([("p", [(328, 380), (358, 376), (364, 410), (332, 414)])], *STEEL)
    c.part([("s", [(282, 232), (318, 224), (334, 252), (322, 280), (290, 272)])], *STEEL, rim=(180, 160, 250))
    h = (348, 398); d = blade_dir(); n = (-d[1], d[0])
    c.part([("p", poly_blade(h, (-d[0], -d[1]), 30, 5, 5))], (40, 30, 40), (20, 14, 20), rim=None)  # grip
    c.part([("e", (h[0] - d[0] * 34 - 7, h[1] - d[1] * 34 - 7, h[0] - d[0] * 34 + 7, h[1] - d[1] * 34 + 7))], *STEEL)
    g = (h[0] + d[0] * 10, h[1] + d[1] * 10)
    c.part([("p", [(g[0] + n[0] * 26, g[1] + n[1] * 26), (g[0] + n[0] * 26 + d[0] * 9, g[1] + n[1] * 26 + d[1] * 9),
                   (g[0] - n[0] * 26 + d[0] * 9, g[1] - n[1] * 26 + d[1] * 9), (g[0] - n[0] * 26, g[1] - n[1] * 26)])],
           (60, 50, 80), (20, 16, 30), rim=(190, 140, 255))
    c.part([("p", poly_blade(h, d, 235, 10, 9, start=18))], (28, 24, 38), (6, 5, 10), rim=VOID, rim_k=3, rim_a=255)
    a = (h[0] + d[0] * 30, h[1] + d[1] * 30); b = (h[0] + d[0] * 205, h[1] + d[1] * 205)
    c.glow([("l", [a, b], 1.4)], VOID, blur=2, a=0.7)
    c.part([("e", (334, 384, 362, 412))], *STEEL)  # fist over grip
    return c

def daniel_sword_glow():
    c = Canvas(DW, DH)
    h = (348, 398); d = blade_dir()
    c.glow([("p", poly_blade(h, d, 245, 16, 14, start=10))], (150, 60, 255), blur=12, a=0.9, core=False)
    c.glow([("p", poly_blade(h, d, 235, 6, 5, start=20))], (200, 140, 255), blur=3, a=0.6, core=False)
    return c

def daniel_wings():
    c = Canvas(DW, DH)
    L = [(244, 272), (176, 196), (100, 128), (26, 92), (58, 168), (16, 206), (70, 250), (26, 304), (92, 320), (70, 382), (150, 360), (222, 330)]
    R = [(282, 266), (346, 182), (424, 112), (496, 80), (470, 160), (506, 200), (452, 240), (498, 292), (432, 312), (452, 372), (372, 350), (302, 322)]
    for pts, bones in ((L, [(26, 92), (16, 206), (26, 304), (70, 382)]), (R, [(496, 80), (506, 200), (498, 292), (452, 372)])):
        c.glow([("p", pts)], (120, 40, 200), blur=10, a=0.5, core=False)
        c.part([("p", pts)], (50, 20, 70), (12, 6, 20), rim=(200, 120, 255), rim_k=3)
        for b in bones:
            c.part([("l", [pts[0], b], 3)], (90, 60, 130), (40, 20, 60), rim=None, ow=0)
    return c

# ---------------------------------------------------------------- DEMON KNIGHT (768x1024, feet 384,1000)
KW, KH = 768, 1024
ARM = ((54, 46, 52), (14, 11, 14)); RIM = (255, 80, 40); FIRE = (255, 110, 30)

def knight_body():
    c = Canvas(KW, KH)
    # tattered cape
    c.part([("p", [(300, 300), (420, 300), (430, 600), (400, 980), (360, 900), (330, 990), (290, 880), (250, 975), (230, 850),
                   (190, 940), (210, 620)])], (90, 16, 20), (24, 4, 6), rim=(255, 90, 60))
    # back arm
    c.part([("p", [(290, 320), (330, 330), (320, 470), (300, 560), (262, 556), (268, 460)])], *ARM, rim=RIM)
    c.part([("e", (252, 540, 306, 600))], *ARM, rim=RIM)
    # legs
    for x0 in (318, 400):
        c.part([("p", [(x0, 620), (x0 + 62, 620), (x0 + 58, 790), (x0 + 66, 990), (x0 - 12, 1000), (x0 + 2, 790)])], *ARM, rim=RIM)
        c.part([("p", [(x0 - 6, 770), (x0 + 66, 766), (x0 + 74, 830), (x0 + 30, 850), (x0 - 10, 830)])], (70, 60, 66), (20, 16, 20), rim=RIM)
        c.part([("p", [(x0 - 16, 950), (x0 + 74, 950), (x0 + 100, 1002), (x0 - 20, 1004)])], (60, 50, 56), (16, 12, 16), rim=RIM)
    # waist armor skirt
    c.part([("p", [(300, 540), (480, 540), (510, 680), (440, 650), (390, 700), (340, 650), (272, 680)])], *ARM, rim=RIM)
    # torso
    c.part([("p", [(290, 300), (490, 300), (512, 380), (470, 560), (310, 560), (270, 380)])], (62, 52, 60), (16, 12, 16), rim=RIM, rim_k=4)
    c.part([("p", [(330, 340), (450, 340), (440, 470), (390, 500), (340, 470)])], (40, 30, 36), (12, 8, 10), rim=(255, 120, 60))
    # molten cracks
    c.glow([("l", [(360, 360), (380, 420), (372, 470)], 2.5), ("l", [(420, 360), (404, 420), (412, 460)], 2.5),
            ("l", [(380, 420), (404, 420)], 2)], FIRE, blur=5, a=0.9)
    # back pauldron
    c.part([("p", [(250, 300), (330, 270), (350, 340), (280, 370), (238, 340), (220, 290)])], (70, 60, 66), (20, 16, 20), rim=RIM)
    # horns
    c.part([("s", [(366, 196), (330, 140), (300, 70), (316, 60), (350, 120), (392, 180)])], (180, 160, 140), (60, 40, 30), rim=(255, 200, 150))
    c.part([("s", [(420, 186), (470, 130), (510, 54), (524, 64), (496, 140), (440, 206)])], (180, 160, 140), (60, 40, 30), rim=(255, 200, 150))
    # helmet
    c.part([("s", [(352, 180), (420, 166), (462, 196), (466, 262), (440, 300), (400, 312), (360, 292), (346, 240)])], (70, 60, 68), (18, 14, 18), rim=RIM, rim_k=4)
    c.part([("p", [(380, 250), (468, 240), (470, 262), (446, 290), (400, 296)])], (36, 28, 32), (10, 8, 10), rim=None)  # jaw guard
    c.part([("p", [(392, 228), (470, 220), (466, 236), (394, 244)])], (6, 4, 6), (6, 4, 6), rim=None, ow=0)            # visor slit
    c.glow([("p", [(404, 232), (428, 229), (426, 238), (406, 240)]), ("p", [(440, 228), (462, 226), (460, 234), (442, 236)])],
           (255, 30, 20), blur=6, a=1.0)
    c.part([("l", [(410, 176), (412, 220)], 3)], (120, 40, 30), (60, 20, 16), rim=None, ow=0)
    return c

def knight_dir():
    return unit(0.55, 0.83)

def knight_arm():
    c = Canvas(KW, KH)
    c.part([("p", [(452, 310), (500, 316), (532, 450), (494, 462)])], *ARM, rim=RIM)
    c.part([("p", [(494, 446), (534, 438), (574, 560), (534, 572)])], *ARM, rim=RIM)
    h = (566, 580); d = knight_dir(); n = (-d[1], d[0])
    c.part([("p", poly_blade(h, (-d[0], -d[1]), 50, 8, 8))], (60, 30, 24), (30, 14, 10), rim=None)
    g = (h[0] + d[0] * 18, h[1] + d[1] * 18)
    c.part([("p", [(g[0] + n[0] * 50, g[1] + n[1] * 50 - 10), (g[0] + n[0] * 40 + d[0] * 16, g[1] + n[1] * 40 + d[1] * 16),
                   (g[0] - n[0] * 40 + d[0] * 16, g[1] - n[1] * 40 + d[1] * 16), (g[0] - n[0] * 50, g[1] - n[1] * 50 + 10)])],
           (110, 80, 60), (40, 24, 18), rim=(255, 180, 90))
    c.glow([("p", poly_blade(h, d, 310, 30, 24, start=30))], FIRE, blur=16, a=0.55, core=False)
    c.part([("p", poly_blade(h, d, 300, 22, 18, start=30))], (60, 30, 26), (20, 8, 6), rim=(255, 150, 40), rim_k=4, rim_a=255)
    for t in (80, 150, 220):
        p = (h[0] + d[0] * t, h[1] + d[1] * t)
        c.glow([("l", [(p[0] - n[0] * 10, p[1] - n[1] * 10), (p[0] + d[0] * 30 + n[0] * 6, p[1] + d[1] * 30 + n[1] * 6)], 2)], FIRE, blur=3, a=0.9)
    c.part([("e", (544, 556, 592, 604))], (80, 66, 70), (20, 14, 18), rim=RIM)
    c.part([("p", [(430, 300), (500, 270), (546, 310), (540, 360), (480, 376), (440, 352)]),
            ("p", [(470, 280), (488, 220), (500, 284)]), ("p", [(510, 290), (548, 240), (530, 306)])], (80, 68, 74), (22, 16, 20), rim=RIM, rim_k=4)
    return c

# ---------------------------------------------------------------- BACKGROUNDS
def sky(w, h, top, mid, bottom, horizon):
    y = np.arange(h)[:, None] / h
    img = np.zeros((h, w, 3), np.float32)
    for j in range(3):
        a = np.where(y < horizon, top[j] + (mid[j] - top[j]) * (y / horizon), mid[j] + (bottom[j] - mid[j]) * ((y - horizon) / (1 - horizon)))
        img[..., j] = np.broadcast_to(a, (h, w))
    return img

def add_glow(img, cx, cy, r, color, power=2.0, amt=1.0):
    h, w, _ = img.shape
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
    g = np.clip(1 - d, 0, 1) ** power * amt
    for j in range(3):
        img[..., j] += g * color[j]

def noise(w, h, scale, octaves=4, seed=0):
    rs = np.random.RandomState(seed)
    out = np.zeros((h, w), np.float32); amp = 1.0; tot = 0
    for o in range(octaves):
        s = max(2, int(scale * 2 ** o))
        small = rs.rand(max(2, h * s // w + 2), s + 2).astype(np.float32)
        big = np.array(Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), np.float32) / 255
        out += big * amp; tot += amp; amp *= 0.5
    return out / tot

def silhouette(w, h, base, rough, spires, seed, color):
    rs = np.random.RandomState(seed)
    m = Image.new("L", (w, h), 0); d = ImageDraw.Draw(m)
    xs = np.linspace(0, w, 60)
    pts = [(x, base - rs.rand() * rough) for x in xs]
    d.polygon([(0, h)] + pts + [(w, h)], fill=255)
    for _ in range(spires):
        x = rs.rand() * w; bw = 18 + rs.rand() * 50; th = 80 + rs.rand() * 260
        d.rectangle([x - bw / 2, base - th, x + bw / 2, base + 10], fill=255)
        d.polygon([(x - bw / 2 - 6, base - th), (x, base - th - bw * 1.8), (x + bw / 2 + 6, base - th)], fill=255)
        if rs.rand() < 0.5:
            d.rectangle([x + bw / 2, base - th * 0.6, x + bw / 2 + bw * 0.8, base], fill=255)
            d.polygon([(x + bw / 2 - 4, base - th * 0.6), (x + bw * 0.9, base - th * 0.6 - bw * 1.4), (x + bw * 1.3 + 4, base - th * 0.6)], fill=255)
    a = np.array(m, np.float32)[..., None] / 255
    return a, np.array(color, np.float32)

def arena_bg(name, pal, moon):
    w, h = 1792, 828
    img = sky(w, h, pal["top"], pal["mid"], pal["bot"], 0.52)
    n = noise(w, h, 6, 5, 1)
    img += (n[..., None] - 0.5) * 40 * np.array(pal["cloud"]) / 255
    add_glow(img, moon[0], moon[1], 420, pal["moonglow"], 2.2, 1.0)
    yy, xx = np.mgrid[0:h, 0:w]
    md = np.sqrt((xx - moon[0]) ** 2 + (yy - moon[1]) ** 2)
    disk = np.clip((moon[2] - md) / 2, 0, 1)
    tex = noise(w, h, 30, 3, 9)
    for j in range(3):
        img[..., j] = img[..., j] * (1 - disk) + disk * (pal["moon"][j] * (0.8 + 0.3 * tex))
    for i, (base, rough, sp, col, fog) in enumerate(pal["layers"]):
        a, c = silhouette(w, h, base, rough, sp, 10 + i, col)
        img = img * (1 - a) + c * a
        fy = np.clip(1 - np.abs(yy - base) / 120, 0, 1)[..., None] * fog
        img += fy * np.array(pal["fog"], np.float32)
    # floor
    fl = int(h * 0.56)
    f = np.zeros((h - fl, w, 3), np.float32)
    ty = np.arange(h - fl)[:, None] / (h - fl)
    for j in range(3):
        f[..., j] = pal["floor"][j] * (0.55 + 0.6 * ty)
    fn = noise(w, h - fl, 18, 4, 3)
    f *= (0.75 + 0.5 * fn[..., None])
    # perspective tiles
    fi = Image.fromarray(np.clip(f, 0, 255).astype(np.uint8)); d = ImageDraw.Draw(fi)
    vx = w / 2
    for k in range(-14, 15):
        d.line([(vx + k * 40, 0), (vx + k * 260, h - fl)], fill=tuple(int(v * 0.45) for v in pal["floor"]), width=3)
    yv = 0.0
    for k in range(9):
        yv = (h - fl) * (k / 8) ** 1.7
        d.line([(0, yv), (w, yv)], fill=tuple(int(v * 0.45) for v in pal["floor"]), width=2 + k // 3)
    f = np.array(fi, np.float32)
    img[fl:] = f
    # glowing cracks
    cr_img = Image.new("L", (w, h), 0); d = ImageDraw.Draw(cr_img); rs = np.random.RandomState(4)
    for _ in range(14):
        x, y = rs.rand() * w, fl + 20 + rs.rand() * (h - fl - 20)
        pts = [(x, y)]
        for _ in range(6):
            x += rs.randn() * 40 + 30; y += rs.randn() * 10
            pts.append((x, y))
        d.line(pts, fill=255, width=3)
    cg = np.array(cr_img.filter(ImageFilter.GaussianBlur(6)), np.float32)[..., None] / 255
    cc = np.array(cr_img, np.float32)[..., None] / 255
    img += cg * np.array(pal["crack"]) * 1.4 + cc * np.array(pal["crack"]) * 0.8
    # horizon fog + vignette
    img += np.clip(1 - np.abs(yy - fl) / 90, 0, 1)[..., None] * np.array(pal["fog"], np.float32) * 0.9
    v = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2)
    img *= np.clip(1.25 - 0.55 * v, 0.25, 1)[..., None]
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(f"{OUT}/{name}.png", optimize=True)

# ---------------------------------------------------------------- FX + UI
def radial(name, size, color, power=2.0, ring=None):
    yy, xx = np.mgrid[0:size, 0:size]
    d = np.sqrt((xx - size / 2) ** 2 + (yy - size / 2) ** 2) / (size / 2)
    a = np.clip(1 - d, 0, 1) ** power if ring is None else np.clip(1 - np.abs(d - ring[0]) / ring[1], 0, 1) ** power
    im = np.zeros((size, size, 4), np.uint8)
    im[..., :3] = color; im[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(im, "RGBA").save(f"{OUT}/{name}.png")

def fx_slash():
    c = Canvas(512, 256)
    outer = [(30 + 450 * t, 200 - math.sin(t * math.pi) * 170) for t in np.linspace(0, 1, 40)]
    inner = [(30 + 450 * t, 200 - math.sin(t * math.pi) * 120 * (0.2 + 0.8 * math.sin(t * math.pi))) for t in np.linspace(1, 0, 40)]
    c.glow([("p", outer + inner)], (255, 255, 255), blur=8, a=0.8, core=False)
    c.flat([("p", outer + inner)], (255, 255, 255), a=230, blur=1.5)
    c.save("fx_slash")

def fx_orb():
    s = 256; yy, xx = np.mgrid[0:s, 0:s]; cx = s / 2
    d = np.sqrt((xx - cx) ** 2 + (yy - cx) ** 2) / (s / 2)
    ang = np.arctan2(yy - cx, xx - cx)
    swirl = 0.5 + 0.5 * np.sin(ang * 3 + d * 14)
    disk = np.clip(1 - np.abs(d - 0.55) / 0.35, 0, 1) ** 1.5 * (0.5 + 0.5 * swirl)
    core = np.clip((0.4 - d) / 0.03, 0, 1)
    im = np.zeros((s, s, 4), np.float32)
    col = np.array([170, 90, 255]); hot = np.array([255, 220, 255])
    for j in range(3):
        im[..., j] = col[j] * disk + hot[j] * np.clip(1 - np.abs(d - 0.42) / 0.04, 0, 1)
    im[..., :3] *= (1 - core[..., None])
    im[..., 3] = np.clip(disk * 255 + core * 255 + np.clip(1 - np.abs(d - 0.42) / 0.04, 0, 1) * 255, 0, 255)
    Image.fromarray(np.clip(im, 0, 255).astype(np.uint8), "RGBA").save(f"{OUT}/fx_orb.png")

def fx_vortex():
    s = 512; yy, xx = np.mgrid[0:s, 0:s]; cx = s / 2
    d = np.sqrt((xx - cx) ** 2 + (yy - cx) ** 2) / (s / 2)
    ang = np.arctan2(yy - cx, xx - cx)
    arms = (0.5 + 0.5 * np.sin(ang * 4 - np.log(d + 0.05) * 6)) ** 3
    a = arms * np.clip(1 - d, 0, 1) ** 0.8 * np.clip(d / 0.15, 0, 1)
    im = np.zeros((s, s, 4), np.float32)
    im[..., 0] = 150 + 100 * arms; im[..., 1] = 60 + 80 * arms ** 2; im[..., 2] = 255
    im[..., 3] = np.clip(a * 300, 0, 255)
    Image.fromarray(im.astype(np.uint8), "RGBA").save(f"{OUT}/fx_vortex.png")

def fx_flame():
    w, h = 256, 160; c = Canvas(w, h)
    for i in range(7):
        x = 40 + i * 28; ht = 60 + random.random() * 80
        pts = [(x - 26, 150), (x - 10, 150 - ht * 0.5), (x + 4, 150 - ht), (x + 16, 150 - ht * 0.45), (x + 30, 150)]
        c.glow([("s", pts)], (255, 100, 20), blur=8, a=0.6, core=False)
        c.flat([("s", pts)], (255, 150, 40), a=220)
        c.flat([("s", [(x - 10, 150), (x, 150 - ht * 0.5), (x + 12, 150)])], (255, 240, 180), a=230)
    c.save("fx_flame")

def fx_star():
    c = Canvas(256, 256)
    pts = []
    for i in range(16):
        r = 120 if i % 2 == 0 else 22
        if i % 4 == 2: r = 70
        a = i / 16 * math.tau
        pts.append((128 + math.cos(a) * r, 128 + math.sin(a) * r))
    c.glow([("p", pts)], (255, 255, 255), blur=6, a=0.8)
    c.save("fx_star")

def fx_smoke():
    s = 128; n = noise(s, s, 3, 4, 21)
    yy, xx = np.mgrid[0:s, 0:s]
    d = np.sqrt((xx - s / 2) ** 2 + (yy - s / 2) ** 2) / (s / 2)
    a = np.clip(1 - d, 0, 1) ** 1.5 * (0.4 + n)
    im = np.zeros((s, s, 4), np.uint8); im[..., :3] = 255; im[..., 3] = np.clip(a * 200, 0, 255).astype(np.uint8)
    Image.fromarray(im, "RGBA").save(f"{OUT}/fx_smoke.png")

def ui_button(name, icon, ring=(190, 160, 255), core=((40, 26, 64), (10, 6, 18)), size=256):
    c = Canvas(size, size); m = size / 2
    c.glow([("e", (16, 16, size - 16, size - 16))], ring, blur=8, a=0.35, core=False)
    c.part([("e", (14, 14, size - 14, size - 14))], (210, 200, 240), (70, 60, 100), rim=(255, 255, 255), outline=(10, 6, 18), ow=2)
    c.part([("e", (30, 30, size - 30, size - 30))], *core, rim=None, shade=0.7, ow=1.5, outline=(120, 100, 170))
    for i in range(8):
        a = i / 8 * math.tau
        p = (m + math.cos(a) * (m - 22), m + math.sin(a) * (m - 22))
        c.part([("p", [(p[0] + math.cos(a) * 9, p[1] + math.sin(a) * 9), (p[0] + math.cos(a + 1.57) * 5, p[1] + math.sin(a + 1.57) * 5),
                       (p[0] - math.cos(a) * 6, p[1] - math.sin(a) * 6), (p[0] - math.cos(a + 1.57) * 5, p[1] - math.sin(a + 1.57) * 5)])],
               (250, 240, 255), (150, 130, 200), rim=None, ow=0.8)
    icon(c, m)
    c.save(name)

def ic_sword(c, m, col=(200, 160, 255)):
    d = unit(1, -1); h = (m - 44, m + 44)
    c.glow([("p", poly_blade(h, d, 130, 9, 8, start=8))], col, blur=6, a=0.8)
    c.part([("p", poly_blade(h, d, 128, 8, 7, start=8))], (60, 50, 90), (16, 12, 26), rim=col, ow=1.5, rim_a=255)
    n = (-d[1], d[0]); g = (h[0] + d[0] * 6, h[1] + d[1] * 6)
    c.part([("l", [(g[0] + n[0] * 24, g[1] + n[1] * 24), (g[0] - n[0] * 24, g[1] - n[1] * 24)], 7)], (220, 200, 255), (100, 80, 150), rim=None, ow=1)
    c.part([("l", [h, (h[0] - d[0] * 26, h[1] - d[1] * 26)], 6)], (90, 60, 60), (40, 20, 20), rim=None, ow=1)

def ic_slash(c, m):
    outer = [(m - 60 + 120 * t, m + 40 - math.sin(t * math.pi) * 90) for t in np.linspace(0, 1, 30)]
    inner = [(m - 60 + 120 * t, m + 40 - math.sin(t * math.pi) * 50) for t in np.linspace(1, 0, 30)]
    c.glow([("p", outer + inner)], (170, 90, 255), blur=6, a=1.0)
    c.flat([("p", outer[5:25] + inner[5:25])], (255, 255, 255), a=200)

def ic_hole(c, m):
    c.glow([("e", (m - 64, m - 30, m + 64, m + 30))], (170, 80, 255), blur=6, a=1.0)
    c.part([("e", (m - 36, m - 36, m + 36, m + 36))], (6, 2, 12), (0, 0, 0), rim=(220, 160, 255), outline=(200, 140, 255), ow=1.5)

def ic_storm(c, m):
    pts = [(m + math.cos(t) * t * 6.5, m + math.sin(t) * t * 6.5) for t in np.linspace(0.5, 11, 80)]
    c.glow([("l", pts, 7)], (160, 80, 255), blur=5, a=1.0)
    c.flat([("l", pts, 3)], (240, 220, 255))

def ic_dodge(c, m):
    for k, a in ((0, 255), (34, 140)):
        pts = [(m - 30 - k, m - 50), (m + 20 - k, m), (m - 30 - k, m + 50), (m - 10 - k, m), ]
        c.glow([("p", pts)], (120, 200, 255), blur=5, a=0.8 * a / 255)
    c.flat([("p", [(m - 30, m - 50), (m + 20, m), (m - 30, m + 50), (m - 10, m)])], (230, 245, 255), a=220)

def ic_demon(c, m):
    c.glow([("p", [(m - 60, m), (m, m - 34), (m + 60, m), (m, m + 34)])], (200, 40, 255), blur=7, a=1.0, core=False)
    c.part([("p", [(m - 58, m), (m - 20, m - 30), (m + 20, m - 30), (m + 58, m), (m + 20, m + 30), (m - 20, m + 30)])], (240, 220, 255), (170, 140, 210), rim=None, ow=1.5)
    c.glow([("e", (m - 18, m - 28, m + 18, m + 28))], (180, 30, 255), blur=3, a=1.0)
    c.flat([("e", (m - 4, m - 24, m + 4, m + 24))], (20, 0, 30))
    c.part([("p", [(m - 50, m - 40), (m - 76, m - 96), (m - 30, m - 50)]), ("p", [(m + 50, m - 40), (m + 76, m - 96), (m + 30, m - 50)])], (220, 210, 240), (90, 70, 120), rim=None, ow=1.2)

def ui_bar_frame():
    c = Canvas(1024, 80)
    c.part([("p", [(30, 14), (994, 14), (1018, 40), (994, 66), (30, 66), (6, 40)])], (200, 190, 230), (70, 60, 100), rim=(255, 255, 255), ow=2)
    c.part([("p", [(40, 22), (984, 22), (1000, 40), (984, 58), (40, 58), (24, 40)])], (16, 10, 24), (4, 2, 8), rim=None, ow=0)
    c.save("ui_bar_frame")

def ui_bar_fill(name, c1, c2):
    w, h = 512, 36
    t = np.arange(h)[:, None] / h
    im = np.zeros((h, w, 4), np.float32)
    for j in range(3):
        im[..., j] = c1[j] * (1 - t) + c2[j] * t
    im[: h // 3, :, :3] = im[: h // 3, :, :3] * 0.6 + 255 * 0.4 * (1 - t[: h // 3, :, None] * 3)
    im[..., 3] = 255
    Image.fromarray(np.clip(im, 0, 255).astype(np.uint8), "RGBA").save(f"{OUT}/{name}.png")

def ui_panel():
    c = Canvas(720, 140)
    c.glow([("p", [(40, 20), (680, 20), (710, 70), (680, 120), (40, 120), (10, 70)])], (150, 80, 255), blur=8, a=0.3, core=False)
    c.part([("p", [(40, 20), (680, 20), (710, 70), (680, 120), (40, 120), (10, 70)])], (200, 190, 230), (80, 70, 110), rim=(255, 255, 255), ow=2)
    c.part([("p", [(50, 30), (670, 30), (694, 70), (670, 110), (50, 110), (26, 70)])], (40, 26, 62), (8, 4, 16), rim=(110, 70, 200), ow=1)
    for x in (26, 694):
        c.glow([("p", [(x - 8, 70), (x, 60), (x + 8, 70), (x, 80)])], (200, 150, 255), blur=3, a=1)
    c.save("ui_panel")

def ui_joy():
    c = Canvas(320, 320)
    c.part([("e", (20, 20, 300, 300))], (40, 30, 60), (10, 6, 18), rim=(160, 120, 255), outline=(190, 170, 240), ow=2)
    c.part([("e", (60, 60, 260, 260))], (24, 16, 36), (12, 8, 20), rim=None, ow=1, outline=(90, 70, 140))
    for i in range(4):
        a = i * math.pi / 2; p = (160 + math.cos(a) * 118, 160 + math.sin(a) * 118)
        c.flat([("p", [(p[0] + math.cos(a) * 10, p[1] + math.sin(a) * 10), (p[0] + math.cos(a + 1.6) * 9, p[1] + math.sin(a + 1.6) * 9),
                       (p[0] + math.cos(a - 1.6) * 9, p[1] + math.sin(a - 1.6) * 9)])], (200, 170, 255))
    c.save("ui_joy_base")
    k = Canvas(160, 160)
    k.glow([("e", (16, 16, 144, 144))], (150, 80, 255), blur=8, a=0.5, core=False)
    k.part([("e", (20, 20, 140, 140))], (210, 200, 240), (80, 66, 120), rim=(255, 255, 255), ow=2)
    k.part([("e", (44, 44, 116, 116))], (70, 40, 120), (20, 10, 40), rim=None, ow=1)
    k.save("ui_joy_knob")

def ui_shade():
    radial("ui_shade", 256, (0, 0, 0), power=0.05)

def compose(name, files, w, h):
    base = Image.new("RGBA", (w, h))
    for f in files:
        base.alpha_composite(Image.open(f"{OUT}/{f}.png"))
    base.save(f"{OUT}/{name}.png", optimize=True)

def icon():
    bg = Image.open(f"{OUT}/bg_menu.png").convert("RGBA")
    s = 1024; bg = bg.crop((300, 0, 300 + 828, 828)).resize((s, s))
    d = Image.open(f"{OUT}/daniel_full.png").crop((90, 40, 470, 420)).resize((s, s), Image.LANCZOS)
    bg.alpha_composite(d)
    bg.convert("RGB").save(sys.argv[2] if len(sys.argv) > 2 else f"{OUT}/icon.png")

if __name__ == "__main__":
  SKIP = os.environ.get("SKIP_CHARS") == "1"
  if True:
    for fn, nm in ((daniel_cape, "daniel_cape"), (daniel_body, "daniel_body"), (daniel_head, "daniel_head"), (daniel_eyes, "daniel_eyes"),
                   (daniel_arm, "daniel_arm"), (daniel_sword_glow, "daniel_sword_glow"), (daniel_wings, "daniel_wings"),
                   (knight_body, "knight_body"), (knight_arm, "knight_arm")):
        if not SKIP: fn().save(nm); print(nm)
    compose("daniel_full", ["daniel_cape", "daniel_body", "daniel_head", "daniel_sword_glow", "daniel_arm"], DW, DH)
    compose("knight_full", ["knight_body", "knight_arm"], KW, KH)
    arena_bg("bg_arena", dict(top=(8, 4, 16), mid=(90, 22, 40), bot=(30, 8, 16), cloud=(255, 80, 60), moonglow=(140, 30, 30),
                              moon=(255, 150, 120), fog=(120, 40, 50), floor=(70, 52, 60), crack=(255, 90, 30),
                              layers=[(420, 30, 14, (40, 14, 24), 0.25), (450, 20, 10, (22, 8, 14), 0.3), (470, 10, 6, (10, 4, 8), 0.2)]),
             (1240, 210, 120))
    arena_bg("bg_menu", dict(top=(4, 4, 14), mid=(50, 26, 90), bot=(14, 8, 26), cloud=(140, 90, 255), moonglow=(90, 50, 170),
                             moon=(230, 220, 255), fog=(70, 40, 130), floor=(40, 36, 60), crack=(160, 80, 255),
                             layers=[(400, 40, 12, (26, 18, 50), 0.3), (440, 20, 9, (14, 10, 30), 0.3), (465, 10, 5, (6, 4, 14), 0.2)]),
             (1350, 230, 140))
    fx_slash(); fx_orb(); fx_vortex(); fx_flame(); fx_star(); fx_smoke()
    radial("fx_spark", 64, (255, 255, 255), 1.6)
    radial("fx_glow", 256, (255, 255, 255), 2.2)
    radial("fx_ring", 256, (255, 255, 255), 1.5, ring=(0.85, 0.12))
    radial("fx_shadow", 128, (0, 0, 0), 1.2)
    ui_button("btn_attack", ic_sword, ring=(255, 200, 255))
    ui_button("btn_slash", ic_slash); ui_button("btn_hole", ic_hole); ui_button("btn_storm", ic_storm)
    ui_button("btn_dodge", ic_dodge, ring=(140, 200, 255), core=((20, 34, 60), (6, 10, 20)))
    ui_button("btn_demon", ic_demon, ring=(220, 60, 255), core=((60, 10, 70), (14, 2, 18)))
    ui_bar_frame(); ui_panel(); ui_joy(); ui_shade()
    ui_bar_fill("ui_fill_hp", (120, 255, 160), (20, 140, 70))
    ui_bar_fill("ui_fill_mana", (120, 170, 255), (40, 60, 200))
    ui_bar_fill("ui_fill_rage", (230, 140, 255), (120, 20, 200))
    ui_bar_fill("ui_fill_boss", (255, 90, 70), (150, 10, 20))
    ui_bar_fill("ui_fill_white", (255, 255, 255), (220, 220, 230))
    icon()
    print("done")
