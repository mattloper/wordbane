"""Build a one-page review gallery for the style batch.

Scans ~/Desktop/wordplay_art_styles/<style>/<monster>.png and writes index.html +
gallery.css next to them, as a styles x monsters matrix.

    uv run python -m wordplay_art.gallery
"""
from __future__ import annotations

import html
import os

ROOT = os.path.expanduser("~/Desktop/wordplay_art_styles")
# Preferred monster order (anything else is appended alphabetically).
_PREFERRED = ["dragon", "goblin", "wolf"]


def _monsters(styles: list[str]) -> list[str]:
    found: set[str] = set()
    for s in styles:
        for f in os.listdir(os.path.join(ROOT, s)):
            if f.endswith(".png"):
                found.add(f[:-4])
    ordered = [m for m in _PREFERRED if m in found]
    ordered += sorted(m for m in found if m not in _PREFERRED)
    return ordered


def build() -> str:
    styles = sorted(
        d for d in os.listdir(ROOT)
        if os.path.isdir(os.path.join(ROOT, d)) and not d.startswith(".")
    )
    monsters = _monsters(styles)
    cells: list[str] = ['<div class="corner">style ╲ monster</div>']
    for m in monsters:
        cells.append(f'<div class="chead">{html.escape(m)}</div>')
    for s in styles:
        cells.append(f'<div class="rhead">{html.escape(s)}</div>')
        for m in monsters:
            rel = f"{s}/{m}.png"
            if os.path.exists(os.path.join(ROOT, rel)):
                cells.append(
                    f'<figure><a href="{rel}" target="_blank">'
                    f'<img loading="lazy" src="{rel}" alt="{html.escape(s)} {html.escape(m)}">'
                    f'</a></figure>'
                )
            else:
                cells.append('<figure class="missing">—</figure>')
    grid = "\n    ".join(cells)
    cols = len(monsters) + 1
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Wordplay — Monster Art Style Review</title>
<link rel="stylesheet" href="gallery.css">
</head>
<body>
<header>
  <h1>Wordplay — Monster Art Style Review</h1>
  <p>{len(styles)} styles × {len(monsters)} monsters. Same seed per monster, so only
  the <em>style</em> changes. Click any image for full size. Rows are styles — pick one.</p>
</header>
<main>
  <div class="grid" style="--cols: {cols}">
    {grid}
  </div>
</main>
</body>
</html>
"""


CSS = """:root { color-scheme: dark; }
* { box-sizing: border-box; }
body {
  margin: 0; padding: 24px;
  background: #14161d; color: #e7e9f0;
  font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
}
header { max-width: 1100px; margin: 0 auto 20px; }
h1 { font-size: 22px; margin: 0 0 6px; letter-spacing: .2px; }
header p { margin: 0; color: #9aa0b3; }
header em { color: #ffd24d; font-style: normal; }
main { max-width: 1400px; margin: 0 auto; }

.grid {
  display: grid;
  grid-template-columns: 120px repeat(calc(var(--cols) - 1), 1fr);
  gap: 10px;
  align-items: center;
}
.corner {
  font-size: 12px; color: #6b7186; text-align: right; padding-right: 8px;
}
.chead {
  text-align: center; font-weight: 600; text-transform: capitalize;
  color: #cfd3e0; padding-bottom: 4px;
}
.rhead {
  font-weight: 600; color: #ffd24d; font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 13px; text-align: right; padding-right: 8px; word-break: break-word;
}
figure {
  margin: 0; background: #1d2029; border: 1px solid #2b2f3c; border-radius: 10px;
  overflow: hidden; aspect-ratio: 1 / 1; display: flex;
}
figure.missing { align-items: center; justify-content: center; color: #565c70; }
figure a { display: block; width: 100%; height: 100%; }
figure img {
  width: 100%; height: 100%; object-fit: contain; display: block;
  transition: transform .15s ease;
  background:
    repeating-conic-gradient(#20242f 0% 25%, #191c25 0% 50%) 50% / 22px 22px;
}
figure img:hover { transform: scale(1.04); }
"""


def main() -> None:
    if not os.path.isdir(ROOT):
        raise SystemExit(f"no gallery dir at {ROOT}")
    with open(os.path.join(ROOT, "index.html"), "w") as f:
        f.write(build())
    with open(os.path.join(ROOT, "gallery.css"), "w") as f:
        f.write(CSS)
    print(f"wrote {ROOT}/index.html and gallery.css")


if __name__ == "__main__":
    main()
