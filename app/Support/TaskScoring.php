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

    /** type_code => ['pass_percent' => .., 'rows' => [..]] */
    public static function templates(): array
    {
        return [
            'pediatric' => [
                'pass_percent' => 100,
                'rows' => [
                    self::row('Prophylaxis', 2, 'both', 6, null, [['label' => 'Prophylaxis', 'points' => 3]]),
                    self::row('Fluoride', 2, 'both', 4, null, [['label' => 'Fluoride', 'points' => 2]]),
                    self::row('Fillings', 4, 'both', 50, null, self::FILLINGS),
                    self::row('Extraction', 2, 'both', 10, null, [['label' => 'Extraction', 'points' => 5]]),
                    self::row('Fixed pulpotomy', 1, 'both', 15, null, [['label' => 'Fixed pulpotomy', 'points' => 15]]),
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
                    ]),
                    self::row('Finished case + report', 2, 'count', null, 5),
                ],
            ],
        ];
    }

    /** Templates keyed by case_sheet_types.id, for the add-task forms. */
    public static function templatesByTypeId(): array
    {
        $templates = self::templates();

        return CaseSheetType::whereIn('type_code', array_keys($templates))
            ->pluck('type_code', 'id')
            ->map(fn ($code) => $templates[$code])
            ->all();
    }

    private static function row(string $title, int $count, string $measure, ?float $minPoints, ?float $weight, array $options = [], array $modifiers = []): array
    {
        return [
            'enabled' => true,
            'title' => $title,
            'required_count' => $count,
            'scoring' => [
                'measure' => $measure,
                'min_points' => $minPoints,
                'weight' => $weight,
                'options' => $options,
                'modifiers' => $modifiers,
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
            "$prefix.modifiers" => ['nullable', 'array', 'max:10'],
            "$prefix.modifiers.*.label" => ['required', 'string', 'max:100'],
            "$prefix.modifiers.*.factor" => ['required', 'numeric', 'min:0', 'max:10'],
        ];
    }

    /** Keeps only the known keys, with numbers as numbers. */
    public static function normalize(?array $scoring): ?array
    {
        if (! $scoring) {
            return null;
        }
        $measure = in_array($scoring['measure'] ?? null, self::MEASURES, true) ? $scoring['measure'] : 'count';
        $num = fn ($v) => $v === null || $v === '' ? null : (float) $v;

        return [
            'measure' => $measure,
            'min_points' => $measure === 'count' ? null : $num($scoring['min_points'] ?? null),
            'weight' => $num($scoring['weight'] ?? null),
            'options' => collect($scoring['options'] ?? [])->map(fn ($o) => [
                'label' => (string) $o['label'],
                'points' => (float) $o['points'],
            ])->values()->all(),
            'modifiers' => collect($scoring['modifiers'] ?? [])->map(fn ($m) => [
                'label' => (string) $m['label'],
                'factor' => (float) $m['factor'],
            ])->values()->all(),
        ];
    }

    /** Rules for the work done on a completed case. */
    public static function workItemRules(): array
    {
        return [
            'work_items' => ['nullable', 'array', 'max:50'],
            'work_items.*.option' => ['required', 'integer', 'min:0'],
            'work_items.*.qty' => ['nullable', 'integer', 'min:1', 'max:100'],
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
    public static function resolveWorkItems(Task $task, ?array $items): ?array
    {
        if ($items === null) {
            return null;
        }
        $options = $task->scoring['options'] ?? [];
        $modifiers = $task->scoring['modifiers'] ?? [];

        $resolved = [];
        $total = 0.0;
        foreach (array_values($items) as $i => $item) {
            $option = $options[(int) $item['option']] ?? null;
            if (! $option) {
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
            $points = round((float) $option['points'] * $qty * $factor, 2);
            $total += $points;
            $resolved[] = [
                'option' => $option['label'],
                'qty' => $qty,
                'modifiers' => $labels,
                'points' => $points,
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
            $minPoints = $s['min_points'] ?? null;

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

    public static function setPassPercent(int $departmentId, $passPercent): void
    {
        Department::whereKey($departmentId)->update([
            'pass_percent' => $passPercent === null || $passPercent === '' ? null : (float) $passPercent,
        ]);
    }
}
