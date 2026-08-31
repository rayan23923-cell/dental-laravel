<?php

namespace App\Support;

use Illuminate\Database\Eloquent\Model;

/**
 * Turns a sheet's `*Form::sections()` layout plus its stored record into
 * printable rows.
 *
 * This is the piece that lets one Blade document stand in for the original's
 * nine hand-written print pages: the layout classes already describe every
 * field's key, label and type for the on-screen form, so the printout can be
 * derived from the same description instead of restating it.
 *
 * Formatting rules are taken from what the original's print pages actually
 * emit — booleans print as Yes/No, selects print their option *label* not
 * the stored value, tooth pickers print the comma list, textareas print in a
 * bordered box, and empty fields print as a blank cell rather than being
 * dropped (a printed case sheet is a form: the label must still be there for
 * a supervisor to write on).
 */
class CaseSheetPrintRenderer
{
    /** Field types that occupy a whole row and print inside a bordered box. */
    private const BLOCK_TYPES = ['textarea'];

    /** Field types that occupy a whole row without a box. */
    private const WIDE_TYPES = ['teeth', 'ppd', 'cal', 'bop'];

    /**
     * The JSON-blob column names a sheet's `sections()` groups fields
     * under — every distinct `field['group']` value.
     *
     * Real bug fixed here (2026-08-20): the two print controllers used to
     * call this via `method_exists($formClass, 'groupColumns') ? ... : []`
     * — but only `OralMedicineForm` actually implements that static
     * method. `OrthodonticsForm` (its whole `examination_data` blob,
     * ~40 fields) and `PreventionForm` (`patient_data`/`questions`/
     * `dmfs_indices`/`dietary_recall`) both group fields just as heavily
     * but have no `groupColumns()`, so `decodeGroups()` below never
     * populated their groups at all — every grouped field on an
     * Orthodontics or Prevention printout silently rendered blank.
     * `sections()` itself is the one thing every sheet always has, so
     * deriving the group list from it (rather than a same-named static
     * method most `*Form` classes never implemented) fixes this for
     * every sheet at once and can't drift out of sync with the fields it
     * actually describes.
     */
    public static function deriveGroupColumns(array $sections): array
    {
        return collect($sections)
            ->flatMap(fn ($section) => $section['fields'] ?? [])
            ->pluck('group')
            ->filter()
            ->unique()
            ->values()
            ->all();
    }

    /**
     * @param  array<int, string>  $excludeKeys  Field keys printed elsewhere
     *                                            as their own graphical block
     *                                            (see toothMarkerCharts()
     *                                            below) — skipped here so
     *                                            they don't also print as a
     *                                            plain comma-list cell.
     * @return array<int, array{title: string, rows: array}> sections that
     *                                                      have at least one printable field
     */
    public static function sections(array $sections, Model $sheet, array $groupColumns = [], array $excludeKeys = []): array
    {
        $groups = self::decodeGroups($sheet, $groupColumns);
        $out = [];

        foreach ($sections as $section) {
            $cells = [];

            foreach ($section['fields'] ?? [] as $field) {
                if (in_array($field['key'] ?? null, $excludeKeys, true)) {
                    continue;
                }

                // `file` fields are upload widgets — the original's print
                // pages never render them, and a stored path on paper is
                // meaningless. `dental_chart` (the odontogram) is printed
                // as its own dedicated block by dentalChart() below, not
                // packed as a label:value cell — its value is a structured
                // array, not text.
                // `teeth_squares_grid` and `quadrant_repeater` (Orthodontics'
                // marking grid and its two info+quadrant repeaters) hold
                // structured per-cell/per-row data the generic label:value
                // cell can't represent — not printed yet, same as `file`.
                //
                // Oral Medicine's six JSON_BLOB_FIELD_TYPES (see
                // SectionedForm.vue) are whole-column blobs with no
                // Eloquent cast — `$sheet->{$key}` below would return the
                // raw *undecoded JSON string*, which the generic formatter
                // has no case for and would print verbatim: the exact same
                // "raw JSON leaking into a field" bug fixed on the edit
                // form (see README, 2026-08-20) resurfacing on the printed
                // sheet instead. Excluded here for the same reason as the
                // structured types above, until each gets a real print
                // block.
                if (in_array($field['type'] ?? 'text', [
                    'file', 'dental_chart', 'teeth_squares_grid', 'quadrant_repeater',
                    'history_complaint', 'pmh_checklist', 'surgical_history',
                    'family_history', 'social_history', 'extraoral_exam',
                ], true)) {
                    continue;
                }

                $cells[] = self::cell($field, $sheet, $groups);
            }

            if ($cells === []) {
                continue;
            }

            $out[] = [
                'title' => $section['title'] ?? '',
                'rows' => self::pack($cells),
            ];
        }

        return $out;
    }

