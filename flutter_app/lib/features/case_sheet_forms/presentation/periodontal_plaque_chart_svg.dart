/// Periodontal's "Plaque Index" per-visit dental chart — the print-side
/// vector art, matching the anatomical shapes
/// `dental_clinics2/doctor/periodontal_chart_print_html.php`'s own
/// `createToothSVG()` draws (same source
/// `resources/views/print/partials/periodontal-plaque-chart.blade.php`
/// copies for the web side, so both surfaces draw the identical shapes).
library;

/// One tooth's outline, in a 0–40 box — copied verbatim from the
/// original's own `toothShapes`, and from `App\Support\PlaqueChart::TOOTH_SHAPES`.
const kPlaqueToothShapes = {
  'molar': 'M 5,10 Q 20,0 35,10 Q 40,20 35,35 Q 20,40 5,35 Q 0,20 5,10 Z',
  'premolar': 'M 5,10 Q 20,2 35,10 Q 38,25 30,35 Q 20,38 10,35 Q 2,25 5,10 Z',
  'canine': 'M 5,15 L 20,2 L 35,15 L 30,35 L 10,35 Z',
  'incisorUpper': 'M 0,0 L 40,0 L 34,40 L 6,40 Z',
  'incisorLower': 'M 5,2 L 35,2 L 32,38 L 8,38 Z',
};

/// FDI tooth number => shape key, left-to-right per arch — matches
/// `App\Support\PlaqueChart::UPPER_TEETH`/`LOWER_TEETH` exactly.
const kPlaqueUpperTeeth = <int, String>{
  18: 'molar', 17: 'molar', 16: 'molar',
  15: 'premolar', 14: 'premolar',
  13: 'canine',
  12: 'incisorUpper', 11: 'incisorUpper', 21: 'incisorUpper', 22: 'incisorUpper',
  23: 'canine',
  24: 'premolar', 25: 'premolar',
  26: 'molar', 27: 'molar', 28: 'molar',
};

const kPlaqueLowerTeeth = <int, String>{
  48: 'molar', 47: 'molar', 46: 'molar',
  45: 'premolar', 44: 'premolar',
  43: 'canine',
  42: 'incisorLower', 41: 'incisorLower', 31: 'incisorLower', 32: 'incisorLower',
  33: 'canine',
  34: 'premolar', 35: 'premolar',
  36: 'molar', 37: 'molar', 38: 'molar',
};

/// The 4 quadrant sectors, as triangles fanning out from the tooth's
/// centre (20,20) in a 0–40 box — the same `quadrants` array the
/// original's `createToothSVG()` builds, and the same points the web
/// Blade partial's `$sectorPoints` uses.
const kPlaqueSectorPoints = {
  'buccal': '0,0 40,0 20,20',
  'distal': '40,0 40,40 20,20',
  'lingual': '40,40 0,40 20,20',
  'mesial': '0,40 0,0 20,20',
};

/// One tooth's self-contained SVG, ready for `pw.SvgImage(svg: ...)` — a
/// clipped set of coloured quadrant triangles under the tooth's real
/// curved outline, the tooth number, and a red X overlay when extracted.
/// `surfaces` uses this app's plain `buccal`/`distal`/`lingual`/`mesial`
/// keys — already resolved server-side (the `palatal` legacy-key fallback
/// lives in `App\Support\PlaqueChart::visitData()`, so this never needs
/// to know about it).
String buildPlaqueToothSvg(int toothId, String type, {required bool extracted, required Map<String, bool> surfaces}) {
  final pathData = kPlaqueToothShapes[type] ?? kPlaqueToothShapes['molar']!;
  final clipId = 'plaque-clip-$toothId';

  final buffer = StringBuffer()
    ..write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40">')
    ..write('<defs><clipPath id="$clipId"><path d="$pathData"/></clipPath></defs>')
    ..write('<g clip-path="url(#$clipId)">');

  for (final entry in kPlaqueSectorPoints.entries) {
    final marked = !extracted && (surfaces[entry.key] ?? false);
    final fill = marked ? '#4caf50' : 'white';
    final opacity = marked ? '0.7' : '0';
    buffer.write('<polygon points="${entry.value}" fill="$fill" fill-opacity="$opacity" stroke="none"/>');
  }

  buffer
    ..write('</g>')
    ..write('<path d="$pathData" fill="none" stroke="#333333" stroke-width="1"/>')
    ..write('<text x="20" y="24" text-anchor="middle" font-size="10" font-weight="bold" fill="#333333">$toothId</text>');

  if (extracted) {
    buffer.write('<path d="M 0,0 L 40,40 M 40,0 L 0,40" stroke="red" stroke-width="2" fill="none"/>');
  }

  buffer.write('</svg>');

  return buffer.toString();
}
