<?php

namespace App\Support;

use App\Models\CaseSheetType;
use App\Models\Department;
use App\Models\Doctor;
use App\Models\Task;
use App\Models\TaskInstance;
use Illuminate\Support\Collection;
use Illuminate\Validation\ValidationException;

/**
 * Points-based requirements (2026-10-14, by request, from the college's
 * "minimum clinical requirements" sheet).
 *
 * A task may carry `scoring`:
 *   measure    'count' (cases, as before) | 'points' | 'both'
 *   min_points the points target ('points'/'both')
 *   weight     the task's share (%) of its department's result; when no
 *              task of a department has one, every task weighs the same
 *   options    [{label, points}] the kinds of work, picked on completion
 *   modifiers  [{label, factor}] optional multipliers (GIC ×2/3 ...)
 *
 * A completed case stores the work done (`work_items`) and its `points`.
 * A doctor's ratio on a task is min(1, cases/required) for 'count',
 * min(1, points/min_points) for 'points', the lower of the two for 'both';
 * the department result is the weighted average, passed when it reaches the
 * department's `pass_percent`.
 *
 * TEMPLATES are the tables a case-sheet type pre-fills in the add-task form;
 * the user edits counts/points/weights and switches rows on or off there.
 */
class TaskScoring
{
    public const MEASURES = ['count', 'points', 'both'];

    private const FILLINGS = [
        ['label' => 'Class I / III', 'points' => 10],
        ['label' => 'Class II / IV', 'points' => 15],
        ['label' => 'Class V / pit / extension', 'points' => 5],
        ['label' => 'Class II MOD', 'points' => 20],
        ['label' => 'C.C (كيس شيت)', 'points' => 25],
    ];

    /**
     * Dental prosthetics (2026-10-14, by request): the fourth- and
     * fifth-stage rows of the sheet together (the other stage's rows are
     * switched off in the form). Each case is graded on its case sheet's
     * steps; a row's points are those step grades, up to each step's max.
     */
    private static function prosthodontics(): array
    {
        $partial = self::steps(ProsthodonticsForm::stages(), true);
        $complete = self::steps(CompleteDentureForm::stages(), false);
        $row = fn ($title, $count, $sheet, $steps) => [
            'enabled' => true,
            'stage' => str_contains($title, 'الرابع') ? 4 : 5,
            'title' => $title,
            'required_count' => $count,
            'case_sheet' => $sheet,
            'scoring' => ['measure' => 'both', 'min_points' => null, 'weight' => null, 'options' => [], 'modifiers' => [], 'steps' => $steps],
        ];

        return [
            'pass_percent' => 100,
            'rows' => [
                $row('طقم متحرك جزئي (FEE) — الرابع', 2, 'partial_denture', $partial),
                $row('طقم متحرك جزئي (Bounded) — الرابع', 1, 'partial_denture', $partial),
                $row('Repair or relining — الرابع', 1, 'prosthodontics', $partial),
                $row('طقم كامل علوي وسفلي (قطعتين) — الخامس', 1, 'complete_denture', $complete),
                $row('طقم كامل منفرد علوي أو سفلي — الخامس', 1, 'complete_denture', $complete),
                $row('طقم متحرك جزئي — الخامس', 1, 'partial_denture', $partial),
                $row('طقم متحرك مرن (flexible) — الخامس', 1, 'partial_denture', $partial),
            ],
        ];
    }

    /**
     * Periodontics: the department's 2025-2026 requirements (2026-10-16, by
     * request), one row per kind of case, each on the chosen case sheet
     * (Periodontal or Advanced). The earlier 1000-point and two-session rows
     * stay in the table switched off, for a department that still uses them.
     */
    private static function periodontics(): array
    {
        $case = fn ($title, $count, $stage) => self::row($title, $count, 'count', null, null, stage: $stage);
        $off = fn (array $row) => ['enabled' => false, 'off' => true] + $row;

        return [
            'pass_percent' => 100,
            'rows' => [
                $case('Scaling and polishing (simple cases) — الرابع', 5, 4),
                $case('Scaling and polishing (moderate cases) — الرابع', 3, 4),
                $case('Scaling and polishing (severe cases) — الرابع', 2, 4),
                $case('Index scoring — الرابع', 3, 4),
                $case('Motivation — الرابع', 3, 4),
                $off(self::row('علاج مرضى اللثة (1000 نقطة) — الرابع', 20, 'points', 1000, null, [
                    ['label' => 'Case sheet', 'points' => 10],
                    ['label' => 'Motivation + instruction', 'points' => 10],
                    ['label' => 'Indices (Bleeding on probing + Calculus index)', 'points' => 20],
                    ['label' => 'Diagnosis', 'points' => 20],
                    ['label' => 'Scaling', 'points' => 40],
                    ['label' => 'Clinical case difficulty (Calculus index total score)', 'points' => 360],
                ], stage: 4, graded: true)),
                $case('Scaling and polishing (severe cases) — الخامس', 12, 5),
                $case('Root planing — الخامس', 3, 5),
                $case('Periodontal surgery — الخامس', 1, 5),
                $off(self::row('علاج مريض لثة بواقع جلستين — الخامس', 4, 'count', null, null, stage: 5,
                    checklist: ['الجلسة الأولى', 'الجلسة الثانية'])),
            ],
        ];
    }

