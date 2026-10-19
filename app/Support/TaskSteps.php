<?php

namespace App\Support;

use App\Models\Task;
use App\Models\TaskInstance;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Validation\ValidationException;

/**
 * A case's steps signed off one after another, each with its grade
 * (2026-10-18, by request: "تعرض جميع الخطوات المطلوبة للمهمة ويتم
 * تأشيرها واحد تلو الاخر ... ويتم توقيعها ووضع درجة لكل خطوة").
 *
 * The steps are the task's enabled graded steps (`scoring.steps`, keyed
 * `s:<key>`) then its checklist parts (`scoring.checklist`, keyed
 * `c:<index>`). A sign-off is kept on the instance (`step_signoffs`) and
 * also written where that step's grade already lives, so every place shows
 * the same result:
 *   - a case-sheet step (prosthodontics) on the sheet's own stage date,
 *     grade and signature, when the sheet exists; a stage the sheet signed
 *     counts as signed here too;
 *   - a step added by hand, or a checklist part, in the instance's
 *     `work_items` and `points`, as the points panel and the complete
 *     dialog store them.
 */
class TaskSteps
{
    /**
     * The task's steps in order, with their sign-off on $instance if any.
     *
     * @return array<int, array{key: string, label: string, max: ?float, signed: bool, grade: ?float, signed_by: ?string, signed_at: ?string, on_sheet: bool, extra: bool}>
     */
    public static function list(Task $task, ?TaskInstance $instance = null): array
    {
        $scoring = $task->scoring ?? [];
        $off = TaskScoring::pointsOff($scoring);
        $signoffs = $instance?->step_signoffs ?? [];
        $record = $instance ? self::sheetRecord($instance) : null;

        $steps = [];
        foreach (collect($scoring['steps'] ?? [])->where('enabled', true) as $step) {
            $steps[] = [
                'key' => 's:'.$step['key'],
                'label' => $step['label'],
                'max' => $off ? null : (float) $step['max'],
                'sheet' => empty($step['custom']) ? (string) $step['key'] : null,
            ];
        }
        // Steps a supervisor added to this case alone (2026-10-19, by request).
        foreach ($instance?->extra_steps ?? [] as $extra) {
            $steps[] = [
                'key' => 'x:'.$extra['key'],
                'label' => $extra['label'],
                'max' => $off ? null : (float) $extra['max'],
                'sheet' => null,
                'extra' => true,
            ];
        }
        foreach (array_values($scoring['checklist'] ?? []) as $i => $part) {
            $steps[] = [
                'key' => 'c:'.$i,
                'label' => $part['label'],
                'max' => ! $off && ! empty($part['scored']) ? (float) $part['max'] : null,
                'sheet' => null,
            ];
        }

        return array_map(function ($step) use ($signoffs, $record) {
            $own = $signoffs[$step['key']] ?? null;
            $sheet = $step['sheet'] !== null && $record ? self::sheetValues($record, $step['sheet']) : null;
            $signedOnSheet = filled($sheet['signature'] ?? null);
            $grade = $sheet && is_numeric($sheet['grade']) ? (float) $sheet['grade'] : (isset($own['grade']) ? (float) $own['grade'] : null);

            return [
                'key' => $step['key'],
                'label' => $step['label'],
                'max' => $step['max'],
                'signed' => $own !== null || $signedOnSheet,
                'grade' => $step['max'] === null ? null : $grade,
                'signed_by' => $own['signed_by'] ?? ($signedOnSheet ? $sheet['signature'] : null),
                'signed_at' => $own['signed_at'] ?? null,
                // A stage the case sheet has its own date/grade/signature for.
                'on_sheet' => $step['sheet'] !== null,
                'extra' => ! empty($step['extra']),
            ];
        }, $steps);
    }

    /** Whether the task has any steps to sign. */
    public static function has(?Task $task): bool
    {
        $scoring = $task?->scoring ?? [];

        return collect($scoring['steps'] ?? [])->where('enabled', true)->isNotEmpty() || ! empty($scoring['checklist']);
    }

