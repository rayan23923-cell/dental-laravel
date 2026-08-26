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
        static::created(function ($model) {
            ActivityLogger::log('create', class_basename($model), static::activityLabel($model).' created', $model->getKey());
        });

        static::updated(function ($model) {
            ActivityLogger::log('update', class_basename($model), static::activityLabel($model).' updated', $model->getKey(), $model->getChanges());
        });

        static::deleted(function ($model) {
            ActivityLogger::log('delete', class_basename($model), static::activityLabel($model).' deleted', $model->getKey());
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
