import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// One tooth position's crown + root outline(s), extracted verbatim (see
/// `AdvancedPerioChart.vue`'s own doc comment) from a reference asset the
/// user supplied specifically to avoid any copyright question — an
/// independently-designed anatomical periodontal chart, not
/// periodontalchart-online.com's own artwork. Root `d` strings need the
/// same `translate(0,10) scale(1.15,.74)` the source asset applies to
/// them; crown `d` strings are already in the tooth's local space.
class _ToothShape {
  const _ToothShape(this.crown, this.roots);
  final String crown;
  final List<String> roots;
}

/// The implant fixture graphic — identical across every tooth in the
/// source asset, so one shared shape suffices.
const _kImplantAbutment = 'M-7,31 L7,31 L6,45 L-6,45 Z';
const _kImplantBody = 'M-6,45 L6,45 L10,58 L8,175 C7,185 3,191 0,194 C-3,191 -7,185 -8,175 L-10,58 Z';
const _kImplantThread =
    'M-9,62 L9,62 M-9,72 L9,72 M-9,82 L9,82 M-9,92 L9,92 M-9,102 L9,102 M-9,112 L9,112 M-9,122 L9,122 M-9,132 L9,132 M-8,142 L8,142 M-8,152 L8,152 M-7,162 L7,162 M-6,172 L6,172';
const _kImplantHighlight = 'M-3,53 L-4,169';

const _kUpperShapes = <String, _ToothShape>{
  'M3': _ToothShape(
    'M-27,5 C-33,-8 -25,-20 -13,-19 L-4,-16 L4,-21 L16,-17 C27,-15 31,-5 28,7 C26,26 17,41 5,46 L-3,44 L-11,47 C-20,39 -27,24 -27,5 Z',
    ['M-13,43 C-18,79 -20,120 -13,151 C-9,167 -2,176 0,179 C4,174 8,163 9,148 C10,116 14,78 13,43 Z'],
  ),
  'M2': _ToothShape(
    'M-29,6 C-32,-6 -26,-17 -16,-18 L-7,-15 L0,-21 L8,-15 L17,-18 C27,-16 32,-7 29,6 C28,26 18,42 7,48 L0,45 L-7,48 C-18,42 -28,26 -29,6 Z',
    [
      'M-17,43 C-21,80 -27,123 -25,158 C-24,174 -18,185 -12,191 C-14,148 -11,91 -6,43 Z',
      'M-5,43 C-8,87 -9,137 -4,177 C-2,188 0,196 3,201 C6,192 7,183 6,172 C4,128 4,82 4,43 Z',
      'M8,43 C13,84 19,129 17,163 C21,160 26,153 27,143 C28,116 23,79 18,43 Z',
    ],
  ),
  'M1': _ToothShape(
    'M-31,5 C-34,-7 -28,-19 -18,-19 L-8,-16 L0,-24 L8,-16 L18,-20 C28,-18 34,-8 31,5 C30,26 20,44 7,50 L0,47 L-7,50 C-20,44 -30,26 -31,5 Z',
    [
      'M-18,43 C-22,80 -29,126 -27,163 C-26,179 -20,191 -13,198 C-15,151 -12,91 -6,43 Z',
      'M-6,43 C-9,86 -11,139 -6,181 C-4,194 -1,202 2,207 C5,199 7,190 7,178 C5,132 4,83 4,43 Z',
      'M7,43 C13,86 21,134 19,171 C24,168 30,159 31,148 C32,119 26,80 20,43 Z',
    ],
  ),
  'PM2': _ToothShape(
    'M-23,3 C-23,-8 -15,-14 -7,-11 L0,-19 L7,-11 C15,-14 23,-8 23,3 C22,24 15,38 6,44 L0,41 L-6,44 C-15,38 -22,24 -23,3 Z',
    ['M-12,40 C-15,79 -18,121 -14,158 C-12,174 -6,185 0,192 C4,183 7,169 9,148 C12,111 12,72 11,40 Z'],
  ),
  'PM1': _ToothShape(
    'M-25,2 C-25,-9 -17,-15 -9,-12 L0,-22 L9,-12 C17,-15 25,-9 25,2 C24,24 17,40 7,46 L0,43 L-7,46 C-17,40 -24,24 -25,2 Z',
    [
      'M-14,40 C-18,79 -23,119 -20,154 C-18,171 -11,184 -5,190 C-7,147 -4,91 -1,40 Z',
      'M2,40 C5,84 9,134 7,171 C11,166 18,157 20,145 C23,112 18,76 14,40 Z',
    ],
  ),
  'C': _ToothShape(
    'M-17,4 C-18,-8 -11,-16 0,-21 C11,-16 18,-8 17,4 L14,40 C9,48 4,52 0,53 C-4,52 -9,48 -14,40 Z',
    ['M-11,40 C-14,80 -17,123 -12,164 C-9,184 -3,199 0,207 C4,199 9,184 13,164 C17,123 14,80 11,40 Z'],
  ),
  'I2': _ToothShape(
    'M-16,5 C-17,-7 -12,-14 -6,-14 L7,-14 C13,-13 17,-7 16,5 L15,36 C10,43 5,46 0,46 C-5,46 -10,43 -15,36 Z',
    ['M-8,35 C-11,71 -12,111 -7,150 C-5,167 -2,181 0,191 C3,181 6,167 8,150 C12,111 11,71 8,35 Z'],
  ),
  'I1': _ToothShape(
    'M-19,4 C-20,-8 -16,-15 -9,-14 L9,-14 C16,-15 20,-8 19,4 L18,38 C12,45 6,48 0,48 C-6,48 -12,45 -18,38 Z',
    ['M-9,35 C-12,72 -13,112 -8,151 C-6,169 -2,184 0,194 C3,184 7,169 9,151 C13,112 12,72 9,35 Z'],
  ),
};

