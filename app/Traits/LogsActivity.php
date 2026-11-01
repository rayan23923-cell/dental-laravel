<?php

namespace App\Traits;

use App\Services\ActivityLogger;

/**
 * Auto-logs create/update/delete on the model to user_activity_log via
 * ActivityLogger, using the model's class basename as the "module" (e.g.
 * "Doctor", "Appointment"). Applied to the handful of high-value models
 * listed in README.md ("Activity logging" section) — not every model, to
 * keep the log signal-to-noise reasonable (lookup-table edits like
 * education types aren't logged).
 */
trait LogsActivity
{
    public static function bootLogsActivity(): void
    {
        // A model with activitySnapshot() (Payment, 2026-11-01) also keeps
        // what the record held, and an update its values before, so a
        // printed log still says what was added, changed or deleted.
        static::created(function ($model) {
            ActivityLogger::log('create', class_basename($model), static::activityLabel($model).' created', $model->getKey(),
                method_exists($model, 'activitySnapshot') ? ['snapshot' => $model->activitySnapshot()] : null);
        });

        static::updated(function ($model) {
            $changes = $model->getChanges();
            $data = method_exists($model, 'activitySnapshot')
                ? ['changes' => $changes, 'before' => array_intersect_key($model->getOriginal(), $changes), 'snapshot' => $model->activitySnapshot()]
                : $changes;
            ActivityLogger::log('update', class_basename($model), static::activityLabel($model).' updated', $model->getKey(), $data);
        });

        static::deleted(function ($model) {
            ActivityLogger::log('delete', class_basename($model), static::activityLabel($model).' deleted', $model->getKey(),
                method_exists($model, 'activitySnapshot') ? ['snapshot' => $model->activitySnapshot()] : null);
        });
    }

    private static function activityLabel($model): string
    {
        foreach (['name', 'full_name', 'title', 'patient_id', 'patient_name'] as $field) {
            if (! empty($model->{$field})) {
                return class_basename($model)." \"{$model->{$field}}\"";
            }
        }

        return class_basename($model)." #{$model->getKey()}";
    }
}
