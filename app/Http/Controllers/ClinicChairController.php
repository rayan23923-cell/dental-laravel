<?php

namespace App\Http\Controllers;

use App\Models\ClinicChair;
use App\Models\EducationType;
use App\Models\Group;
use App\Models\Stage;
use App\Services\AcademicSessionHelper;
use App\Services\ScopeHelper;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Inertia\Inertia;
use Inertia\Response;

/**
 * The clinic seating map (2026-09-03, by request — see the
 * `create_clinic_chairs_table` migration's own doc comment for why a chair
 * belongs to a `Group`, not an individual doctor). No legacy-app
 * counterpart to port from; this module is new.
 */
class ClinicChairController extends Controller
{
    public function index(Request $request): Response
    {
        $user = $request->user();
        $selectedSession = AcademicSessionHelper::resolve();
        $selectedSessionId = $selectedSession?->id;

        $chairs = ClinicChair::with(['group.stage', 'group.doctors:id,name', 'doctor:id,name,profile_image'])
            ->orderBy('row_number')
            ->orderBy('column_number')
            ->get();

        // The sidebar's assignable list — same session scoping
        // `GroupController::index()` already applies, since a chair
        // assignment is only ever meaningful for the group's own session.
        $groupsQuery = Group::with(['stage', 'doctors:id,name'])->orderBy('name');
        if ($selectedSessionId !== null) {
            $groupsQuery->where(function ($q) use ($selectedSessionId) {
                $q->where('academic_session_id', $selectedSessionId)->orWhereNull('academic_session_id');
            });
        }
        $groupsQuery = ScopeHelper::scopeStages($groupsQuery, $user, 'stage_id');
        $groupsQuery = ScopeHelper::scopeAcademicSessions($groupsQuery, $user);

        return Inertia::render('ClinicChairs/Index', [
            'chairs' => $chairs,
            'groups' => $groupsQuery->get(),
            // Lets the sidebar tell "every doctor already seated" apart
            // from "N new doctors to distribute" per group, without a
            // second round-trip when the "Distribute/Update" button is
            // clicked (see assignGroup() below — same doctor-not-yet-
            // seated check, just done client-side first for the button
            // label/disabled state).
            'assignedDoctorIds' => ClinicChair::whereNotNull('doctor_id')->pluck('doctor_id'),
            'educationTypes' => ScopeHelper::scopeEducationTypes(EducationType::query(), $user)->orderBy('name')->get(['id', 'name']),
            'stages' => ScopeHelper::scopeStages(Stage::query(), $user)->orderBy('name')->get(['id', 'name', 'education_type_id']),
            'currentSession' => $selectedSession?->only('id', 'name'),
        ]);
    }

    /**
     * Adds one chair. `row_number` omitted (or naming a row with no chairs
     * left to append after — can't happen from the UI, but handled the
     * same way regardless) starts a brand-new row; given an existing row it
     * appends to that row's end. Either way `column_number` is always "one
     * past whatever's already there", never chosen by the caller — that's
     * what dragging existing chairs is for.
     */
    public function store(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'row_number' => ['nullable', 'integer', 'min:1'],
        ]);

        $rowNumber = $validated['row_number'] ?? ((int) ClinicChair::max('row_number') + 1);
        $columnNumber = (int) ClinicChair::where('row_number', $rowNumber)->max('column_number') + 1;

        ClinicChair::create([
            'row_number' => $rowNumber,
            'column_number' => $columnNumber,
        ]);

        return back()->with('success', 'Chair added.');
    }

    /**
     * Assigns/clears a chair's group and/or doctor (drag a group chip onto
     * a chair for the plain group-level mode; "unassign" clears both
     * together, since a chair can't sensibly keep a doctor without the
     * group they were seated as part of).
     */
    public function update(Request $request, ClinicChair $clinicChair): RedirectResponse
    {
        $validated = $request->validate([
            'group_id' => ['nullable', 'integer', 'exists:groups,id'],
            'doctor_id' => ['nullable', 'integer', 'exists:doctors,id'],
            'label' => ['nullable', 'string', 'max:50'],
        ]);

        // "Unassign" sends group_id: null with no doctor_id key at all —
        // clear both explicitly rather than leaving a stale doctor_id
        // pointing nowhere.
        if ($request->has('group_id') && $validated['group_id'] === null && ! $request->has('doctor_id')) {
            $validated['doctor_id'] = null;
        }

        $clinicChair->update($validated);

        return back()->with('success', 'Chair updated.');
    }

    /**
     * Spreads a group's doctors across chairs, one doctor per chair
     * (2026-09-04, by request — "عند اختيار مجموعة لم يتم اختيارها من
     * قبل وزع الكراسي بصورة عشوائية وكل كرسي لاسم طبيب معين"). Only
     * touches doctors from this group who don't already have a chair
     * anywhere — the very first click seats everyone, a later click
     * (e.g. after a new doctor joined the group) seats only the newcomer,
     * satisfying "امكانية تحديث الكراسي اذا تم اضافة طبيب جديد" with the
     * same action rather than a separate "sync" button. Existing empty
     * chairs (no group, no doctor) are filled first; anything left over
     * gets a brand-new row of chairs. `shuffle()` on the doctor order
     * before filling is the "عشوائية" — which doctor lands in which
     * chair position is random, not which chairs exist.
     */
    public function assignGroup(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'group_id' => ['required', 'integer', 'exists:groups,id'],
        ]);

        $group = Group::with('doctors:id')->findOrFail($validated['group_id']);
        $doctorIds = $group->doctors->pluck('id')->all();

        if ($doctorIds === []) {
            return back()->with('error', 'This group has no doctors yet.');
        }

        $alreadySeated = ClinicChair::whereIn('doctor_id', $doctorIds)->pluck('doctor_id')->all();
        $unseatedDoctorIds = array_values(array_diff($doctorIds, $alreadySeated));

        if ($unseatedDoctorIds === []) {
            return back()->with('success', 'Every doctor in this group already has a chair.');
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

        return back()->with('success', count($unseatedDoctorIds).' doctor(s) assigned to chairs.');
    }

    /**
     * Drag-and-drop reordering — moves `clinicChair` to `(row_number,
     * column_number)`. If another chair already sits there, the two simply
     * swap positions rather than one silently overwriting the other or
     * every later chair in the row needing to shift down.
     */
    public function move(Request $request, ClinicChair $clinicChair): RedirectResponse
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

        return back()->with('success', 'Chair moved.');
    }

    public function destroy(ClinicChair $clinicChair): RedirectResponse
    {
        $clinicChair->delete();

        return back()->with('success', 'Chair removed.');
    }
}