final _kLowerShapes = <String, _ToothShape>{
  'M3': _kUpperShapes['M3']!, // the source asset's own "var" 3rd-molar simplification is shared verbatim across 18/28/38/48
  'M2': const _ToothShape(
    'M-32,4 C-34,-8 -27,-18 -17,-19 L-8,-16 L0,-22 L8,-16 L17,-19 C27,-17 34,-8 32,4 C31,26 20,44 7,49 L0,46 L-7,49 C-20,44 -31,26 -32,4 Z',
    [
      'M-16,43 C-21,83 -26,125 -23,161 C-21,178 -16,188 -10,196 C-13,149 -10,91 -5,43 Z',
      'M6,43 C11,91 14,149 11,188 C16,183 21,174 23,160 C26,125 21,83 17,43 Z',
    ],
  ),
  'M1': const _ToothShape(
    'M-34,4 C-36,-8 -30,-19 -20,-20 L-10,-17 L-2,-23 L7,-17 L17,-20 C29,-18 35,-8 34,4 C33,27 21,45 8,51 L0,48 L-8,51 C-21,45 -33,27 -34,4 Z',
    [
      'M-17,43 C-23,83 -28,126 -25,163 C-23,181 -17,193 -11,201 C-14,153 -11,91 -6,43 Z',
      'M7,43 C12,91 15,151 12,190 C17,185 23,176 25,161 C28,126 23,83 18,43 Z',
    ],
  ),
  'PM2': const _ToothShape(
    'M-25,3 C-25,-9 -16,-15 -7,-13 L0,-19 L7,-13 C16,-15 25,-9 25,3 C24,24 15,40 6,45 L0,42 L-6,45 C-15,40 -24,24 -25,3 Z',
    ['M-12,41 C-15,82 -16,123 -11,162 C-8,180 -3,194 0,202 C3,194 8,180 11,162 C15,123 14,82 12,41 Z'],
  ),
  'PM1': const _ToothShape(
    'M-24,5 C-25,-10 -14,-17 -3,-15 L4,-20 L12,-11 C21,-8 24,2 22,14 C20,29 12,41 3,45 L-5,43 C-15,36 -22,22 -24,5 Z',
    ['M-11,41 C-14,82 -15,122 -10,160 C-7,179 -2,193 0,201 C3,193 8,179 11,160 C15,122 14,82 11,41 Z'],
  ),
  'C': const _ToothShape(
    'M-14,4 C-15,-7 -9,-14 0,-19 C9,-14 15,-7 14,4 L12,38 C8,46 3,50 0,51 C-3,50 -8,46 -12,38 Z',
    ['M-10,40 C-13,81 -14,123 -9,163 C-6,183 -2,198 0,207 C3,198 7,183 10,163 C14,123 13,81 10,40 Z'],
  ),
  'I2': const _ToothShape(
    'M-13,4 C-14,-7 -10,-13 -4,-13 L5,-13 C10,-12 14,-6 13,4 L12,37 C8,43 3,46 0,46 C-4,46 -8,43 -12,37 Z',
    ['M-9,35 C-12,72 -12,111 -7,151 C-5,169 -2,184 0,194 C3,184 6,169 8,151 C12,111 12,72 9,35 Z'],
  ),
  'I1': const _ToothShape(
    'M-12,3 C-13,-7 -9,-12 -4,-12 L4,-12 C9,-12 13,-7 12,3 L11,36 C7,42 3,44 0,44 C-3,44 -7,42 -11,36 Z',
    ['M-8,35 C-11,72 -11,111 -7,150 C-5,168 -2,183 0,193 C3,183 6,168 8,150 C11,111 11,72 8,35 Z'],
  ),
};

