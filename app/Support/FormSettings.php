<?php

namespace App\Support;

use App\Models\ClinicSetting;

/**
 * "إعدادات النماذج" (2026-10-22, by request): which case-sheet forms the
 * students use (electronic, paper or both), whether they see their grades,
 * and the supervisor code (see App\Services\SupervisorCode) with the
 * actions it may be used for on a student's account.
 */
class FormSettings
{
    /** What the code can do, each with the task-progress permission it needs. */
    public const ACTIONS = [
        'start' => 'start',
        'step' => 'track_steps',
        'finish' => 'finish',
    ];

    public const PERIODS = ['daily', 'hourly'];

    public static function get(): array
    {
        $settings = ClinicSetting::current();
        $actions = $settings->supervisor_code_actions;

        return [
            'electronic_forms_enabled' => (bool) ($settings->electronic_forms_enabled ?? true),
            'paper_forms_enabled' => (bool) ($settings->paper_forms_enabled ?? true),
            'show_grades_to_doctors' => (bool) ($settings->show_grades_to_doctors ?? true),
            'supervisor_code_enabled' => (bool) ($settings->supervisor_code_enabled ?? false),
            'supervisor_code_period' => in_array($settings->supervisor_code_period, self::PERIODS, true) ? $settings->supervisor_code_period : 'daily',
            // Nothing picked yet means every action.
            'supervisor_code_actions' => is_array($actions) ? array_values(array_intersect(array_keys(self::ACTIONS), $actions)) : array_keys(self::ACTIONS),
        ];
    }

    public static function rules(): array
    {
        return [
            'electronic_forms_enabled' => ['required', 'boolean'],
            'paper_forms_enabled' => ['required', 'boolean'],
            'show_grades_to_doctors' => ['required', 'boolean'],
            'supervisor_code_enabled' => ['required', 'boolean'],
            'supervisor_code_period' => ['required', 'in:'.implode(',', self::PERIODS)],
            'supervisor_code_actions' => ['present', 'array'],
            'supervisor_code_actions.*' => ['in:'.implode(',', array_keys(self::ACTIONS))],
        ];
    }

    public static function save(array $validated): array
    {
        if (! $validated['electronic_forms_enabled'] && ! $validated['paper_forms_enabled']) {
            throw \Illuminate\Validation\ValidationException::withMessages([
                'paper_forms_enabled' => 'فعّل نوعاً واحداً من النماذج على الأقل.',
            ]);
        }
        $validated['supervisor_code_actions'] = array_values(array_unique($validated['supervisor_code_actions']));
        ClinicSetting::current()->update($validated);

        return self::get();
    }

    /** Whether the code may be used for $action now. */
    public static function codeAllows(string $action): bool
    {
        $settings = self::get();

        return $settings['supervisor_code_enabled'] && in_array($action, $settings['supervisor_code_actions'], true);
    }

    public static function formTypeEnabled(string $formType): bool
    {
        return self::get()[$formType === 'paper' ? 'paper_forms_enabled' : 'electronic_forms_enabled'];
    }

    public static function gradesShownToDoctors(): bool
    {
        return self::get()['show_grades_to_doctors'];
    }

    /**
     * Blanks the grades and points of every case in $data (any array
     * carrying a `status`, an `instance_id`, a `slot` or a `signed` step),
     * for a viewer who should not see them. A task's top grade stays.
     */
    public static function withoutGrades(array $data): array
    {
        $isCard = collect(['status', 'instance_id', 'slot', 'signed'])->contains(fn ($key) => array_key_exists($key, $data));
        foreach ($data as $key => $value) {
            if (is_array($value)) {
                $data[$key] = self::withoutGrades($value);
            } elseif ($isCard && in_array($key, ['grade', 'points'], true)) {
                $data[$key] = null;
            }
        }
        if ($isCard && isset($data['work_items']) && is_array($data['work_items'])) {
            $data['work_items'] = array_map(fn ($item) => is_array($item) ? [...$item, 'points' => null] : $item, $data['work_items']);
        }

        return $data;
    }
}