    /** Tooth order, FDI notation — the same quadrant layout as PerioChart.vue. */
    private const UPPER_TEETH = [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28];

    private const LOWER_TEETH = [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38];

    /**
     * Per-tooth measurement grids (periodontal BOP/PPD/CAL).
     *
     * The original renders these client-side at print time — its
     * periodontal_chart_print_html.php builds the tables in JavaScript from
     * the `chart_data` JSON (`renderChartTable`, its server-side
     * `renderDentalChart()` is a stub that returns ''). Rendered server-side
     * here instead: a printout that depends on scripts having run is the one
     * thing that must not be left to chance, and Ctrl+P can fire before the
     * script does.
     *
     * Six sites per tooth (3 buccal + 3 palatal/lingual), the shape
     * PerioChart.vue stores: { tooth: { buccal: [v,v,v], lingual: [v,v,v] } }.
     */
    public static function charts(array $chartGroups, ?array $chartData): array
    {
        if ($chartGroups === [] || ! $chartData) {
            return [];
        }

        $out = [];

        foreach ($chartGroups as $group) {
            $tables = [];

            foreach ($group['tables'] ?? [] as $table) {
                $values = $chartData[$group['key']][$table['key']] ?? [];

                if (! is_array($values) || $values === []) {
                    continue;
                }

                $tables[] = [
                    'label' => $table['label'] ?? $table['key'],
                    'arches' => [
                        self::arch('Upper', self::UPPER_TEETH, $values, 'Palatal'),
                        self::arch('Lower', self::LOWER_TEETH, $values, 'Lingual'),
                    ],
                ];
            }

            // A group whose measurements were never filled in is omitted
            // rather than printed as an empty grid.
            if ($tables !== []) {
                $out[] = ['title' => $group['title'] ?? '', 'tables' => $tables];
            }
        }

        return $out;
    }

    private static function arch(string $name, array $teeth, array $values, string $innerLabel): array
    {
        return [
            'name' => $name,
            'innerLabel' => $innerLabel,
            'teeth' => $teeth,
            'buccal' => array_map(fn ($t) => self::sites($values[$t]['buccal'] ?? null), $teeth),
            'lingual' => array_map(fn ($t) => self::sites($values[$t]['lingual'] ?? null), $teeth),
        ];
    }

    /** Always three sites, so the grid keeps its shape when values are absent. */
    private static function sites(mixed $zone): array
    {
        $zone = is_array($zone) ? array_values($zone) : [];

        return [
            (string) ($zone[0] ?? ''),
            (string) ($zone[1] ?? ''),
            (string) ($zone[2] ?? ''),
        ];
    }

    /**
     * The odontogram's drawing vocabulary — copied point-for-point from
     * `Components/ToothOdontogram.vue`'s `SURFACE_POINTS` (itself read out
     * of the original `dental_clinics2/doctor/operative.php`'s SVG), so the
     * printed chart, the on-screen Vue editor, and the Flutter PDF's own
     * vector drawing (`case_sheet_print_pdf.dart`) all draw the exact same
     * shapes from the exact same source of truth. A 0–30 square per tooth,
     * five surfaces in a "flower" target pattern.
     */
    public const SURFACE_POINTS = [
        'top' => [[0, 0], [30, 0], [20, 10], [10, 10]],
        'left' => [[0, 0], [10, 10], [10, 20], [0, 30]],
        'bottom' => [[0, 30], [10, 20], [20, 20], [30, 30]],
        'right' => [[30, 0], [20, 10], [20, 20], [30, 30]],
        'center' => [[10, 10], [20, 10], [20, 20], [10, 20]],
    ];

    public const SURFACE_COLORS = [
        'healthy' => '#ffffff', 'cavity' => '#ffc107', 'filling' => '#000000',
        'crown' => '#17a2b8', 'bridge' => '#6f42c1',
    ];

    public const ROOT_COLORS = [
        'healthy' => '#ffffff', 'root_canal' => '#dc3545', 'infected' => '#ff9800', 'treated' => '#4caf50',
    ];

    /** Overrides every surface uniformly — see ToothOdontogram.vue's own TOOTH_LEVEL_FILL. */
    public const TOOTH_LEVEL_FILL = [
        'missing' => '#6c757d', 'extracted' => '#6c757d', 'non_vital' => '#8b0000',
    ];

    public const TOOTH_LEVEL_OPACITY = [
        'missing' => 0.15, 'extracted' => 0.35,
    ];