const _kUpper = <(int, String)>[
  (18, 'M3'), (17, 'M2'), (16, 'M1'), (15, 'PM2'), (14, 'PM1'), (13, 'C'), (12, 'I2'), (11, 'I1'),
  (21, 'I1'), (22, 'I2'), (23, 'C'), (24, 'PM1'), (25, 'PM2'), (26, 'M1'), (27, 'M2'), (28, 'M3'),
];
const _kLower = <(int, String)>[
  (48, 'M3'), (47, 'M2'), (46, 'M1'), (45, 'PM2'), (44, 'PM1'), (43, 'C'), (42, 'I2'), (41, 'I1'),
  (31, 'I1'), (32, 'I2'), (33, 'C'), (34, 'PM1'), (35, 'PM2'), (36, 'M1'), (37, 'M2'), (38, 'M3'),
];

/// Furcation grade icons (revision 9, by request — "دائرة فارغة نصف دائرة
/// دائرة مملوئة") — the exact `<svg>` markup captured live from the
/// reference site's own furcation buttons at each grade (see
/// `AdvancedPerioChart.vue`'s own doc comment for the full live-capture
/// method): grade 0 has no icon at all (blank cell); grade 1 is a hollow
/// ring; grade 2 is the same ring plus a filled half-circle; grade 3 is a
/// fully filled disc with the ring outline on top.
const _kFurcationRing =
    '<path d="M7.5,2A5.5,5.5,0,1,1,2,7.5a5.51,5.51,0,0,1,5.5-5.5m0-2A7.5,7.5,0,1,0,15,7.5,7.5,7.5,0,0,0,7.5,0Z" fill="#000000"/>';
String _furcationSvg(String grade) {
  switch (grade) {
    case '1':
      return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 15 15">$_kFurcationRing</svg>';
    case '2':
      return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 15 15">$_kFurcationRing<path d="M7.5,15a7.5,7.5,0,1,1,0-15" fill="#000000"/></svg>';
    case '3':
      return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 15 15"><circle cx="7.5" cy="7.5" r="6.5" fill="#000000"/>$_kFurcationRing</svg>';
    default:
      return '';
  }
}

/// Gingival Margin / Probing Depth "pocket" overlay on the tooth graphic
/// (revision 9, by request — "gingival margin attachment lebel وتأثيرها
/// على الخطوط والمنحنيات والجيوب") — Flutter port of the same live-
/// reverse-engineered mechanics documented in full on
/// `AdvancedPerioChart.vue` (a red GM polyline, a blue PD polyline, and a
/// navy semi-transparent polygon band between them, all driven by the
/// per-site mm values; PD is measured *from* the GM line, not a fixed
/// baseline; Attachment Level has no visual effect on the reference
/// site's own graphic, confirmed by isolated live testing, so it isn't
/// drawn here either).
const _kPocketScale = 6.45;
const _kPocketBaselineY = 45.0;
const _kPocketX = [-16.0, 0.0, 16.0];

double _gmLocalY(AdvancedPerioChartField field, int tooth, String zone, int pos) {
  final gm = double.tryParse('${field._getSite(tooth, zone, 'gm', pos)}') ?? 0;
  return _kPocketBaselineY + gm * _kPocketScale;
}

double _pdLocalY(AdvancedPerioChartField field, int tooth, String zone, int pos) {
  final pd = double.tryParse('${field._getSite(tooth, zone, 'pd', pos)}') ?? 0;
  return _gmLocalY(field, tooth, zone, pos) + (pd < 0 ? 0 : pd) * _kPocketScale;
}

String _pocketOverlaySvg(AdvancedPerioChartField field, int tooth, String zone) {
  final gmPts = [for (var pos = 0; pos < 3; pos++) '${_kPocketX[pos]},${_gmLocalY(field, tooth, zone, pos)}'];
  final pdPts = [for (var pos = 0; pos < 3; pos++) '${_kPocketX[pos]},${_pdLocalY(field, tooth, zone, pos)}'];
  final polygonPts = [...gmPts, ...pdPts.reversed].join(' ');
  final buffer = StringBuffer()
    ..write('<polygon points="$polygonPts" fill="#000080" fill-opacity="0.35" stroke="none"/>')
    ..write('<polyline points="${pdPts.join(' ')}" fill="none" stroke="#2563eb" stroke-width="2"/>')
    ..write('<polyline points="${gmPts.join(' ')}" fill="none" stroke="#dc2626" stroke-width="2"/>');
  return buffer.toString();
}

/// Furcation marker drawn directly on the tooth graphic (revision 10, by
/// request — "يطبق تأثير على السن اي يرسم كذلك على السن") — Flutter port
/// of the same live-captured reference-site markup documented in full on
/// `AdvancedPerioChart.vue`'s own `FURCATION_MARKER` doc comment: grade 1
/// is a hollow-ring circle, grade 2 adds a filled half-circle wedge,
/// grade 3 is a bigger fully filled circle. One marker per zone per
/// tooth (not per site), matching this app's own single-furcation-field
/// simplification.
const _kFurcationMarkerY = 34.0; // _kPocketBaselineY (45) - 11, matching the reference's own baseline-relative offset
String _furcationMarkerSvg(AdvancedPerioChartField field, int tooth, String zone) {
  final grade = '${field._getSite(tooth, zone, 'furcation', 0)}';
  const y = _kFurcationMarkerY;
  switch (grade) {
    case '1':
      return '<circle cx="0" cy="$y" r="5.75" fill="none" stroke="#000000" stroke-width="2.5"/>';
    case '2':
      return '<circle cx="0" cy="$y" r="5.75" fill="none" stroke="#000000" stroke-width="2.5"/>'
          '<path d="M 0 ${y - 7} A 7 7 0 0 0 0 ${y + 7} L 0 $y Z" fill="#000000"/>';
    case '3':
      return '<circle cx="0" cy="$y" r="7" fill="#000000"/>';
    default:
      return '';
  }
}

