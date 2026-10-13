<?php

namespace App\Services;

use App\Models\AcademicSession;
use App\Models\ClinicSetting;
use App\Models\Doctor;
use App\Models\Group;
use App\Models\Stage;
use Illuminate\Support\Facades\DB;

/**
 * Group "A" for every stage (2026-10-13, by request): each stage gets a
 * group named A in the current academic session, meeting on every day of
 * the week during the clinic's working hours, and every doctor of that
 * stage is put in it automatically — existing doctors by sync(), new ones
 * (or ones moved to another stage) as they are saved (see Doctor::booted).
 *
 * A doctor already placed in another group for the session by hand stays
 * there; only doctors with no group at all for the session are added.
 */
class DefaultGroups
{
    public const NAME = 'A';

    public const DAYS = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

    /** Ensures group A for every stage and fills it with the stage's ungrouped doctors. */
    public static function sync(): int
    {
        $sessionId = self::currentSessionId();
        $added = 0;

        foreach (Stage::pluck('id') as $stageId) {
            $group = self::ensureGroup((int) $stageId, $sessionId);

            $doctorIds = Doctor::where('stage_id', $stageId)
                ->when($sessionId, fn ($q) => $q->where(fn ($q2) => $q2
                    ->where('academic_session_id', $sessionId)
                    ->orWhereNull('academic_session_id')))
                ->pluck('id');

            foreach ($doctorIds as $doctorId) {
                $added += self::addIfUngrouped((int) $doctorId, $group, $sessionId) ? 1 : 0;
            }
        }

        return $added;
    }

    /** Puts one doctor in their stage's group A, unless already grouped for the session. */
    public static function assign(Doctor $doctor, bool $stageChanged = false): void
    {
        if (! $doctor->stage_id) {
            return;
        }

        $sessionId = $doctor->academic_session_id ?: self::currentSessionId();

        DB::transaction(function () use ($doctor, $sessionId, $stageChanged) {
            if ($stageChanged) {
                // A group belongs to one stage; membership of the old
                // stage's group for this session no longer makes sense.
                DB::table('doctor_group_members')
                    ->where('doctor_id', $doctor->id)
                    ->whereIn('group_id', Group::where('stage_id', '!=', $doctor->stage_id)->select('id'))
                    ->where(fn ($q) => $q->where('academic_session_id', $sessionId)->orWhereNull('academic_session_id'))
                    ->delete();
            }

            self::addIfUngrouped($doctor->id, self::ensureGroup((int) $doctor->stage_id, $sessionId), $sessionId);
        });
    }

    public static function ensureGroup(int $stageId, ?int $sessionId): Group
    {
        $group = Group::where('stage_id', $stageId)
            ->where('name', self::NAME)
            ->where(fn ($q) => $sessionId
                ? $q->where('academic_session_id', $sessionId)->orWhereNull('academic_session_id')
                : $q->whereNull('academic_session_id'))
            ->orderByRaw('academic_session_id is null')
            ->first();

        if ($group) {
            return $group;
        }

        [$start, $end] = self::workingHours();

        $group = Group::create(['name' => self::NAME, 'stage_id' => $stageId, 'academic_session_id' => $sessionId]);
        $group->slots()->createMany(array_map(
            fn ($day) => ['day' => $day, 'start_time' => $start, 'end_time' => $end],
            self::DAYS
        ));

        return $group;
    }

    /**
     * The clinic's working hours from settings ("8:00 - 14:00", "من 08:30 إلى 15:00"…),
     * or 08:00–14:00 when they are not written as two times.
     */
    public static function workingHours(): array
    {
        $text = (string) ClinicSetting::current()->clinic_working_hours;

        if (preg_match_all('/(\d{1,2})[:.](\d{2})/', $text, $m, PREG_SET_ORDER) >= 2) {
            $times = array_map(fn ($t) => sprintf('%02d:%s', min(23, (int) $t[1]), $t[2]), array_slice($m, 0, 2));
            if ($times[0] < $times[1]) {
                return $times;
            }
        }

        return ['08:00', '14:00'];
    }

    private static function addIfUngrouped(int $doctorId, Group $group, ?int $sessionId): bool
    {
        $grouped = DB::table('doctor_group_members')
            ->where('doctor_id', $doctorId)
            ->where(fn ($q) => $sessionId
                ? $q->where('academic_session_id', $sessionId)->orWhereNull('academic_session_id')
                : $q->whereNull('academic_session_id'))
            ->exists();

        if ($grouped) {
            return false;
        }

        DB::table('doctor_group_members')->insert([
            'group_id' => $group->id,
            'doctor_id' => $doctorId,
            'academic_session_id' => $sessionId,
            'added_at' => now(),
        ]);

        return true;
    }

    /** The system-wide current year — not the browser's selected one, so it also works from the console. */
    private static function currentSessionId(): ?int
    {
        return AcademicSession::where('is_current', true)->where('is_active', true)->value('id')
            ?? AcademicSession::where('is_active', true)->orderByDesc('start_date')->value('id');
    }
}
