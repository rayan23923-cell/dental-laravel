<?php

namespace App\Services;

use App\Models\Doctor;
use App\Models\PatientRegistration;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Notifications\TaskAssigned;
use Illuminate\Support\Facades\DB;

/**
 * Extracted from `TaskProgressController::start()` (admin/ajax/assign_task_ajax.php's
 * port) so the NFC lookup flow (`Api\TaskProgressController::start()`) can
 * reuse the exact same guard rails instead of a third divergent copy —
 * `Api\TaskInstanceController::store()` already skips these guards
 * entirely, which this extraction does not fix but does avoid repeating.
 *
 * Guards, unchanged from the original: `required_per_doctor` falls back to
 * `required_count` when unset; refuses once the doctor has already
 * completed their required number; lazily creates a single `pending`
 * instance when the global pool is empty rather than pre-creating them all.
 *
 * `$patientRegistration` is required (2026-08-26, the infectious-disease
 * screening feature) — every task instance is now stamped with the
 * specific patient it was started for, and `PatientScreeningGate` refuses
 * to let this proceed until that patient's registration is confirmed
 * `screening_status === 'clear'` by a lab/reception scan.
 */
class TaskStarter
{
    /**
     * @throws TaskStartException
     * @throws PatientScreeningException
     */
    public static function start(
        Task $task,
        Doctor $doctor,
        PatientRegistration $patientRegistration,
        ?string $notes,
        ?int $assignedByUserId
    ): TaskInstance {
        PatientScreeningGate::ensureClear($patientRegistration);

        $requiredForDoctor = (int) ($task->required_per_doctor ?: $task->required_count);

        if ($requiredForDoctor === 0) {
            throw new TaskStartException('This task does not require any cases for this doctor.');
        }

        $completedForDoctor = TaskInstance::where('task_id', $task->id)
            ->where('doctor_id', $doctor->id)
            ->where('status', 'completed')
            ->count();

        if ($completedForDoctor >= $requiredForDoctor) {
            throw new TaskStartException('This doctor has already met the required count for this task.');
        }

        DB::transaction(function () use ($task, $doctor, $patientRegistration, $notes, $assignedByUserId, $requiredForDoctor, $completedForDoctor) {
            $pending = TaskInstance::where('task_id', $task->id)->where('status', 'pending')->first();

            if (! $pending) {
                $assignedForDoctor = TaskInstance::where('task_id', $task->id)
                    ->where('doctor_id', $doctor->id)
                    ->where('status', 'assigned')
                    ->count();

                if (max(0, $requiredForDoctor - ($completedForDoctor + $assignedForDoctor)) <= 0) {
                    throw new TaskStartException('This doctor has already met the required count for this task.');
                }

                $pending = TaskInstance::create(['task_id' => $task->id, 'status' => 'pending']);
            }

            $pending->update([
                'doctor_id' => $doctor->id,
                'patient_registration_id' => $patientRegistration->id,
                'status' => 'assigned',
                'assigned_date' => now(),
                'notes' => $notes,
                'assigned_by' => $assignedByUserId,
            ]);
        });

        $instance = TaskInstance::where('task_id', $task->id)
            ->where('doctor_id', $doctor->id)
            ->where('status', 'assigned')
            ->latest('id')
            ->firstOrFail();

        // Outside the transaction so a mail failure can't roll back the
        // assignment — same reasoning as the original controller method.
        $instance->load('task.department');
        Notifier::send($doctor, new TaskAssigned($instance));
        // Second, independent delivery path — inert until a real Firebase
        // project is configured (see PushNotifier's docblock).
        PushNotifier::send($doctor, 'مهمة جديدة', "تم بدء مهمة \"{$instance->task->title}\" لك.", [
            'task_instance_id' => (string) $instance->id,
        ]);

        return $instance;
    }
}