/// Builds the whole arch's tooth-row graphic as one SVG document string,
/// rendered via `flutter_svg`'s `SvgPicture.string` rather than hand-
/// translated `Path` commands — the source paths use cubic Béziers
/// (`C`), and reusing the exact same path strings this way (matching the
/// web side's `AdvancedPerioChart.vue` byte-for-byte) is both simpler and
/// lower-risk than a manual `Path.cubicTo()` transcription of ~40 curves.
String _archSvg(List<(int, String)> arch, bool isUpper, AdvancedPerioChartField field, String zone) {
  const slot = 90.0;
  final width = arch.length * slot;
  const height = 235.0;
  final shapes = isUpper ? _kUpperShapes : _kLowerShapes;

  // The lower arch draws crown-up/root-down (a tooth's own path data is
  // already in that orientation, no flip needed). The upper arch needs
  // the opposite — crown hanging down, root pointing up — the same
  // vertical flip the reference asset's own upper-arch groups apply
  // (`scale(1,-1)`), which an earlier revision omitted, leaving every
  // arch rendering crown-up regardless of jaw (reported live from
  // production: "كل المخططات تتجه للاسفل"). `translate(cx,164) scale(1,-1)`
  // reflects the tooth about screen-y 164 — chosen so the flipped
  // footprint lands in the same [1,188] range the unflipped lower-arch
  // tooth already occupies (crown tip at local y=-24, the tallest root's
  // own transformed tip at local y≈163 — both source-verified from the
  // shape data above), matching `AdvancedPerioChart.vue`'s identical fix.
  final gumlineY = isUpper ? 119.0 : 70.0;

  final buffer = StringBuffer()
    ..write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $width $height">')
    ..write('<line x1="0" y1="$gumlineY" x2="$width" y2="$gumlineY" stroke="#dc2626" stroke-width="1.5" stroke-dasharray="4,3"/>');

  for (var i = 0; i < arch.length; i++) {
    final (tooth, type) = arch[i];
    final cx = 45 + i * slot;
    final implant = field._getSingle(tooth, 'implant') == true;
    final extracted = field._isExtracted(tooth);
    final transform = isUpper ? 'translate($cx,164) scale(1,-1)' : 'translate($cx,25)';

    final shape = shapes[type]!;
    // Dim + a red cross overlay for an extracted tooth — same convention
    // `PlaqueChartField`'s own graphic already established.
    buffer.write('<g transform="$transform" opacity="${extracted ? 0.35 : 1}">');
    // The crown always renders, implant or not — only the *root* is ever
    // replaced by the implant fixture (revision 7, by request: "اجعله لا
    // يختفي بكل الاحوال" — the crown must never disappear), matching the
    // reference asset's own CSS (`.implant-mode` hides `.root`/`.canal`/
    // etc. but never `.crown`) and real anatomy — an implant replaces the
    // natural root, not the visible crown restoration on top of it.
    if (implant) {
      buffer
        ..write('<path d="$_kImplantBody" fill="#d7d9db" stroke="#20272b" stroke-width="1.4"/>')
        ..write('<path d="$_kImplantAbutment" fill="#eceeef" stroke="#20272b" stroke-width="1.4"/>')
        ..write('<path d="$_kImplantThread" fill="none" stroke="#3b4246" stroke-width="1"/>')
        ..write('<path d="$_kImplantHighlight" fill="none" stroke="#ffffff" stroke-width="1" opacity="0.7"/>');
    } else {
      buffer.write('<g transform="translate(0,10) scale(1.15,0.74)">');
      for (final r in shape.roots) {
        buffer.write('<path d="$r" fill="#ffffff" stroke="#37474f" stroke-width="1.3"/>');
      }
      buffer.write('</g>');
    }
    buffer.write('<path d="${shape.crown}" fill="#ffffff" stroke="#20272b" stroke-width="1.6" stroke-linejoin="round"/>');
    if (extracted) {
      buffer.write('<path d="M -25,-15 L 25,175 M 25,-15 L -25,175" stroke="#dc2626" stroke-width="3" stroke-linecap="round"/>');
    } else {
      buffer.write(_pocketOverlaySvg(field, tooth, zone));
      buffer.write(_furcationMarkerSvg(field, tooth, zone));
    }
    buffer.write('</g>');
  }

  buffer.write('</svg>');
  return buffer.toString();
}