    /**
     * Orthodontics (2026-10-14, by request). Fourth stage: every lab form of
     * the curriculum, one row each (names editable). Fifth stage: a record
     * session with all its parts, and a seminar.
     */
    private static function orthodontics(): array
    {
        $lab = ['Adams clasp', 'Ball-ended clasp', 'Labial bow', 'Finger spring', 'Z-spring', 'T-spring', 'Coffin spring', 'Canine retractor', 'Removable appliance (acrylic base)'];

        return [
            'pass_percent' => 100,
            'rows' => [
                ...array_map(fn ($name) => self::row("شكل مختبري: $name — الرابع", 1, 'count', null, null, sheet: 'orthodontics', stage: 4), $lab),
                self::row('Record session — الخامس', 1, 'count', null, null, sheet: 'orthodontics', stage: 5, checklist: [
                    'Case sheet filling',
                    'Full set of extra-oral and intra-oral photographs',
                    'Impressions (upper and lower arches)',
                    'Properly made and trimmed study models',
                    'Case presentation',
                ]),
                self::row('سمنار — الخامس', 1, 'count', null, null, sheet: 'orthodontics', stage: 5),
            ],
        ];
    }

    /**
     * Operative dentistry (2026-10-14, by request): the minimum fillings of
     * each class per stage, the rest of the total as any class, and the
     * root fillings, whose case sheet opens with its Endodontics section on.
     */
    private static function operative(): array
    {
        $count = fn ($title, $n, $stage) => self::row($title, $n, 'count', null, null, sheet: 'operative', stage: $stage);
        $endo = fn ($title, $n, $stage) => self::row($title, $n, 'count', null, null, sheet: 'operative', stage: $stage, endo: true);

        return [
            'pass_percent' => 100,
            'rows' => [
                $count('Cl I (amalgam) — الرابع', 2, 4),
                $count('Cl I (composite) — الرابع', 1, 4),
                $count('Cl II (amalgam) — الرابع', 1, 4),
                $count('Cl II (composite) — الرابع', 1, 4),
                $count('Cl III — الرابع', 1, 4),
                $count('Cl IV — الرابع', 1, 4),
                $count('Cl V — الرابع', 1, 4),
                $count('حشوات أي صنف لإكمال المجموع 10 — الرابع', 2, 4),
                $endo('Endo Lab (حشوة جذر) — الرابع', 3, 4),
                $count('Cl II (amalgam) — الخامس', 3, 5),
                $count('Cl II (composite) — الخامس', 3, 5),
                $count('Cl III — الخامس', 1, 5),
                $count('Cl IV — الخامس', 1, 5),
                $count('Cl V — الخامس', 1, 5),
                $count('Compound filling — الخامس', 1, 5),
                $count('حشوات أي صنف لإكمال المجموع 13 — الخامس', 3, 5),
                $count('Fixed prosthesis (crown) — الخامس', 1, 5),
                $endo('Endo (حشوة جذر، أمامي أو ضاحك) — الخامس', 1, 5),
            ],
        ];
    }

    private static function steps(array $stages, bool $withDiagnosis): array
    {
        $steps = $withDiagnosis ? [['key' => 'diagnosis', 'label' => 'Diagnosis', 'max' => 10, 'enabled' => true]] : [];
        foreach ($stages as $stage) {
            $steps[] = ['key' => $stage['key'], 'label' => $stage['label'], 'max' => 10, 'enabled' => true];
        }

        return $steps;
    }