    /** FDI numbering, right-to-left across each arch — matches ToothOdontogram.vue's UPPER/LOWER. */
    public const UPPER_ARCH = [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28];

    public const LOWER_ARCH = [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38];

    /**
     * The odontogram's raw per-tooth data (only the *marked* teeth) — kept
     * as `tooth_status`/`polygons` rather than pre-flattened English/Arabic
     * labels, so both print surfaces (the Blade SVG chart below and the
     * Flutter PDF's own vector chart) can feed it straight into the same
     * `SURFACE_POINTS`/`*_COLORS` lookups the on-screen editors already
     * use, instead of re-parsing a formatted string. Returns [] when the
     * sheet has no `dental_chart` field, so the section prints nothing
     * rather than a chart with no data behind it.
     */
    public static function dentalChart(array $sections, Model $sheet): array
    {
        $field = collect($sections)
            ->flatMap(fn ($s) => $s['fields'] ?? [])
            ->firstWhere('type', 'dental_chart');

        if (! $field) {
            return [];
        }

        // Cast to 'array' on the model (App\Models\DentalChart) — already a
        // real PHP array, not a JSON string, unlike the group-JSON columns
        // elsewhere in this renderer.
        $teeth = $sheet->{$field['key']} ?? [];

        if (! is_array($teeth)) {
            return [];
        }

        return collect($teeth)
            ->filter(fn ($t) => ! empty($t['number']))
            ->map(fn ($t) => [
                'number' => (string) $t['number'],
                'tooth_status' => $t['toothStatus'] ?? null,
                'polygons' => collect($t['polygons'] ?? [])
                    ->map(fn ($p) => $p['status'] ?? null)
                    ->filter()
                    ->all(),
                'notes' => (string) ($t['notes'] ?? ''),
            ])
            ->values()
            ->all();
    }

    /**
     * Quadrant + number tooth codes (`UR8`, `UL1`, `LR6`, `LL3`, …) — this
     * app's own unified tooth-picker convention (`QuadrantTeeth.vue`,
     * shared by every `teeth`-type field across all 8 sheets), read
     * outer-to-inner on the right quadrants and inner-to-outer on the
     * left, matching that component's own `QUADRANTS` layout so a printed
     * chart lines up with what the doctor actually clicked on screen. Not
     * the same numbering the *original* app's own print pages used for
     * these same fields (`operative.php`'s FDI two-digit codes,
     * `surgery_print_html.php`'s own bespoke `U1`–`U16`/`L1`–`L16`) — this
     * rebuild deliberately replaced those inconsistent per-page schemes
     * with one shared picker, so the print chart follows that, not the
     * original's now-defunct numbering.
     */
    public const QUADRANTS = [
        'UR' => [8, 7, 6, 5, 4, 3, 2, 1],
        'UL' => [1, 2, 3, 4, 5, 6, 7, 8],
        'LR' => [8, 7, 6, 5, 4, 3, 2, 1],
        'LL' => [1, 2, 3, 4, 5, 6, 7, 8],
    ];

    /**
     * Circled-tooth-number marker charts — the simpler graphic the
     * original draws on `surgery_print_html.php`/`complete_denture_print_html.php`/
     * `prosthodontics_print_html.php` for a handful of `teeth`-type fields
     * (a plain circle around each selected tooth's number, not a full
     * per-surface odontogram like `dentalChart()`'s). Which fields get
     * this treatment, on which of the 8 sheets, is config-driven —
     * `App\Support\CaseSheetPrint::SHEETS[...]['toothMarkerCharts']` — since
     * the original doesn't graph *every* `teeth` field this way (Orthodontics'
     * many tooth-position fields, for one, print as plain text there too).
     *
     * @param  array  $config  One `CaseSheetPrint::SHEETS` entry.
     * @return array<int, array{label: string, selected: array<int, string>}>
     *               Charts with at least one selected tooth — an empty
     *               chart is omitted rather than printed blank.
     */
    public static function toothMarkerCharts(array $config, Model $sheet): array
    {
        return collect($config['toothMarkerCharts'] ?? [])
            ->map(function ($chart) use ($sheet) {
                $raw = $sheet->{$chart['key']} ?? null;
                if (empty($raw) && ! empty($chart['fallbackKey'])) {
                    $raw = $sheet->{$chart['fallbackKey']} ?? null;
                }

                $selected = collect(explode(',', (string) $raw))
                    ->map(fn ($code) => self::normalizeToothCode($code))
                    ->filter()
                    ->values()
                    ->all();

                return ['label' => $chart['label'], 'selected' => $selected];
            })
            ->filter(fn ($chart) => $chart['selected'] !== [])
            ->values()
            ->all();
    }

