import 'package:flutter/material.dart';

/// Every status/colour value here was read directly out of
/// `dental_clinics2/doctor/operative.php`'s own `<style>` block and JS
/// (`updateToothVisualStatus()`, `surfaceStatusOptions`/`rootStatusOptions`)
/// — the exact same source `Components/ToothOdontogram.vue` was built
/// from, kept in lockstep with it so a chart round-trips identically
/// between the web app and this one.
class ToothStatusOption {
  const ToothStatusOption(this.value, this.label, this.icon, this.color);
  final String value;
  final String label;
  final IconData icon;
  final Color color;
}

class SurfaceStatusOption {
  const SurfaceStatusOption(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color color;
}

const List<ToothStatusOption> kToothStatuses = [
  ToothStatusOption('present', 'Healthy', Icons.check_circle, Color(0xFF059669)),
  ToothStatusOption('non_vital', 'Non-vital', Icons.dangerous, Color(0xFFB91C1C)),
  ToothStatusOption('missing', 'Congenitally Missing', Icons.remove_circle, Color(0xFF6B7280)),
  ToothStatusOption('extracted', 'Extracted', Icons.cancel, Color(0xFF4B5563)),
  ToothStatusOption('retained_root', 'Retained Root', Icons.warning_amber, Color(0xFFEA580C)),
  ToothStatusOption('crown', 'Crown', Icons.emoji_events, Color(0xFF111827)),
];

const List<SurfaceStatusOption> kSurfaceStatuses = [
  SurfaceStatusOption('healthy', 'Healthy', Color(0xFFFFFFFF)),
  SurfaceStatusOption('cavity', 'Cavity', Color(0xFFFFC107)),
  SurfaceStatusOption('filling', 'Filling', Color(0xFF000000)),
  SurfaceStatusOption('crown', 'Crown', Color(0xFF17A2B8)),
  SurfaceStatusOption('bridge', 'Bridge', Color(0xFF6F42C1)),
];

const List<SurfaceStatusOption> kRootStatuses = [
  SurfaceStatusOption('healthy', 'Healthy', Color(0xFFFFFFFF)),
  SurfaceStatusOption('root_canal', 'Root Canal', Color(0xFFDC3545)),
  SurfaceStatusOption('infected', 'Infected', Color(0xFFFF9800)),
  SurfaceStatusOption('treated', 'Treated', Color(0xFF4CAF50)),
];

const kTreatmentStatuses = [
  ('planned', 'Planned'),
  ('in_progress', 'In Progress'),
  ('completed', 'Completed'),
  ('failed', 'Failed'),
];

/// Tooth-level fills that override every surface uniformly — a non_vital
/// tooth always paints solid dark red regardless of its per-root statuses
/// (those are tracked as data but never distinguished visually on the
/// flower icon, matching the original exactly); missing/extracted paint
/// uniform grey at reduced opacity.
const Map<String, Color> kToothLevelFill = {
  'missing': Color(0xFF6C757D),
  'extracted': Color(0xFF6C757D),
  'non_vital': Color(0xFF8B0000),
};

const Map<String, double> kToothLevelOpacity = {
  'missing': 0.15,
  'extracted': 0.35,
};

const kUpperArch = [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28];
const kLowerArch = [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38];

/// The five non-root surfaces every tooth's flower icon always draws
/// (three become editable as roots instead once non_vital, but the icon
/// itself keeps these same five polygon slots — see kToothLevelFill above
/// for why non_vital doesn't need per-surface colours at all).
const kSurfaceIds = ['top', 'left', 'bottom', 'right', 'center'];
const kRootIds = ['root-1', 'root-2', 'root-3'];

String surfaceLabel(String surfaceId) => const {
      'top': 'Top',
      'bottom': 'Bottom',
      'left': 'Left',
      'right': 'Right',
      'center': 'Center',
      'root-1': 'Root 1',
      'root-2': 'Root 2',
      'root-3': 'Root 3',
    }[surfaceId] ??
    surfaceId;

Color colorForStatus(List<SurfaceStatusOption> pool, String? status) =>
    pool.firstWhere((s) => s.value == status, orElse: () => pool.first).color;
