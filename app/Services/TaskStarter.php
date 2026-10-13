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
 * Guards: `required_count` is the per-doctor cap (the separate
 * `required_per_doctor` field was dropped, 2026-10-13, by request); refuses
 * once the doctor has already completed their required number; lazily creates a single `pending`
 * instance when the global pool is empty rather than pre-creating them all.
 *
 * `$patientRegistration` is optional (2026-10-12, by request): a task is
 * started from the case QR or by picking the doctor and task, without
 * scanning the patient's QR. When a patient is given, the instance is
 * stamped with it and `PatientScreeningGate` still refuses to proceed until
 * that registration is `screening_status === 'clear'`.
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
        ?PatientRegistration $patientRegistration,
        ?string $notes,
        ?int $assignedByUserId
    ): TaskInstance {
        if ($patientRegistration) {
            PatientScreeningGate::ensureClear($patientRegistration);
        }

        $requiredForDoctor = (int) $task->required_count;

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
                'patient_registration_id' => $patientRegistration?->id,
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

        // Push the newly-assigned treating doctor into any appointment
        // already booked for this patient/task (see AppointmentPatientSync's
        // own docblock) — appointments and task instances are otherwise
        // two disconnected subsystems that both reference PatientRegistration.
        if ($patientRegistration) {
            AppointmentPatientSync::syncForPatient($patientRegistration, $task->id);
        }

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
