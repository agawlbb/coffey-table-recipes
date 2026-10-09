"""Regenerate launcher assets with Python and Pillow; run from any directory."""

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/branding/app_icon.png"


def main():
    with Image.open(SOURCE) as original:
        source = original.convert("RGB")
    if source.width != source.height:
        raise ValueError("The icon source must be square")
    targets = {}
    for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96,
                          "xxhdpi": 144, "xxxhdpi": 192}.items():
        targets[ROOT / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png"] = (size, False)
    ios = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for entry in json.loads((ios / "Contents.json").read_text())["images"]:
        size = round(float(entry["size"].split("x")[0]) * float(entry["scale"].rstrip("x")))
        targets[ios / entry["filename"]] = (size, False)
    targets[ROOT / "web/favicon.png"] = (32, False)
    for size in (192, 512):
        targets[ROOT / f"web/icons/Icon-{size}.png"] = (size, False)
        targets[ROOT / f"web/icons/Icon-maskable-{size}.png"] = (size, True)
    for path, (size, maskable) in targets.items():
        # Keep the entire square artwork inside the maskable icon's safe circle.
        artwork_size = int(size * 0.56) if maskable else size
        artwork = source.resize((artwork_size, artwork_size), Image.Resampling.LANCZOS)
        icon = Image.new("RGB", (size, size), "white")
        offset = (size - artwork_size) // 2
        icon.paste(artwork, (offset, offset))
        icon.save(path)
        with Image.open(path) as saved:
            saved.verify()
        with Image.open(path) as saved:
            assert saved.size == (size, size) and saved.mode == "RGB", path
    print(f"Generated and verified {len(targets)} Android, iOS, and web icons.")


if __name__ == "__main__":
    main()
