"""Patch the Tajawal fonts the app's PDFs use (flutter_app/assets/fonts).

The Dart `pdf` package shapes Arabic itself, and two of its habits broke
the app's printed reports (2026-10-31, "النص غير دقيق" on the payments
report):

1. It writes isolated letters as Arabic Presentation Forms-B code points
   (U+FE83 for an isolated "أ", ...). Tajawal has no cmap entries for most
   of them, so they came out with zero width and the next letter was drawn
   over them ("أجور" printed as a broken glyph). Each missing isolated form
   is mapped to its base letter's glyph.

2. In right-to-left text it places each word by its ink box rather than its
   advance width, so words whose edge letters overhang or sit in from their
   advance (final "ر", "د", ...) ate the space between words ("دينارعراقي").
   Every spacing glyph's header box is set to 0..advance with a left
   bearing of 0; the outlines are untouched, so viewers draw the same shapes.

Idempotent. Run with fontTools installed:  python3 scripts/patch_pdf_fonts.py
"""
import unicodedata
from pathlib import Path

from fontTools.ttLib import TTFont

FONTS = Path(__file__).resolve().parent.parent / 'flutter_app' / 'assets' / 'fonts'

for path in sorted(FONTS.glob('Tajawal-*.ttf')):
    font = TTFont(path, recalcBBoxes=False)
    cmap = font.getBestCmap()

    added = {}
    for code in range(0xFE70, 0xFEFD):
        parts = unicodedata.decomposition(chr(code)).split()
        if code in cmap or len(parts) != 2 or parts[0] != '<isolated>':
            continue
        base = int(parts[1], 16)
        if base in cmap:
            added[code] = cmap[base]
    for table in font['cmap'].tables:
        if table.isUnicode():
            table.cmap.update(added)

    glyf, hmtx = font['glyf'], font['hmtx']
    for name in font.getGlyphOrder():
        glyph = glyf[name]
        advance, _ = hmtx[name]
        # Marks (zero advance) keep their real box.
        if not glyph.numberOfContours or advance == 0:
            continue
        glyph.xMin, glyph.xMax = 0, advance
        hmtx[name] = (advance, 0)

    font.save(path)
    print(f'{path.name}: {len(added)} isolated forms mapped')