    /** type_code => ['pass_percent' => .., 'rows' => [..]] */
    public static function templates(): array
    {
        return [
            'pediatric' => [
                'pass_percent' => 100,
                'rows' => [
                    self::row('Prophylaxis', 2, 'both', 6, null, [['label' => 'Prophylaxis', 'points' => 3]], sheet: 'prevention'),
                    self::row('Fluoride', 2, 'both', 4, null, [['label' => 'Fluoride', 'points' => 2]], sheet: 'prevention'),
                    self::row('Fillings', 4, 'both', 50, null, self::FILLINGS, sheet: 'operative'),
                    self::row('Extraction', 2, 'both', 10, null, [['label' => 'Extraction', 'points' => 5]], sheet: 'surgery'),
                    self::row('Fixed pulpotomy', 1, 'both', 15, null, [['label' => 'Fixed pulpotomy', 'points' => 15]], sheet: 'operative'),
                ],
            ],
            'prevention' => [
                'pass_percent' => 30,
                'rows' => [
                    self::row('Prophylaxis with fluoride', 8, 'count', null, 5),
                    self::row('Nutritional assessment', 2, 'count', null, 5),
                    self::row('Fissure sealant + health education', 10, 'points', 25, 10, [
                        ['label' => 'Fissure sealant (per tooth)', 'points' => 2],
                        ['label' => 'Program for health education', 'points' => 5],
                    ]),
                    self::row('Secondary prevention', 20, 'points', 200, 75, [
                        ['label' => 'Class I / III', 'points' => 10],
                        ['label' => 'Class II / IV', 'points' => 15],
                        ['label' => 'Any extension', 'points' => 5],
                        ['label' => 'Class V / pits', 'points' => 5],
                        ['label' => 'Extraction', 'points' => 5],
                    ], [
                        ['label' => 'GIC filling', 'factor' => 0.6667],
                        ['label' => 'TF filling', 'factor' => 0.5],
                        ['label' => 'Within finished case', 'factor' => 1.5],
                    ], sheet: 'operative'),
                    self::row('Finished case + report', 2, 'count', null, 5),
                ],
            ],
            'prosthodontics' => self::prosthodontics(),
            'periodontal' => self::periodontics(),
            'advanced_periodontal' => self::periodontics(),
            'orthodontics' => self::orthodontics(),
            'operative' => self::operative(),
            'partial_denture' => self::prosthodontics(),
            'complete_denture' => self::prosthodontics(),
        ];
    }

    /** Templates keyed by case_sheet_types.id, for the add-task forms. */
    public static function templatesByTypeId(): array
    {
        $templates = self::templates();
        $ids = CaseSheetType::where('is_active', true)->pluck('id', 'type_code');

        return $ids->only(array_keys($templates))
            ->flip()
            ->map(fn ($code, $typeId) => [
                ...$templates[$code],
                // Each row's own case sheet, defaulting to the chosen type.
                'rows' => array_map(fn ($row) => [
                    ...collect($row)->except('case_sheet')->all(),
                    'case_sheet_type_id' => $ids[$row['case_sheet'] ?? ''] ?? $typeId,
                ], $templates[$code]['rows']),
            ])
            ->all();
    }

    /**
     * $sheet: the case-sheet type_code this row's task uses; null keeps the chosen one.
     * $stage: 4 or 5 when the row belongs to one stage only (the form
     * switches off the other stage's rows). $graded: options are items the
     * supervisor grades up to their points. $checklist: parts that must all
     * be ticked to complete a case. $endo: a root filling, whose case sheet
     * opens with its Endodontics section on.
     */
    private static function row(string $title, int $count, string $measure, ?float $minPoints, ?float $weight, array $options = [], array $modifiers = [], ?string $sheet = null, ?int $stage = null, bool $graded = false, array $checklist = [], bool $endo = false): array
    {
        return [
            'enabled' => true,
            'stage' => $stage,
            'title' => $title,
            'required_count' => $count,
            'case_sheet' => $sheet,
            'scoring' => [
                'measure' => $measure,
                'min_points' => $minPoints,
                'weight' => $weight,
                'options' => $options,
                'modifiers' => $modifiers,
                'graded' => $graded,
                'checklist' => array_map(fn ($label) => ['label' => $label], $checklist),
                'endo' => $endo,
            ],
        ];
    }

