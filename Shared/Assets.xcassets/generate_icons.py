#!/usr/bin/env python3
"""Generate a Rezka Player icon set for tvOS/iOS/macOS."""
from __future__ import annotations

import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.abspath(__file__))


def radial_gradient(size, inner, outer):
    w, h = size
    img = Image.new("RGB", (w, h), outer)
    cx, cy = w / 2, h / 2
    max_r = (cx ** 2 + cy ** 2) ** 0.5
    px = img.load()
    for y in range(h):
        for x in range(w):
            r = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            t = min(1.0, r / max_r)
            px[x, y] = (
                int(inner[0] * (1 - t) + outer[0] * t),
                int(inner[1] * (1 - t) + outer[1] * t),
                int(inner[2] * (1 - t) + outer[2] * t),
            )
    return img


def make_back(size):
    w, h = size
    img = radial_gradient(size, (90, 30, 160), (15, 10, 40)).convert("RGBA")
    overlay = Image.new("RGBA", size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.ellipse([(w * -0.2, h * -0.6), (w * 0.6, h * 0.4)], fill=(70, 150, 255, 70))
    od.ellipse([(w * 0.5, h * 0.5), (w * 1.3, h * 1.4)], fill=(255, 80, 180, 60))
    overlay = overlay.filter(ImageFilter.GaussianBlur(radius=max(w, h) * 0.08))
    return Image.alpha_composite(img, overlay)


def make_middle(size):
    w, h = size
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = w / 2, h / 2
    r = min(w, h) * 0.30
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, 35))
    r2 = min(w, h) * 0.22
    d.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], fill=(255, 255, 255, 60))
    img = img.filter(ImageFilter.GaussianBlur(radius=max(w, h) * 0.01))
    return img


def make_front(size):
    w, h = size
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = w / 2, h / 2
    side = min(w, h) * 0.32
    tri = [
        (cx - side * 0.45, cy - side * 0.55),
        (cx - side * 0.45, cy + side * 0.55),
        (cx + side * 0.62, cy),
    ]
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon(tri, fill=(0, 0, 0, 140))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=max(w, h) * 0.02))
    img.alpha_composite(shadow, dest=(int(max(w, h) * 0.01), int(max(w, h) * 0.02)))
    d.polygon(tri, fill=(255, 255, 255, 255))
    return img


def make_flat_icon(size):
    """Composite a flat icon (used for iOS/macOS where layering isn't available)."""
    back = make_back(size).convert("RGBA")
    mid = make_middle(size)
    front = make_front(size)
    out = back.copy()
    out.alpha_composite(mid)
    out.alpha_composite(front)
    return out


def make_top_shelf(size):
    """A wide hero strip used as Top Shelf image."""
    w, h = size
    base = radial_gradient(size, (90, 30, 160), (10, 10, 35)).convert("RGBA")
    overlay = Image.new("RGBA", size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.ellipse([(-w * 0.2, -h * 0.5), (w * 0.5, h * 0.6)], fill=(70, 150, 255, 80))
    od.ellipse([(w * 0.55, h * 0.3), (w * 1.3, h * 1.6)], fill=(255, 80, 180, 70))
    overlay = overlay.filter(ImageFilter.GaussianBlur(radius=max(w, h) * 0.06))
    out = Image.alpha_composite(base, overlay)
    front = make_front((int(h * 1.6), int(h * 1.6)))
    fw, fh = front.size
    out.alpha_composite(front, dest=(int(w * 0.07), int((h - fh) / 2)))
    return out


# --- tvOS layered icon (Brand Assets) ---
TVOS_SIZES = {  # (1x, 2x)
    "App Icon": (400, 240),
    "App Icon - App Store": (1280, 768),
}
TVOS_LAYERS = {
    "Back": (make_back, "back"),
    "Middle": (make_middle, "midle"),
    "Front": (make_front, "front"),
}


BRAND_BUNDLE = "App Icon & Top Shelf Image.brandassets"


def write_tvos_layer_contents(stack_name, layer_name, base_name):
    layer_dir = os.path.join(
        ROOT,
        BRAND_BUNDLE,
        f"{stack_name}.imagestack",
        f"{layer_name}.imagestacklayer",
        "Content.imageset",
    )
    os.makedirs(layer_dir, exist_ok=True)
    contents = (
        "{\n  \"images\" : [\n"
        f"    {{\n      \"filename\" : \"{base_name}.png\",\n      \"idiom\" : \"tv\",\n      \"scale\" : \"1x\"\n    }},\n"
        f"    {{\n      \"filename\" : \"{base_name}@2x.png\",\n      \"idiom\" : \"tv\",\n      \"scale\" : \"2x\"\n    }}\n"
        "  ],\n  \"info\" : {\n    \"author\" : \"xcode\",\n    \"version\" : 1\n  }\n}\n"
    )
    with open(os.path.join(layer_dir, "Contents.json"), "w") as f:
        f.write(contents)
    return layer_dir


def generate_tvos():
    for stack_name, (w1, h1) in TVOS_SIZES.items():
        for layer_name, (make_fn, base) in TVOS_LAYERS.items():
            layer_dir = write_tvos_layer_contents(stack_name, layer_name, base)
            img1 = make_fn((w1, h1))
            img2 = make_fn((w1 * 2, h1 * 2))
            img1.save(os.path.join(layer_dir, f"{base}.png"))
            img2.save(os.path.join(layer_dir, f"{base}@2x.png"))


def generate_top_shelf():
    target_dir = os.path.join(ROOT, BRAND_BUNDLE, "Top Shelf Image.imageset")
    os.makedirs(target_dir, exist_ok=True)
    make_top_shelf((1920, 720)).save(os.path.join(target_dir, "shelf.png"))
    wide_dir = os.path.join(ROOT, BRAND_BUNDLE, "Top Shelf Image Wide.imageset")
    if os.path.isdir(wide_dir):
        make_top_shelf((2320, 720)).save(os.path.join(wide_dir, "shelf.png"))


# --- iOS/macOS AppIcon (flat) ---
APPICON_SIZES = [
    ("icon.png", 1024),
    ("icon-16.png", 16),
    ("icon-16@2x.png", 32),
    ("icon-32.png", 32),
    ("icon-32@2x.png", 64),
    ("icon-128.png", 128),
    ("icon-128@2x.png", 256),
    ("icon-256.png", 256),
    ("icon-256@2x.png", 512),
    ("icon-512.png", 512),
    ("icon-512@2x.png", 1024),
]


def generate_appicon():
    target = os.path.join(ROOT, "AppIcon.appiconset")
    os.makedirs(target, exist_ok=True)
    master = make_flat_icon((1024, 1024))
    for filename, side in APPICON_SIZES:
        master.resize((side, side), Image.LANCZOS).save(os.path.join(target, filename))


if __name__ == "__main__":
    generate_tvos()
    generate_top_shelf()
    generate_appicon()
    print("Icons regenerated.")