    /** Signs the next step with its grade, as $signerName. */
    public static function sign(TaskInstance $instance, string $key, $grade, string $signerName): void
    {
        $instance->loadMissing('task');
        $steps = self::list($instance->task, $instance);
        $index = collect($steps)->search(fn ($s) => $s['key'] === $key);
        if ($index === false) {
            throw ValidationException::withMessages(['step' => 'هذه الخطوة غير موجودة بهذه المهمة.']);
        }
        $step = $steps[$index];
        if ($step['signed']) {
            throw ValidationException::withMessages(['step' => 'هذه الخطوة موقّعة مسبقاً.']);
        }
        $before = collect($steps)->take($index)->first(fn ($s) => ! $s['signed']);
        if ($before) {
            throw ValidationException::withMessages(['step' => "وقّع خطوة \"{$before['label']}\" أولاً."]);
        }
        if ($step['max'] !== null) {
            if (! is_numeric($grade)) {
                throw ValidationException::withMessages(['grade' => 'ضع درجة هذه الخطوة.']);
            }
            if ((float) $grade < 0 || (float) $grade > $step['max']) {
                throw ValidationException::withMessages(['grade' => "الدرجة بين 0 و {$step['max']}."]);
            }
            $grade = (float) $grade;
        } else {
            $grade = null;
        }

        $signoffs = $instance->step_signoffs ?? [];
        $signoffs[$key] = ['grade' => $grade, 'signed_by' => $signerName, 'signed_at' => now()->format('Y-m-d H:i')];
        $instance->step_signoffs = $signoffs;
        $instance->save();

        self::sync($instance, $key, $grade, $signerName);
    }

    /** Takes back the last signed step, unless the case sheet's own signature holds it. */
    public static function undo(TaskInstance $instance, string $key): void
    {
        $instance->loadMissing('task');
        $last = collect(self::list($instance->task, $instance))->where('signed', true)->last();
        $signoffs = $instance->step_signoffs ?? [];
        if (! $last || $last['key'] !== $key || ! isset($signoffs[$key])) {
            throw ValidationException::withMessages(['step' => 'يمكن إلغاء آخر خطوة موقّعة فقط.']);
        }
        $sheetKey = str_starts_with($key, 's:') ? substr($key, 2) : null;
        $record = self::sheetRecord($instance);
        if ($sheetKey !== null && $record && filled(self::sheetValues($record, $sheetKey)['signature'] ?? null)) {
            throw ValidationException::withMessages(['step' => 'هذه الخطوة موقّعة في النموذج ولا يمكن إلغاؤها.']);
        }

        unset($signoffs[$key]);
        $instance->step_signoffs = $signoffs ?: null;
        $instance->save();

        self::sync($instance, $key, null, null);
    }

    /**
     * Adds a step with its own name and top grade to this case alone
     * (2026-10-19, by request: "امكانية اضافة خطوات اضافية مع اضافة تسميه
     * ودرجتها"). It is signed after the task's own steps.
     */
    public static function addExtra(TaskInstance $instance, string $label, float $max): void
    {
        $extras = $instance->extra_steps ?? [];
        $extras[] = ['key' => (collect($extras)->max('key') ?? 0) + 1, 'label' => $label, 'max' => $max];
        $instance->extra_steps = $extras;
        $instance->save();
        self::syncPoints($instance->fresh('task'));
    }

    /** Removes a step added to this case, unless it is already signed. */
    public static function removeExtra(TaskInstance $instance, string $key): void
    {
        $id = str_starts_with($key, 'x:') ? (int) substr($key, 2) : null;
        $extras = collect($instance->extra_steps ?? []);
        if ($id === null || ! $extras->contains('key', $id)) {
            throw ValidationException::withMessages(['step' => 'هذه الخطوة غير موجودة بهذه الحالة.']);
        }
        if (isset(($instance->step_signoffs ?? [])[$key])) {
            throw ValidationException::withMessages(['step' => 'ألغِ توقيع الخطوة أولاً.']);
        }
        $instance->extra_steps = $extras->reject(fn ($x) => $x['key'] === $id)->values()->all() ?: null;
        $instance->save();
        self::syncPoints($instance->fresh('task'));
    }

    /**
     * Recounts a case's points with its added steps: a step-graded task
     * through TaskScoring::pointsFromCaseSheet(), any other one as scored
     * work items next to its own work.
     */
    private static function syncPoints(TaskInstance $instance): void
    {
        $result = TaskScoring::pointsFromCaseSheet($instance);
        if ($result) {
            $instance->update(['work_items' => $result[0], 'points' => $result[1]]);

            return;
        }
        if (TaskScoring::pointsOff($instance->task?->scoring)) {
            return;
        }
        $items = collect($instance->work_items ?? [])->reject(fn ($item) => ! empty($item['extra']))->values();
        foreach ($instance->extra_steps ?? [] as $extra) {
            $grade = $instance->step_signoffs['x:'.$extra['key']]['grade'] ?? null;
            if ($grade === null) {
                continue;
            }
            $items->push([
                'option' => $extra['label'], 'qty' => 1, 'modifiers' => [], 'points' => (float) $grade,
                'grade' => (float) $grade, 'max' => (float) $extra['max'], 'scored' => true, 'check' => true,
                'step' => 'x:'.$extra['key'], 'extra' => true,
            ]);
        }
        $scored = $items->contains(fn ($item) => empty($item['check']) || ! empty($item['scored']));
        $instance->update([
            'work_items' => $items->all() ?: null,
            'points' => $scored ? round($items->sum('points'), 2) : $instance->points,
        ]);
    }