    /** Validation rules for a `scoring` payload under $prefix ('scoring' or 'rows.*.scoring'). */
    public static function rules(string $prefix): array
    {
        return [
            $prefix => ['nullable', 'array'],
            "$prefix.measure" => ["required_with:$prefix", 'in:'.implode(',', self::MEASURES)],
            "$prefix.min_points" => ['nullable', 'numeric', 'min:0'],
            "$prefix.weight" => ['nullable', 'numeric', 'min:0', 'max:100'],
            "$prefix.options" => ['nullable', 'array', 'max:30'],
            "$prefix.options.*.label" => ['required', 'string', 'max:100'],
            "$prefix.options.*.points" => ['required', 'numeric', 'min:0'],
            "$prefix.options.*.enabled" => ['boolean'],
            "$prefix.modifiers" => ['nullable', 'array', 'max:10'],
            "$prefix.modifiers.*.label" => ['required', 'string', 'max:100'],
            "$prefix.modifiers.*.factor" => ['required', 'numeric', 'min:0', 'max:10'],
            "$prefix.steps" => ['nullable', 'array', 'max:20'],
            "$prefix.steps.*.key" => ['required', 'string', 'max:30'],
            "$prefix.steps.*.label" => ['required', 'string', 'max:100'],
            "$prefix.steps.*.max" => ['required', 'numeric', 'min:0'],
            "$prefix.steps.*.enabled" => ['boolean'],
            "$prefix.steps.*.custom" => ['boolean'],
            "$prefix.graded" => ['boolean'],
            "$prefix.checklist" => ['nullable', 'array', 'max:20'],
            "$prefix.checklist.*.label" => ['required', 'string', 'max:150'],
            "$prefix.checklist.*.scored" => ['boolean'],
            "$prefix.checklist.*.max" => ['nullable', 'numeric', 'min:0'],
            "$prefix.endo" => ['boolean'],
            "$prefix.points_off" => ['boolean'],
        ];
    }

    /** Keeps only the known keys, with numbers as numbers. */
    public static function normalize(?array $scoring): ?array
    {
        if (! $scoring) {
            return null;
        }
        // Points switched off (2026-10-16, by request): the kinds of work,
        // checklist and steps stay, counted as cases with no points.
        $off = (bool) ($scoring['points_off'] ?? false);
        $measure = ! $off && in_array($scoring['measure'] ?? null, self::MEASURES, true) ? $scoring['measure'] : 'count';
        $num = fn ($v) => $v === null || $v === '' ? null : (float) $v;

        return [
            'measure' => $measure,
            'min_points' => $measure === 'count' ? null : $num($scoring['min_points'] ?? null),
            'weight' => $num($scoring['weight'] ?? null),
            'options' => collect($scoring['options'] ?? [])->map(fn ($o) => [
                'label' => (string) $o['label'],
                'points' => (float) $o['points'],
                // Switched off in the setup (2026-10-16, by request): kept but not offered.
                'enabled' => (bool) ($o['enabled'] ?? true),
            ])->values()->all(),
            'modifiers' => collect($scoring['modifiers'] ?? [])->map(fn ($m) => [
                'label' => (string) $m['label'],
                'factor' => (float) $m['factor'],
            ])->values()->all(),
            // Case-sheet steps graded on the sheet (prosthodontics).
            'steps' => collect($scoring['steps'] ?? [])->map(fn ($st) => [
                'key' => (string) $st['key'],
                'label' => (string) $st['label'],
                'max' => (float) $st['max'],
                'enabled' => (bool) ($st['enabled'] ?? true),
                // Added by hand (2026-10-16): not on the sheet, graded on the task.
                'custom' => (bool) ($st['custom'] ?? false),
            ])->values()->all(),
            'graded' => (bool) ($scoring['graded'] ?? false),
            'checklist' => collect($scoring['checklist'] ?? [])
                // A part may carry a grade up to `max` (2026-10-16, by request).
                ->map(fn ($c) => ['label' => trim((string) $c['label'])] + (! empty($c['scored']) && is_numeric($c['max'] ?? null)
                    ? ['scored' => true, 'max' => (float) $c['max']]
                    : []))
                ->filter(fn ($c) => $c['label'] !== '')
                ->values()->all(),
            'endo' => (bool) ($scoring['endo'] ?? false),
            'points_off' => $off,
        ];
    }

    /** Whether a task's points are switched off (its setup is kept, unscored). */
    public static function pointsOff(?array $scoring): bool
    {
        return (bool) ($scoring['points_off'] ?? false);
    }

