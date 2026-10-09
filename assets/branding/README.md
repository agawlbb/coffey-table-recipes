# App icon

`app_icon.png` is the approved pot, leaves, and coffee beans artwork supplied for
the app icon. It is kept separately from recipe photos and is not bundled as an
in-app image.

To regenerate Android launcher icons, the iOS AppIcon catalog, and web/PWA icons:

```sh
python -m pip install Pillow
python tools/generate_app_icons.py
```

The generator preserves the original artwork and produces opaque PNGs at each
platform's configured size. Web maskable icons include white padding to keep the
artwork within the central safe circle. The web favicon uses the same artwork.