    /** Writes a step's grade where the rest of the app reads it. */
    private static function sync(TaskInstance $instance, string $key, ?float $grade, ?string $signerName): void
    {
        $scoring = $instance->task?->scoring ?? [];

        if (str_starts_with($key, 'x:')) {
            self::syncPoints($instance->fresh('task'));

            return;
        }

        if (str_starts_with($key, 's:')) {
            $stepKey = substr($key, 2);
            $step = collect($scoring['steps'] ?? [])->firstWhere('key', $stepKey);
            $record = empty($step['custom']) && $signerName !== null ? self::sheetRecord($instance) : null;
            if ($record && self::sheetValues($record, $stepKey) !== null) {
                $columns = self::sheetColumns($stepKey);
                $record->forceFill(array_filter([
                    $columns['date'] => blank($record->getAttribute($columns['date'])) ? now()->toDateString() : null,
                    $columns['grade'] => $grade !== null && blank($record->getAttribute($columns['grade'])) ? $grade : null,
                    $columns['signature'] => blank($record->getAttribute($columns['signature'])) ? CaseSheetSignatures::stamp($signerName) : null,
                ], fn ($v) => $v !== null))->save();
            }
            $result = TaskScoring::pointsFromCaseSheet($instance->fresh('task'), ! empty($step['custom']) ? [$stepKey => $grade] : null);
            if ($result) {
                $instance->update(['work_items' => $result[0], 'points' => $result[1]]);
            }

            return;
        }

        // A checklist part: ticked (with its grade) or taken back in work_items.
        $index = (int) substr($key, 2);
        $part = array_values($scoring['checklist'] ?? [])[$index] ?? null;
        if (! $part) {
            return;
        }
        $off = TaskScoring::pointsOff($scoring);
        $items = collect($instance->work_items ?? [])
            ->reject(fn ($item) => ! empty($item['check']) && ($item['option'] ?? null) === $part['label'])
            ->values()->all();
        if ($signerName !== null) {
            $item = ['option' => $part['label'], 'qty' => 1, 'modifiers' => [], 'points' => 0, 'check' => true];
            if (! $off && ! empty($part['scored'])) {
                $item = ['points' => (float) $grade, 'grade' => (float) $grade, 'max' => (float) $part['max'], 'scored' => true] + $item;
            }
            $items[] = $item;
        }
        $scored = ! $off && collect($items)->contains(fn ($item) => empty($item['check']) || ! empty($item['scored']));
        $instance->update([
            'work_items' => $items ?: null,
            'points' => $scored ? round(collect($items)->sum('points'), 2) : null,
        ]);
    }

    /** The case sheet linked to $instance, when it has been created. */
    private static function sheetRecord(TaskInstance $instance): ?Model
    {
        $resource = CaseSheetResolver::resourceFor($instance);
        $model = CaseSheetResolver::modelFor($resource);
        $id = $model ? CaseSheetResolver::existingRecordId($resource, $instance->id) : null;

        return $id ? $model::find($id) : null;
    }

    /** @return array{date: string, grade: string, signature: string} */
    private static function sheetColumns(string $stepKey): array
    {
        return $stepKey === 'diagnosis'
            ? ['date' => 'diagnosis_date', 'grade' => 'diagnosis_grade', 'signature' => 'diagnosis_instructor_signature']
            : ['date' => "stage_{$stepKey}_date", 'grade' => "stage_{$stepKey}_grade", 'signature' => "stage_{$stepKey}_signature"];
    }

    /** @return array{grade: mixed, signature: mixed}|null null when the sheet has no such stage */
    private static function sheetValues(Model $record, string $stepKey): ?array
    {
        $columns = self::sheetColumns($stepKey);
        if (! $record->isFillable($columns['signature'])) {
            return null;
        }

        return ['grade' => $record->getAttribute($columns['grade']), 'signature' => $record->getAttribute($columns['signature'])];
    }
}