    /** Rules for the work done on a completed case. */
    public static function workItemRules(): array
    {
        return [
            'work_items' => ['nullable', 'array', 'max:50'],
            // An item is a kind of work (`option`) or a ticked checklist part (`check`).
            'work_items.*.option' => ['required_without:work_items.*.check', 'integer', 'min:0'],
            'work_items.*.check' => ['nullable', 'integer', 'min:0'],
            'work_items.*.qty' => ['nullable', 'integer', 'min:1', 'max:100'],
            'work_items.*.grade' => ['nullable', 'numeric', 'min:0'],
            'work_items.*.modifiers' => ['nullable', 'array'],
            'work_items.*.modifiers.*' => ['integer', 'min:0'],
        ];
    }

    /**
     * Resolves the submitted work (option/modifier indexes) against the
     * task's own setup into stored items with their points, so a client can
     * never send its own points.
     *
     * @return array{0: array, 1: float}|null [items, total], null when nothing was sent
     */
    public static function resolveWorkItems(Task $task, ?array $items, bool $requireChecklist = true): ?array
    {
        $checklist = $task->scoring['checklist'] ?? [];
        if ($items === null && ! $checklist) {
            return null;
        }
        $items ??= [];
        $options = $task->scoring['options'] ?? [];
        $modifiers = $task->scoring['modifiers'] ?? [];
        $off = self::pointsOff($task->scoring);
        $graded = ! $off && (bool) ($task->scoring['graded'] ?? false);

        // Every checklist part must be ticked to complete the case.
        $ticked = collect($items)->pluck('check')->filter(fn ($c) => $c !== null)->map(fn ($c) => (int) $c)->unique();
        $missing = collect($checklist)->keys()->diff($ticked);
        if ($requireChecklist && $missing->isNotEmpty()) {
            throw ValidationException::withMessages(['work_items' => 'أكمل كل البنود قبل الإنجاز: '.collect($checklist)->only($missing->all())->pluck('label')->implode('، ')]);
        }

        // A graded part scores the supervisor's grade, up to its max.
        $grades = collect($items)->filter(fn ($item) => ($item['check'] ?? null) !== null)->mapWithKeys(fn ($item) => [(int) $item['check'] => $item['grade'] ?? null]);
        $total = 0.0;
        $resolved = [];
        foreach (collect($checklist)->only($ticked->all()) as $ci => $c) {
            $part = ['option' => $c['label'], 'qty' => 1, 'modifiers' => [], 'points' => 0, 'check' => true];
            if (! $off && ! empty($c['scored'])) {
                $grade = is_numeric($grades[$ci] ?? null) ? max(0.0, min((float) $grades[$ci], (float) $c['max'])) : 0.0;
                $part = ['points' => $grade, 'grade' => $grade, 'max' => (float) $c['max'], 'scored' => true] + $part;
                $total += $grade;
            }
            $resolved[] = $part;
        }
        foreach (array_values($items) as $i => $item) {
            if (($item['check'] ?? null) !== null) {
                continue;
            }
            $option = $options[(int) $item['option']] ?? null;
            if (! $option || ! ($option['enabled'] ?? true)) {
                throw ValidationException::withMessages(["work_items.$i.option" => 'نوع العمل غير موجود بهذه المهمة.']);
            }
            $qty = max(1, (int) ($item['qty'] ?? 1));
            $factor = 1.0;
            $labels = [];
            foreach (array_unique($item['modifiers'] ?? []) as $m) {
                $modifier = $modifiers[(int) $m] ?? null;
                if (! $modifier) {
                    throw ValidationException::withMessages(["work_items.$i.modifiers" => 'المعامل غير موجود بهذه المهمة.']);
                }
                $factor *= (float) $modifier['factor'];
                $labels[] = $modifier['label'];
            }
            // A graded item scores the supervisor's grade, up to its points.
            $base = $off ? 0.0 : ($graded ? min((float) ($item['grade'] ?? 0), (float) $option['points']) : (float) $option['points'] * $qty);
            $qty = $graded ? 1 : $qty;
            $points = round($base * $factor, 2);
            $total += $points;
            $resolved[] = [
                'option' => $option['label'],
                'qty' => $qty,
                'modifiers' => $labels,
                'points' => $points,
                ...($graded ? ['grade' => $base] : []),
            ];
        }

        return [$resolved, round($total, 2)];
    }

