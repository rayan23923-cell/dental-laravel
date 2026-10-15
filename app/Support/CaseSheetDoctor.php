<?php

namespace App\Support;

use App\Models\Doctor;
use App\Models\TaskInstance;

/**
 * The doctor a case sheet belongs to (2026-10-15, by request): the sheet's
 * own doctor, else the doctor of the task case it was opened from. The form
 * shows that name instead of a "choose a doctor" picker, which only a new,
 * unlinked sheet offers.
 */
class CaseSheetDoctor
{
    /** @return array{id:int,name:string}|null */
    public static function linked(mixed $doctorId, mixed $taskInstanceId): ?array
    {
        $id = $doctorId ?: ($taskInstanceId ? TaskInstance::whereKey($taskInstanceId)->value('doctor_id') : null);
        $doctor = $id ? Doctor::find($id, ['id', 'name']) : null;

        return $doctor ? ['id' => $doctor->id, 'name' => $doctor->name] : null;
    }
}