    /**
     * Normalizes one tooth code to this app's own `{UR|UL|LR|LL}{1-8}`
     * convention, whatever format it actually arrived in. **Real,
     * confirmed-live data problem, not a theoretical one**: this app's own
     * `QuadrantTeeth.vue` picker only ever writes the canonical form, but
     * the `surgeries` table's 16 real rows (imported from the original
     * database, predating that picker) hold `selected_teeth` in the
     * *original* surgery print page's own bespoke `U1`–`U16`/`L1`–`L16`
     * scheme instead (confirmed via a live query, e.g. `"U1,U9,L1,L9"`) —
     * matching those against the canonical form directly would have
     * silently shown every legacy-imported surgery sheet's chart as
     * completely blank. Also accepts a raw FDI two-digit tooth number
     * (`"16"`, `"38"`), since `complete_denture_print_html.php`'s own
     * `convertQuadrantCodesToToothNumbers()` shows the original treats
     * that as valid input for these same fields too.
     */
    private static function normalizeToothCode(string $code): ?string
    {
        $code = strtoupper(trim($code));

        if ($code === '') {
            return null;
        }

        // Already canonical: UR8, UL1, LR6, LL3.
        if (preg_match('/^(UR|UL|LR|LL)([1-8])$/', $code, $m)) {
            return $m[1].$m[2];
        }

        // surgery_print_html.php's own U1-U16 / L1-L16 (1-8 = right
        // quadrant reading outer-to-inner, 9-16 = left quadrant reading
        // inner-to-outer — see this method's own doc comment).
        if (preg_match('/^([UL])(1[0-6]|[1-9])$/', $code, $m)) {
            $n = (int) $m[2];

            return $m[1].($n <= 8 ? 'R' : 'L').($n <= 8 ? $n : $n - 8);
        }

        // Raw FDI two-digit tooth number (11-48) — quadrant from the first
        // digit, in-quadrant position from the second (FDI's own '1' is
        // the innermost/central tooth, same as this app's own position 1).
        if (preg_match('/^([1-4])([1-8])$/', $code, $m)) {
            $quadrant = ['1' => 'UR', '2' => 'UL', '3' => 'LL', '4' => 'LR'][$m[1]];

            return $quadrant.$m[2];
        }

        return null;
    }

    /**
     * FDI tooth numbers (11-48) for prosthodontics' decorative anatomical
     * arch illustration (`resources/views/print/partials/prosthodontics-dental-arch.blade.php`)
     * — the one graphic among the 8 sheets this renderer doesn't hand back
     * as structured cell/chart data, since the illustration itself is a
     * static asset the Blade partial embeds directly; this only needs to
     * say *which* teeth to colour, in the FDI numbering that static
     * asset's `tooth-{n}-parent`/`tooth-{n}`/`tooth-{n}-text` CSS classes
     * are keyed by (not this app's own `UR8`-style codes — see
     * normalizeToothCode()'s doc comment for why those differ).
     *
     * @return array{missing: array<int, int>, caries: array<int, int>}
     */
    public static function prosthodonticsDentalArch(Model $sheet): array
    {
        $toFdiList = fn (mixed $raw) => collect(explode(',', (string) $raw))
            ->map(fn ($code) => self::normalizeToothCode($code))
            ->filter()
            ->map(fn ($code) => self::quadrantCodeToFdi($code))
            ->filter()
            ->values()
            ->all();

        return [
            'missing' => $toFdiList($sheet->missing_teeth ?? null),
            'caries' => $toFdiList($sheet->caries_teeth ?? null),
        ];
    }

    private static function quadrantCodeToFdi(string $code): ?int
    {
        if (! preg_match('/^(UR|UL|LL|LR)([1-8])$/', $code, $m)) {
            return null;
        }

        return ['UR' => 1, 'UL' => 2, 'LL' => 3, 'LR' => 4][$m[1]] * 10 + (int) $m[2];
    }

    /**
     * Stage rows for the sheets that have them; columns follow the
     * original's `stage_{key}_{signature,date,grade}` naming.
     */
    public static function stages(array $stages, Model $sheet): array
    {
        return array_map(fn ($stage) => [
            'label' => $stage['label'] ?? ($stage['key'] ?? ''),
            'note' => $stage['note'] ?? null,
            'signature' => (string) ($sheet->{"stage_{$stage['key']}_signature"} ?? ''),
            'date' => self::formatDate($sheet->{"stage_{$stage['key']}_date"} ?? null),
            'grade' => (string) ($sheet->{"stage_{$stage['key']}_grade"} ?? ''),
        ], $stages);
    }

