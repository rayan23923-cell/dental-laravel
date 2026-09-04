<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ClinicChair;
use App\Models\Group;
use App\Models\Stage;
use App\Services\AcademicSessionHelper;
use App\Services\ScopeHelper;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

/**
 * Mirrors App\Http\Controllers\ClinicChairController for the Flutter
 * client (2026-09-04, by request — "اضفها الى فلتر") — plain
 * (non-Resource-wrapped) JSON, matching Api\GroupController's own
 * convention rather than this API's REST-envelope one, since this is a
 * small staff-admin resource, not a doctor clinical-workflow one.
 */
class ClinicChairController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $selectedSession = AcademicSessionHelper::resolve();
        $selectedSessionId = $selectedSession?->id;

        $chairs = ClinicChair::with(['group.stage', 'group.doctors:id,name', 'doctor:id,name,profile_image'])
            ->orderBy('row_number')
            ->orderBy('column_number')
            ->get()
            ->each(fn ($chair) => $this->withPhotoUrl($chair));

        $groupsQuery = Group::with(['stage', 'doctors:id,name'])->orderBy('name');
        if ($selectedSessionId !== null) {
            $groupsQuery->where(function ($q) use ($selectedSessionId) {
                $q->where('academic_session_id', $selectedSessionId)->orWhereNull('academic_session_id');
            });
        }
        $groupsQuery = ScopeHelper::scopeStages($groupsQuery, $user, 'stage_id');
        $groupsQuery = ScopeHelper::scopeAcademicSessions($groupsQuery, $user);

        return response()->json([
            'chairs' => $chairs,
            'groups' => $groupsQuery->get(),
            'stages' => ScopeHelper::scopeStages(Stage::query(), $user)->orderBy('name')->get(['id', 'name', 'education_type_id']),
            'assigned_doctor_ids' => ClinicChair::whereNotNull('doctor_id')->pluck('doctor_id'),
            'current_session' => $selectedSession?->only('id', 'name'),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'row_number' => ['nullable', 'integer', 'min:1'],
        ]);

        $rowNumber = $validated['row_number'] ?? ((int) ClinicChair::max('row_number') + 1);
        $columnNumber = (int) ClinicChair::where('row_number', $rowNumber)->max('column_number') + 1;

        $chair = ClinicChair::create([
            'row_number' => $rowNumber,
            'column_number' => $columnNumber,
        ]);

        return response()->json($chair, 201);
    }

    public function update(Request $request, ClinicChair $clinicChair): JsonResponse
    {
        $validated = $request->validate([
            'group_id' => ['nullable', 'integer', 'exists:groups,id'],
            'doctor_id' => ['nullable', 'integer', 'exists:doctors,id'],
            'label' => ['nullable', 'string', 'max:50'],
        ]);

        if ($request->has('group_id') && $validated['group_id'] === null && ! $request->has('doctor_id')) {
            $validated['doctor_id'] = null;
        }

        $clinicChair->update($validated);
        $clinicChair->load(['group.stage', 'group.doctors:id,name', 'doctor:id,name,profile_image']);

        return response()->json($this->withPhotoUrl($clinicChair));
    }

    /**
     * `doctor.profile_image` is a raw storage-disk path, meaningless to a
     * client with no knowledge of this server's storage layout — the
     * Flutter domain model (`doctor_admin.dart`, mirrored by
     * `Api\DoctorController`'s own `DoctorResource`) already expects a
     * full `profile_image_url` instead, same `Storage::disk('public')->url()`
     * conversion `DoctorResource`/`UserResource` both do.
     */
    private function withPhotoUrl(ClinicChair $chair): ClinicChair
    {
        if ($chair->doctor) {
            $chair->doctor->setAttribute(
                'profile_image_url',
                $chair->doctor->profile_image ? Storage::disk('public')->url($chair->doctor->profile_image) : null,
            );
        }

        return $chair;
    }

    public function move(Request $request, ClinicChair $clinicChair): JsonResponse
    {
        $validated = $request->validate([
            'row_number' => ['required', 'integer', 'min:1'],
            'column_number' => ['required', 'integer', 'min:1'],
        ]);

        DB::transaction(function () use ($validated, $clinicChair) {
            $occupant = ClinicChair::where('row_number', $validated['row_number'])
                ->where('column_number', $validated['column_number'])
                ->where('id', '!=', $clinicChair->id)
                ->first();

            if ($occupant) {
                $occupant->update(['row_number' => $clinicChair->row_number, 'column_number' => $clinicChair->column_number]);
            }

            $clinicChair->update($validated);
        });

        return response()->json(['status' => 'ok']);
    }

    public function destroy(ClinicChair $clinicChair): JsonResponse
    {
        $clinicChair->delete();

        return response()->json(null, 204);
    }

    /** Same logic as the web controller's own assignGroup() — see its doc comment. */
    public function assignGroup(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'group_id' => ['required', 'integer', 'exists:groups,id'],
        ]);

        $group = Group::with('doctors:id')->findOrFail($validated['group_id']);
        $doctorIds = $group->doctors->pluck('id')->all();

        if ($doctorIds === []) {
            return response()->json(['message' => 'This group has no doctors yet.'], 422);
        }

        $alreadySeated = ClinicChair::whereIn('doctor_id', $doctorIds)->pluck('doctor_id')->all();
        $unseatedDoctorIds = array_values(array_diff($doctorIds, $alreadySeated));

        if ($unseatedDoctorIds === []) {
            return response()->json(['message' => 'Every doctor in this group already has a chair.', 'assigned_count' => 0]);
        }

        shuffle($unseatedDoctorIds);

        DB::transaction(function () use ($unseatedDoctorIds, $validated) {
            $emptyChairs = ClinicChair::whereNull('group_id')->whereNull('doctor_id')
                ->orderBy('row_number')->orderBy('column_number')->get();

            $toReuse = array_slice($unseatedDoctorIds, 0, $emptyChairs->count());
            $toCreate = array_slice($unseatedDoctorIds, $emptyChairs->count());

            foreach ($toReuse as $index => $doctorId) {
                $emptyChairs[$index]->update(['group_id' => $validated['group_id'], 'doctor_id' => $doctorId]);
            }

            if ($toCreate !== []) {
                $rowNumber = (int) ClinicChair::max('row_number') + 1;
                $column = 1;
                foreach ($toCreate as $doctorId) {
                    ClinicChair::create([
                        'row_number' => $rowNumber,
                        'column_number' => $column++,
                        'group_id' => $validated['group_id'],
                        'doctor_id' => $doctorId,
                    ]);
                }
            }
        });

        return response()->json([
            'message' => count($unseatedDoctorIds).' doctor(s) assigned to chairs.',
            'assigned_count' => count($unseatedDoctorIds),
        ]);
    }
}