/// "Advanced Periodontal Chart" (2026-08-31, revised same day by request)
/// — Flutter port of `resources/js/Components/AdvancedPerioChart.vue`;
/// see that file's own doc comment for the full design rationale
/// (real crown+root/implant artwork from a user-supplied, independently
/// designed reference asset; fluid, non-scrolling layout; row structure
/// closer to periodontalchart-online.com's own logic — Mobility/Implant
/// once per arch, Bleeding on Probing/Plaque/Furcation/Gingival Margin/
/// Probing Depth/Attachment Level twice per arch, a free-text Note once
/// per arch).
///
/// Extraction, and Furcation as a tap-cycle (revision 8, by request —
/// "اضف سلوك القلع وال furcation وbleeding on probing و plaque"): there
/// was no way to mark a tooth extracted before this — added by making
/// the tooth-*number* itself the toggle (same interaction
/// `PlaqueChartField`'s own `_toggleExtractedAllVisits` already
/// established), overlaying a red cross + dimming the drawing when set
/// (visible in both the Labial and Lingual rows automatically, same
/// "one shared data source" property every other per-tooth flag here
/// already has), and locking + excluding from the stats every one of
/// the 6 site metrics for that tooth. Furcation changed from a free-typed
/// number to a tap-to-cycle grade (blank... actually `'0'` → `'1'` →
/// `'2'` → `'3'` → `'0'`, confirmed live against the reference site's own
/// `data-grade` click behavior), and locks specifically (not the other 5
/// metrics) when the tooth is an implant, confirmed live against the
/// reference's own `.implant-active .furcation-button { display: none }`
/// rule.
///
/// Layout (revision 5, reversed from the earlier "no horizontal scroll"
/// request): that revision used `Expanded` flex cells so the arch could
/// never overflow the screen width — technically no-scroll, but on a
/// phone that meant every cell shrank to a few pixels, unusable for
/// actual data entry. Reverted to fixed-pixel-width cells (`_cellSize`,
/// matching `perio_chart_table.dart`'s own established sizing) inside a
/// `SingleChildScrollView(scrollDirection: Axis.horizontal)` wrapping the
/// whole arch's `Column` — desktop/tablet show as many teeth as fit at a
/// legible, tappable size; a phone scrolls horizontally for the rest,
/// explicitly requested this time ("اجعل المخطط قابل للسكرول ومتوافق مع
/// الاجهزة اللوحية والموبايل والحاسوب"). Same tradeoff the web side's
/// `AdvancedPerioChart.vue` makes for the same reason.
///
/// [value] is `chart_data.advancedChart` as already-decoded JSON — see
/// `AdvancedPerioChart.vue`'s own doc comment for the exact shape.
class AdvancedPerioChartField extends StatelessWidget {
  const AdvancedPerioChartField({super.key, required this.value, required this.onChanged, required this.readOnly});

  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  Map<String, dynamic> get _teeth => (value['teeth'] as Map<String, dynamic>?) ?? const {};

  Map<String, dynamic> _toothData(int tooth) => (_teeth['$tooth'] as Map<String, dynamic>?) ?? const {};

  void _setTooth(int tooth, Map<String, dynamic> data) {
    final teeth = Map<String, dynamic>.from(_teeth);
    teeth['$tooth'] = data;
    onChanged({'teeth': teeth});
  }

  dynamic _getSingle(int tooth, String key) => _toothData(tooth)[key] ?? (key == 'implant' ? false : '');

  void _setSingle(int tooth, String key, dynamic v) {
    if (readOnly) return;
    _setTooth(tooth, {..._toothData(tooth), key: v});
  }

  dynamic _getSite(int tooth, String zone, String metric, int pos) {
    final z = _toothData(tooth)[zone] as Map<String, dynamic>?;
    final arr = z?[metric] as List<dynamic>?;
    if (arr != null && pos < arr.length && arr[pos] != null) return arr[pos];
    if (metric == 'bop' || metric == 'plaque') return false;
    if (metric == 'furcation') return '0'; // reference site's own default grade, confirmed live
    return '';
  }

  void _setSite(int tooth, String zone, String metric, int pos, dynamic v) {
    if (readOnly) return;
    final t = Map<String, dynamic>.from(_toothData(tooth));
    final z = Map<String, dynamic>.from((t[zone] as Map<String, dynamic>?) ?? {});
    final arr = List<dynamic>.from((z[metric] as List<dynamic>?) ?? ['', '', '']);
    arr[pos] = v;
    z[metric] = arr;
    t[zone] = z;
    _setTooth(tooth, t);
  }

  void _cycleFurcation(int tooth, String zone, int pos) {
    if (readOnly || _isSiteDisabled(tooth, 'furcation')) return;
    final current = int.tryParse('${_getSite(tooth, zone, 'furcation', pos)}') ?? 0;
    _setSite(tooth, zone, 'furcation', pos, '${(current + 1) % 4}');
  }