    /**
     * One doctor's result on a department's tasks, or null when none of
     * them is scored and the department has no pass percentage.
     *
     * @param  Collection<int, Task>  $tasks
     * @param  Collection<int, TaskInstance>  $instances  this doctor's own
     */
    public static function doctorResult(Collection $tasks, Collection $instances, $passPercent): ?array
    {
        if ($passPercent === null && $tasks->every(fn ($t) => empty($t->scoring))) {
            return null;
        }

        $anyWeight = $tasks->contains(fn ($t) => ($t->scoring['weight'] ?? null) !== null);
        $weighted = 0.0;
        $weights = 0.0;
        $rows = [];

        foreach ($tasks as $task) {
            $s = $task->scoring ?? [];
            $measure = $s['measure'] ?? 'count';
            $done = $instances->where('task_id', $task->id)->where('status', 'completed');
            $cases = $done->count();
            $points = round((float) $done->sum('points'), 2);
            $required = (int) $task->required_count;
            $minPoints = self::stepsMax($s) !== null ? self::stepsMax($s) * $required : ($s['min_points'] ?? null);

            $caseRatio = $required > 0 ? min(1, $cases / $required) : 1;
            $pointRatio = $minPoints ? min(1, $points / $minPoints) : 1;
            $ratio = match ($measure) {
                'points' => $pointRatio,
                'both' => min($caseRatio, $pointRatio),
                default => $caseRatio,
            };

            $weight = $anyWeight ? (float) ($s['weight'] ?? 0) : 1.0;
            $weighted += $ratio * $weight;
            $weights += $weight;

            $rows[] = [
                'task_id' => $task->id,
                'title' => $task->title,
                'measure' => $measure,
                'cases' => $cases,
                'required_count' => $required,
                'points' => $points,
                'min_points' => $minPoints,
                'weight' => $anyWeight ? $weight : null,
                'percent' => round($ratio * 100, 1),
            ];
        }

        $percent = $weights > 0 ? round($weighted / $weights * 100, 1) : 0.0;
        $pass = $passPercent === null ? 100.0 : (float) $passPercent;

        return [
            'percent' => $percent,
            'pass_percent' => $pass,
            'passed' => $percent + 0.0001 >= $pass,
            'tasks' => $rows,
        ];
    }

    /** Extra rules for the add-task table (one task per enabled row). */
    public static function tableRules(): array
    {
        return [
            'rows' => ['nullable', 'array', 'max:30'],
            'rows.*.enabled' => ['boolean'],
            'rows.*.title' => ['required', 'string', 'max:255'],
            'rows.*.required_count' => ['required', 'integer', 'min:1'],
            'rows.*.case_sheet_type_id' => ['nullable', 'exists:case_sheet_types,id'],
            ...self::rules('rows.*.scoring'),
            'pass_percent' => ['nullable', 'numeric', 'min:0', 'max:100'],
        ];
    }

    /**
     * Saves a validated task payload: one task, or one task per enabled
     * table row sharing the payload's other fields. Applies `pass_percent`
     * to the department. Returns the created tasks.
     *
     * @return Collection<int, Task>
     */
    public static function createTasks(array $validated): Collection
    {
        $rows = $validated['rows'] ?? null;
        $passPercent = array_key_exists('pass_percent', $validated) ? $validated['pass_percent'] : false;
        $base = collect($validated)->except(['rows', 'pass_percent', 'scoring'])->all();

        if ($rows === null) {
            $tasks = collect([Task::create([...$base, 'scoring' => self::normalize($validated['scoring'] ?? null)])]);
        } else {
            $enabled = collect($rows)->filter(fn ($r) => $r['enabled'] ?? true)->values();
            if ($enabled->isEmpty()) {
                throw ValidationException::withMessages(['rows' => 'فعّل خانة وحدة على الأقل من الجدول.']);
            }
            $tasks = $enabled->map(fn ($r) => Task::create([
                ...$base,
                'title' => $r['title'],
                'required_count' => (int) $r['required_count'],
                'case_sheet_type_id' => $r['case_sheet_type_id'] ?? $base['case_sheet_type_id'],
                'scoring' => self::normalize($r['scoring'] ?? null),
            ]));
        }

        if ($passPercent !== false) {
            self::setPassPercent((int) $base['department_id'], $passPercent);
        }

        return $tasks;
    }

