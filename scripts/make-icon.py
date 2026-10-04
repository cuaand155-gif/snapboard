"""Draws Snapboard's app icon (Resources/AppIcon.png, 1024x1024).
Re-run with: python3 scripts/make-icon.py   (needs Pillow)."""
from PIL import Image, ImageDraw, ImageFilter

S = 4                      # draw large, then shrink for smooth edges
N = 1024 * S
img = Image.new("RGBA", (N, N), (0, 0, 0, 0))

# macOS icon shape: a rounded square inside the canvas, with a soft shadow.
m, r = 100 * S, 185 * S
shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([m, m + 12 * S, N - m, N - m + 12 * S], r, fill=(0, 0, 0, 90))
img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18 * S)))

# Background: a diagonal indigo-to-teal gradient, clipped to the rounded square.
grad = Image.new("RGBA", (N, N))
top, bottom = (79, 70, 229), (20, 184, 166)
gp = grad.load()
for y in range(N):
    for x in range(0, N, 1):
        t = (x * 0.35 + y * 0.65) / N
        gp[x, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
mask = Image.new("L", (N, N), 0)
ImageDraw.Draw(mask).rounded_rectangle([m, m, N - m, N - m], r, fill=255)
img.paste(grad, (0, 0), mask)

d = ImageDraw.Draw(img)
# Three zones like the "big left, two right" layout; the top-right one is lit up, as if a
# window is about to snap into it.
inset, gap, zr = 190 * S, 34 * S, 46 * S
L, T, R, B = inset, inset, N - inset, N - inset
split = L + int((R - L) * 0.56)
mid = T + (B - T) // 2
white = (255, 255, 255, 235)
d.rounded_rectangle([L, T, split - gap // 2, B], zr, fill=white)
d.rounded_rectangle([split + gap // 2, mid + gap // 2, R, B], zr, fill=white)
d.rounded_rectangle([split + gap // 2, T, R, mid - gap // 2], zr, fill=(255, 214, 102, 255), outline=(255, 255, 255, 255), width=10 * S)

# A small "widget" dot in the big zone: the desktop-widgets half of the app.
cx, cy, cr = L + 120 * S, T + 120 * S, 52 * S
d.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=(79, 70, 229, 255))

img.resize((1024, 1024), Image.LANCZOS).save("Resources/AppIcon.png")
print("Wrote Resources/AppIcon.png")