  // Extraction (revision 8, by request — "عند الضغط على رقم سن يؤشر عليه
  // انه مقلوع") — toggled by tapping the tooth's own number, same
  // convention `PlaqueChartField`'s own `_toggleExtractedAllVisits`
  // already established. Only one snapshot's worth of data exists per
  // tooth here (unlike Plaque Index's 5 visits), so both the Labial and
  // Lingual graphics already read this same flag automatically.
  bool _isExtracted(int tooth) => _getSingle(tooth, 'extracted') == true;
  void _toggleExtracted(int tooth) {
    if (readOnly) return;
    _setSingle(tooth, 'extracted', !_isExtracted(tooth));
  }

  // A site metric is locked when the tooth is extracted (nothing left to
  // measure) or — furcation only, confirmed live against the reference
  // site's own `.implant-active .furcation-button { display: none }` rule
  // — when the tooth is an implant (a fixture has no natural furcation).
  // Bleeding on Probing/Plaque/Gingival Margin/Probing Depth/Attachment
  // Level stay active around an implant, matching the reference's own
  // behavior exactly rather than assumed uniform.
  bool _isSiteDisabled(int tooth, String metric) =>
      _isExtracted(tooth) || (metric == 'furcation' && _getSingle(tooth, 'implant') == true);

  // 32 teeth x 2 zones x 3 sites = 192 — the reference site's own
  // denominator, but only while every tooth is present. An extracted
  // tooth has no sites left to measure, so it's dropped too — same
  // "extracted teeth never count" rule `PlaqueChart`/`AdvancedPerioChart.vue`
  // already apply.
  ({String avgPd, String avgAl, String bopPct, String plaquePct, int bopMarked, int plaqueMarked, int totalSites}) get _stats {
    var bopMarked = 0, plaqueMarked = 0, pdCount = 0, alCount = 0, totalSites = 0;
    var pdSum = 0.0, alSum = 0.0;
    for (final (tooth, _) in [..._kUpper, ..._kLower]) {
      if (_isExtracted(tooth)) continue;
      totalSites += 6;
      for (final zone in ['buccal', 'lingual']) {
        for (var pos = 0; pos < 3; pos++) {
          if (_getSite(tooth, zone, 'bop', pos) == true) bopMarked++;
          if (_getSite(tooth, zone, 'plaque', pos) == true) plaqueMarked++;
          final pd = double.tryParse('${_getSite(tooth, zone, 'pd', pos)}');
          if (pd != null) {
            pdSum += pd;
            pdCount++;
          }
          final al = double.tryParse('${_getSite(tooth, zone, 'al', pos)}');
          if (al != null) {
            alSum += al;
            alCount++;
          }
        }
      }
    }
    return (
      avgPd: pdCount > 0 ? (pdSum / pdCount).toStringAsFixed(1) : '0.0',
      avgAl: alCount > 0 ? (alSum / alCount).toStringAsFixed(1) : '0.0',
      bopPct: totalSites > 0 ? (bopMarked / totalSites * 100).toStringAsFixed(1) : '0.0',
      plaquePct: totalSites > 0 ? (plaqueMarked / totalSites * 100).toStringAsFixed(1) : '0.0',
      bopMarked: bopMarked,
      plaqueMarked: plaqueMarked,
      totalSites: totalSites,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 4,
            children: [
              Text('Avg. Probing Depth: ${s.avgPd} mm'),
              Text('Avg. Attachment Level: ${s.avgAl} mm'),
              Text('BOP: ${s.bopPct}% (${s.bopMarked} / ${s.totalSites})'),
              Text('PI: ${s.plaquePct}% (${s.plaqueMarked} / ${s.totalSites})'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _ArchBlock(field: this, teeth: _kUpper, isUpper: true),
        const SizedBox(height: 12),
        _ArchBlock(field: this, teeth: _kLower, isUpper: false),
        const SizedBox(height: 6),
        const Text(
          'Bleeding on Probing / Plaque: tap a site to toggle. Furcation: tap a site to cycle its grade (0–3). Gingival Margin (mm, negative = recession) / Probing Depth (mm) / Attachment Level (mm): enter a value per site. Mobility (0–3): one value per tooth. Implant: tap to toggle — the tooth\'s own drawing switches to a fixture graphic and locks its Furcation sites. Extracted: tap the tooth\'s own number — its drawing dims with a red cross and every site metric locks and drops out of the stats. Note: free text per tooth.',
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
      ],
    );
  }
}

// 'kind' drives the cell widget: 'toggle' (BOP/Plaque, boolean), 'cycle'
// (Furcation, tap-to-cycle 0–3 grade — confirmed live against the
// reference site's own click behavior), or 'number' (GM/PD/AL, free-typed).
// 'single' (revision 10, by request — "كل سن يحتوي حقل furcation واحد")
// — Furcation is one value per zone per tooth, not 3 site positions like
// the other metrics; see `_furcationMarkerSvg`'s own doc comment for the
// live-confirmed reasoning.
const _kSiteRows = [
  ('bop', 'BOP', 'toggle', false),
  ('plaque', 'Plaque', 'toggle', false),
  ('furcation', 'Furcation', 'cycle', true),
  ('gm', 'GM', 'number', false),
  ('pd', 'PD', 'number', false),
  ('al', 'AL', 'number', false),
];

const _kSingleRows = [
  ('mobility', 'Mobility'),
  ('implant', 'Implant'),
];

class _ArchBlock extends StatelessWidget {
  const _ArchBlock({required this.field, required this.teeth, required this.isUpper});
  final AdvancedPerioChartField field;
  final List<(int, String)> teeth;
  final bool isUpper;

  @override
  Widget build(BuildContext context) {
    // Stored zone keys are always 'buccal'/'lingual' — only the *display*
    // label and *visual row order* flip per arch, matching the same
    // convention `PerioChart.vue`/`perio_chart_table.dart` already
    // established.
    final innerLabel = isUpper ? 'Palatal' : 'Lingual';
    final firstZone = isUpper ? 'buccal' : 'lingual';
    final firstLabel = isUpper ? 'Buccal' : innerLabel;
    final secondZone = isUpper ? 'lingual' : 'buccal';
    final secondLabel = isUpper ? innerLabel : 'Buccal';

    // Fixed-pixel-width cells inside one shared horizontal scroll — see
    // this file's own doc comment (revision 5) for why: a fluid layout
    // that could never overflow left every cell too small to actually
    // tap/type into on a phone. `_cellSize`/`_labelWidth` match
    // `perio_chart_table.dart`'s own established sizing, and — same
    // precedent as that file — the row label scrolls *with* the row
    // rather than staying pinned, so every row (including the label)
    // stays aligned to the same horizontal scroll position.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.all(2),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isUpper) ..._singleRows(teeth),
              for (final (key, label, kind, single) in _kSiteRows) _siteRow(teeth, firstZone, '$firstLabel — $label', key, kind, single),
              _numberRow(teeth),
              // Two tooth-row diagrams per arch — Labial and Lingual/Palatal
              // views, matching the reference site's own "MAXILLA · LABIAL" /
              // "MAXILLA · LINGUAL" structure (by request). Both draw from
              // the same crown+root outline data (the reference asset's own
              // lingual-view groups carry byte-for-byte identical crown/root
              // paths to the labial view — see the shape library's own doc
              // comment), and both read the same `field._teeth` implant
              // data, so toggling Implant for a tooth swaps *both* rows'
              // drawing for that column together automatically.
              _toothRowGraphic('Labial', 'buccal'),
              _toothRowGraphic(isUpper ? 'Palatal / Lingual' : 'Lingual', 'lingual'),
              for (final (key, label, kind, single) in _kSiteRows.reversed) _siteRow(teeth, secondZone, '$secondLabel — $label', key, kind, single),
              _noteRow(teeth),
              if (!isUpper) ..._singleRows(teeth),
            ],
          ),
        ),
      ),
    );
  }

  // Matches periodontalchart-online.com's own live-measured dimensions
  // (revision 6, "قارن حجم الجداول والاسنان مع هذا الموقع... بدون تخمين
  // اوهلوسة" — read directly from its DOM via the browser rather than
  // guessed): a site-cell `<input>` is 15px wide there, and the label
  // column is 130px — `_labelWidth` is independent of `_cellSize` for the
  // same reason (this app's combined labels, e.g. "Buccal — Bleeding on
  // Probing", are longer than the reference's plain "Bleeding on
  // Probing", so it gets a little more room: 140 vs. their 130).
  static const _cellSize = 15.0;
  static const _labelWidth = 140.0;
  double get _archWidth => teeth.length * _cellSize * 3;

  Widget _toothRowGraphic(String label, String zone) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _labelWidth,
            child: Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: _archWidth,
            child: SvgPicture.string(_archSvg(teeth, isUpper, field, zone), fit: BoxFit.fitWidth),
          ),
        ],
      ),
    );
  }

  List<Widget> _singleRows(List<(int, String)> teeth) => [
        for (final (key, label) in _kSingleRows) _singleRow(teeth, label, key),
      ];

  Widget _rowLabel(String label) => SizedBox(
        width: _labelWidth,
        child: Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis),
      );

  Widget _singleRow(List<(int, String)> teeth, String label, String key) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          _rowLabel(label),
          for (final (tooth, _) in teeth) SizedBox(width: _cellSize * 3, child: _singleCell(tooth, key)),
        ],
      ),
    );
  }

  Widget _singleCell(int tooth, String key) {
    final value = field._getSingle(tooth, key);
    final isToggle = key == 'implant';
    return Container(
      height: 20,
      margin: const EdgeInsets.all(0.5),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
      child: isToggle
          ? Material(
              color: value == true ? Colors.indigo.shade400 : Colors.transparent,
              child: InkWell(
                onTap: field.readOnly ? null : () => field._setSingle(tooth, key, !(value == true)),
                child: Center(
                  child: Text(value == true ? '✓' : '', style: TextStyle(fontSize: 11, color: value == true ? Colors.white : null)),
                ),
              ),
            )
          : TextFormField(
              key: ValueKey('single-$tooth-$key-$value'),
              initialValue: '$value' == 'null' ? '' : '$value',
              enabled: !field.readOnly,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 1,
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(counterText: '', contentPadding: EdgeInsets.zero, border: InputBorder.none),
              onChanged: (v) => field._setSingle(tooth, key, v),
            ),
    );
  }

  Widget _siteRow(List<(int, String)> teeth, String zone, String label, String metric, String kind, bool single) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          _rowLabel(label),
          if (single)
            for (final (tooth, _) in teeth) SizedBox(width: _cellSize * 3, child: _siteCell(tooth, zone, metric, 0, kind))
          else
            for (final (tooth, _) in teeth)
              for (var pos = 0; pos < 3; pos++) SizedBox(width: _cellSize, child: _siteCell(tooth, zone, metric, pos, kind)),
        ],
      ),
    );
  }

  Widget _siteCell(int tooth, String zone, String metric, int pos, String kind) {
    final value = field._getSite(tooth, zone, metric, pos);
    final locked = field._isSiteDisabled(tooth, metric);
    if (kind == 'toggle') {
      final marked = value == true && !locked;
      final color = metric == 'bop' ? Colors.red.shade600 : Colors.amber.shade600;
      return Container(
        height: 20,
        margin: const EdgeInsets.all(0.5),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
        child: Opacity(
          opacity: locked ? 0.35 : 1,
          child: Material(
            color: marked ? color : Colors.transparent,
            child: InkWell(
              onTap: field.readOnly || locked ? null : () => field._setSite(tooth, zone, metric, pos, !(value == true)),
            ),
          ),
        ),
      );
    }
    if (kind == 'cycle') {
      final grade = '$value';
      return Container(
        height: 20,
        margin: const EdgeInsets.all(0.5),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), color: Colors.grey.shade100),
        child: Opacity(
          opacity: locked ? 0.35 : 1,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: field.readOnly || locked ? null : () => field._cycleFurcation(tooth, zone, pos),
              child: grade == '0' ? null : Center(child: SvgPicture.string(_furcationSvg(grade), width: 10, height: 10)),
            ),
          ),
        ),
      );
    }
    return Container(
      height: 20,
      margin: const EdgeInsets.all(0.5),
      child: TextFormField(
        key: ValueKey('site-$tooth-$zone-$metric-$pos-$value'),
        initialValue: '$value' == 'null' ? '' : '$value',
        enabled: !field.readOnly && !locked,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        maxLength: 3,
        style: const TextStyle(fontSize: 10),
        decoration: const InputDecoration(counterText: '', contentPadding: EdgeInsets.zero, border: OutlineInputBorder(borderRadius: BorderRadius.zero)),
        onChanged: (v) => field._setSite(tooth, zone, metric, pos, v),
      ),
    );
  }

  Widget _noteRow(List<(int, String)> teeth) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          _rowLabel('Note'),
          for (final (tooth, _) in teeth) SizedBox(width: _cellSize * 3, child: _noteCell(tooth)),
        ],
      ),
    );
  }

  Widget _noteCell(int tooth) {
    final value = field._getSingle(tooth, 'note');
    return Container(
      height: 20,
      margin: const EdgeInsets.all(0.5),
      child: TextFormField(
        key: ValueKey('note-$tooth-$value'),
        initialValue: '$value' == 'null' ? '' : '$value',
        enabled: !field.readOnly,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 10),
        decoration: const InputDecoration(counterText: '', contentPadding: EdgeInsets.zero, border: OutlineInputBorder(borderRadius: BorderRadius.zero)),
        onChanged: (v) => field._setSingle(tooth, 'note', v),
      ),
    );
  }

  // Tap a tooth's own number to toggle it extracted (revision 8, by
  // request: "عند الضغط على رقم سن يؤشر عليه انه مقلوع") — same
  // convention `PlaqueChartField`'s own tooth-number tap already
  // established.
  Widget _numberRow(List<(int, String)> teeth) => Row(
        children: [
          SizedBox(width: _labelWidth),
          for (final (tooth, _) in teeth)
            SizedBox(
              width: _cellSize * 3,
              child: Material(
                color: field._isExtracted(tooth) ? Colors.red.shade100 : Colors.grey.withValues(alpha: 0.15),
                child: InkWell(
                  onTap: field.readOnly ? null : () => field._toggleExtracted(tooth),
                  child: SizedBox(
                    height: 20,
                    child: Center(
                      child: FittedBox(
                        child: Text(
                          '$tooth',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: field._isExtracted(tooth) ? Colors.red.shade700 : null,
                            decoration: field._isExtracted(tooth) ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
}