    /**
     * A doctor's result on every scored department of their stage, for the
     * doctor progress pages: [{department_id, department, score}].
     */
    public static function doctorResults(Doctor $doctor, ?int $academicSessionId): array
    {
        $departments = Department::where('stage_id', $doctor->stage_id)->orderBy('name')->get(['id', 'name', 'pass_percent']);
        $tasks = Task::where('stage_id', $doctor->stage_id)
            ->whereIn('department_id', $departments->pluck('id'))
            ->when($academicSessionId, fn ($q) => $q->where(
                fn ($q2) => $q2->where('academic_session_id', $academicSessionId)->orWhereNull('academic_session_id')
            ))
            ->orderBy('title')
            ->get(['id', 'title', 'department_id', 'required_count', 'scoring']);
        $instances = TaskInstance::where('doctor_id', $doctor->id)
            ->whereIn('task_id', $tasks->pluck('id'))
            ->get(['id', 'task_id', 'status', 'points']);

        return $departments->map(fn ($d) => [
            'department_id' => $d->id,
            'department' => $d->name,
            'score' => self::doctorResult($tasks->where('department_id', $d->id)->values(), $instances, $d->pass_percent),
        ])->filter(fn ($r) => $r['score'] !== null)->values()->all();
    }

    /** Total max of a task's enabled steps, or null when it has none. */
    public static function stepsMax(?array $scoring): ?float
    {
        $steps = collect($scoring['steps'] ?? [])->where('enabled', true);

        return $steps->isEmpty() ? null : (float) $steps->sum('max');
    }

    /**
     * Points of a case graded by steps: each enabled step's grade on the
     * linked case sheet (stage_{key}_grade, diagnosis_grade), up to its
     * max. A step added by hand has no sheet column (2026-10-16): its grade
     * is entered on the task's points panel, kept in the instance's
     * work_items, and replaced by `$customGrades` (key => grade) when given.
     * Null when the task has no steps.
     *
     * @return array{0: array, 1: float}|null
     */
    public static function pointsFromCaseSheet(TaskInstance $instance, ?array $customGrades = null): ?array
    {
        $steps = collect($instance->task?->scoring['steps'] ?? [])->where('enabled', true);
        if ($steps->isEmpty() || self::pointsOff($instance->task?->scoring)) {
            return null;
        }
        $record = null;
        if ($steps->contains(fn ($step) => empty($step['custom']))) {
            $resource = CaseSheetResolver::resourceFor($instance);
            $model = CaseSheetResolver::modelFor($resource);
            $recordId = CaseSheetResolver::existingRecordId($resource, $instance->id);
            $record = $model && $recordId ? $model::find($recordId) : null;
        }
        $saved = collect($instance->work_items ?? [])->filter(fn ($item) => isset($item['step']))->pluck('points', 'step');

        $items = [];
        $total = 0.0;
        foreach ($steps as $step) {
            $custom = (bool) ($step['custom'] ?? false);
            if ($custom) {
                $raw = $customGrades !== null && array_key_exists($step['key'], $customGrades) ? $customGrades[$step['key']] : $saved->get($step['key']);
            } else {
                $column = $step['key'] === 'diagnosis' ? 'diagnosis_grade' : "stage_{$step['key']}_grade";
                $raw = $record?->getAttribute($column);
                // Signed off before the sheet had it (2026-10-18), see TaskSteps.
                if (! is_numeric($raw)) {
                    $raw = $instance->step_signoffs["s:{$step['key']}"]['grade'] ?? null;
                }
            }
            $grade = is_numeric($raw) ? max(0.0, min((float) $raw, (float) $step['max'])) : 0.0;
            $total += $grade;
            $items[] = [
                'option' => $step['label'],
                'qty' => 1,
                'modifiers' => [],
                'points' => round($grade, 2),
                'step' => $step['key'],
                'max' => (float) $step['max'],
                ...($custom ? ['custom' => true] : []),
            ];
        }

        return [$items, round($total, 2)];
    }

    /** Whether a task is a root filling (its case sheet opens with Endodontics on). */
    public static function isRootFilling(?Task $task): bool
    {
        return (bool) ($task?->scoring['endo'] ?? false);
    }

    public static function setPassPercent(int $departmentId, $passPercent): void
    {
        Department::whereKey($departmentId)->update([
            'pass_percent' => $passPercent === null || $passPercent === '' ? null : (float) $passPercent,
        ]);
    }
}