    private static function cell(array $field, Model $sheet, array $groups): array
    {
        $type = $field['type'] ?? 'text';
        $key = $field['key'];

        $raw = isset($field['group'])
            ? ($groups[$field['group']][$key] ?? null)
            : ($sheet->{$key} ?? null);

        $block = in_array($type, self::BLOCK_TYPES, true);
        $wide = in_array($type, self::WIDE_TYPES, true)
            || ($field['width'] ?? null) === 'full';

        return [
            'label' => $field['label'] ?? $key,
            'value' => self::format($raw, $type, $field),
            'block' => $block,
            'teeth' => $type === 'teeth',
            'wide' => $block || $wide,
        ];
    }

    private static function format(mixed $raw, string $type, array $field): string
    {
        if ($raw === null || $raw === '') {
            return '';
        }

        return match ($type) {
            'boolean' => self::truthy($raw) ? 'Yes' : 'No',
            'date' => self::formatDate($raw),
            'select', 'radio', 'lookup' => self::optionLabel($raw, $field),
            'checkboxes' => is_array($raw) ? implode(', ', array_map(fn ($v) => self::optionLabel($v, $field), $raw)) : self::optionLabel($raw, $field),
            'teeth' => self::teeth($raw),
            default => is_array($raw) ? self::flatten($raw) : (string) $raw,
        };
    }

    /**
     * Booleans arrive as 1/0, "1"/"0", true/false or "yes"/"no" depending on
     * whether the column is cast — all of which must print the same way.
     */
    private static function truthy(mixed $raw): bool
    {
        if (is_string($raw)) {
            return in_array(strtolower($raw), ['1', 'yes', 'true', 'on'], true);
        }

        return (bool) $raw;
    }

    /**
     * Prints the option's label, not the stored value — the original's print
     * pages show "Female", never "female".
     */
    private static function optionLabel(mixed $raw, array $field): string
    {
        foreach ($field['options'] ?? [] as $option) {
            if ((string) ($option['value'] ?? '') === (string) $raw) {
                return (string) ($option['label'] ?? $raw);
            }
        }

        // `lookup` options come from another table at render time and aren't
        // in the layout, so the stored value is the best available label.
        return (string) $raw;
    }

    /** Tooth pickers store a comma list ("U1,U2,L3"); normalise the spacing. */
    private static function teeth(mixed $raw): string
    {
        $parts = array_filter(array_map('trim', explode(',', (string) $raw)), fn ($p) => $p !== '');

        return implode(', ', array_map('strtoupper', $parts));
    }

    private static function formatDate(mixed $raw): string
    {
        if (! $raw) {
            return '';
        }

        // Date columns serialise as full ISO datetimes; the sheets print the
        // calendar date only.
        return preg_match('/^(\d{4}-\d{2}-\d{2})/', (string) $raw, $m) ? $m[1] : (string) $raw;
    }

    private static function flatten(array $raw): string
    {
        return implode(', ', array_filter(array_map(
            fn ($v) => is_scalar($v) ? trim((string) $v) : '',
            $raw
        ), fn ($v) => $v !== ''));
    }

    /**
     * Decodes the JSON columns that hold several subkeys each (see the
     * `group` note in App\Support\OralMedicineForm).
     */
    private static function decodeGroups(Model $sheet, array $groupColumns): array
    {
        $groups = [];

        foreach ($groupColumns as $column) {
            $raw = $sheet->{$column} ?? null;

            if (is_array($raw)) {
                $groups[$column] = $raw;

                continue;
            }

            $decoded = is_string($raw) && $raw !== '' ? json_decode($raw, true) : null;
            $groups[$column] = is_array($decoded) ? $decoded : [];
        }

        return $groups;
    }

    /**
     * Packs cells two per row, except wide/boxed ones which take the full
     * width — the two-column strip the original uses for short fields and a
     * full-width row for narratives.
     */
    private static function pack(array $cells): array
    {
        $rows = [];
        $pending = null;

        foreach ($cells as $cell) {
            if ($cell['wide']) {
                if ($pending) {
                    $rows[] = [$pending + ['span' => 2]];
                    $pending = null;
                }
                $rows[] = [$cell + ['span' => 2]];

                continue;
            }

            if ($pending === null) {
                $pending = $cell;

                continue;
            }

            $rows[] = [$pending + ['span' => 1], $cell + ['span' => 1]];
            $pending = null;
        }

        if ($pending) {
            $rows[] = [$pending + ['span' => 2]];
        }

        return $rows;
    }
}
