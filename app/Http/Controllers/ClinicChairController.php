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

        $chairs = ClinicChair::with(['group.stage', 'group.doctors:id,name'])
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

    /** Assigns/clears a chair's group (drag a group chip onto a chair). */
    public function update(Request $request, ClinicChair $clinicChair): RedirectResponse
    {
        $validated = $request->validate([
            'group_id' => ['nullable', 'integer', 'exists:groups,id'],
            'label' => ['nullable', 'string', 'max:50'],
        ]);

        $clinicChair->update($validated);

        return back()->with('success', 'Chair updated.');
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
