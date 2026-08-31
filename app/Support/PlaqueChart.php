<?php

namespace App\Support;

/**
 * Periodontal's "Plaque Index" per-visit dental chart — a completely
 * separate feature from the BOP/PPD/CAL measurement grids
 * `PeriodontalChartForm::chartGroups()` already covers, both stored in
 * the same `chart_data` JSON column under a different top-level key
 * (`dentalCharts`, matching the original's own key exactly, so a chart
 * saved by either app stays readable by the other).
 *
 * Ported from `dental_clinics2/doctor/periodontal_chart_print_html.php`'s
 * own `createToothSVG()`/`renderDentalChartJS()` (JS, client-side there —
 * server-side here, for the same "print must not depend on a script
 * having run" reason as everywhere else in this renderer family). By
 * explicit request (2026-08-31), this uses the original's own 5-visit
 * structure (`visit2`–`visit5`, `followup`) rather than the 3-stage
 * grouping `chartGroups()` uses for the measurement grids — a deliberate
 * exception, confirmed directly rather than assumed, since those two
 * features track genuinely different things in the original (BOP/PPD/CAL
 * progress vs. a plaque-presence snapshot per visit).
 */
class PlaqueChart
{
    public const VISITS = [
        ['key' => 'visit2', 'label' => 'Second Visit'],
        ['key' => 'visit3', 'label' => 'Third Visit'],
        ['key' => 'visit4', 'label' => 'Fourth Visit'],
        ['key' => 'visit5', 'label' => 'Fifth Visit'],
        ['key' => 'followup', 'label' => 'Follow up Visit'],
    ];

    /**
     * FDI tooth number => anatomical shape key, one arch, left-to-right in
     * the order the original's own `upperTeeth`/`lowerTeeth` JS arrays
     * list them (not numeric order — matches display order).
     */
    public const UPPER_TEETH = [
        18 => 'molar', 17 => 'molar', 16 => 'molar',
        15 => 'premolar', 14 => 'premolar',
        13 => 'canine',
        12 => 'incisorUpper', 11 => 'incisorUpper', 21 => 'incisorUpper', 22 => 'incisorUpper',
        23 => 'canine',
        24 => 'premolar', 25 => 'premolar',
        26 => 'molar', 27 => 'molar', 28 => 'molar',
    ];

    public const LOWER_TEETH = [
        48 => 'molar', 47 => 'molar', 46 => 'molar',
        45 => 'premolar', 44 => 'premolar',
        43 => 'canine',
        42 => 'incisorLower', 41 => 'incisorLower', 31 => 'incisorLower', 32 => 'incisorLower',
        33 => 'canine',
        34 => 'premolar', 35 => 'premolar',
        36 => 'molar', 37 => 'molar', 38 => 'molar',
    ];

    /** The 4 quadrant sectors every tooth's chart tracks — matches the original's own `q.name` list. */
    public const SURFACES = ['buccal', 'distal', 'lingual', 'mesial'];

    /** Each shape's outline, in a 0–40 box — copied verbatim from the original's own `toothShapes`. */
    public const TOOTH_SHAPES = [
        'molar' => 'M 5,10 Q 20,0 35,10 Q 40,20 35,35 Q 20,40 5,35 Q 0,20 5,10 Z',
        'premolar' => 'M 5,10 Q 20,2 35,10 Q 38,25 30,35 Q 20,38 10,35 Q 2,25 5,10 Z',
        'canine' => 'M 5,15 L 20,2 L 35,15 L 30,35 L 10,35 Z',
        'incisorUpper' => 'M 0,0 L 40,0 L 34,40 L 6,40 Z',
        'incisorLower' => 'M 5,2 L 35,2 L 32,38 L 8,38 Z',
    ];

    /**
     * One visit's data, normalized for either print renderer to draw from
     * directly — every one of the 32 FDI tooth slots present (blank
     * default when the doctor never touched that tooth), plus the same
     * "Plaque Index: X% (Marked Surfaces: Y / Total: Z)" stat the
     * original's own `renderDentalChartJS()` computes, recalculated here
     * rather than trusted from stored data for the same reason the
     * original recalculates it at render time: an extracted tooth's
     * surfaces must never count toward the total, and that has to stay
     * true even if the stored `extracted` flag changed after the surfaces
     * were originally marked.
     *
     * @return array{teeth: array<int, array{extracted: bool, surfaces: array<string, bool>}>, total_surfaces: int, marked_surfaces: int, plaque_index: float}|null
     *               null when this visit has no data at all — the section
     *               prints nothing rather than a blank chart with a 0%
     *               stat line that was never actually recorded.
     */
    public static function visitData(array $chartData, string $visitKey): ?array
    {
        $teeth = $chartData['dentalCharts'][$visitKey]['teeth'] ?? null;

        if (! is_array($teeth) || $teeth === []) {
            return null;
        }

        $total = 0;
        $marked = 0;
        $normalized = [];

        foreach (self::UPPER_TEETH + self::LOWER_TEETH as $toothId => $type) {
            $t = $teeth[(string) $toothId] ?? $teeth[$toothId] ?? null;
            $isExtracted = self::truthy($t['extracted'] ?? null);

            $surfaces = [];
            foreach (self::SURFACES as $surface) {
                $value = self::truthy($t['surfaces'][$surface] ?? null);
                // The original also treats a `palatal` key as `lingual` for
                // upper teeth (`q.name === 'lingual' && ... surfaces['palatal']`)
                // — a leftover from an earlier column name, kept for data saved
                // under that name.
                if (! $value && $surface === 'lingual') {
                    $value = self::truthy($t['surfaces']['palatal'] ?? null);
                }
                $surfaces[$surface] = $value;
            }

            if (! $isExtracted) {
                $total += 4;
                $marked += count(array_filter($surfaces));
            }

            $normalized[$toothId] = ['extracted' => $isExtracted, 'surfaces' => $surfaces];
        }

        return [
            'teeth' => $normalized,
            'total_surfaces' => $total,
            'marked_surfaces' => $marked,
            'plaque_index' => $total > 0 ? round($marked / $total * 100, 1) : 0.0,
        ];
    }

    private static function truthy(mixed $value): bool
    {
        if (is_string($value)) {
            return in_array(strtolower($value), ['1', 'true', 'yes'], true);
        }

        return (bool) $value;
    }
}
