<?php

namespace App\Http\Controllers;

use App\Models\EducationType;
use App\Models\Stage;
use App\Services\ScopeHelper;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

class StageController extends Controller
{
    public function index(Request $request): Response
    {
        $user = $request->user();
        $query = Stage::with('educationType')->withCount('departments');

        // Matches admin/ajax/get_stages_list.php: a direct stage-scope
        // restriction takes priority; if the user has none, fall back to
        // scoping by their allowed education types instead.
        $stageIds = ScopeHelper::allowedStageIds($user);
        $eduTypeIds = ScopeHelper::allowedEducationTypeIds($user);

        if ($stageIds !== null) {
            $query->whereIn('id', $stageIds);
        } elseif ($eduTypeIds !== null) {
            $query->whereIn('education_type_id', $eduTypeIds);
        }

        $query
            ->when($request->string('search')->toString(), fn ($q, $search) => $q->where('name', 'like', "%{$search}%"))
            ->when($request->integer('education_type_id'), fn ($q, $id) => $q->where('education_type_id', $id));

        return Inertia::render('Stages/Index', [
            'stages' => $query->orderBy('name')->get(),
            'educationTypes' => ScopeHelper::scopeEducationTypes(EducationType::query(), $user)->orderBy('name')->get(),
            'filters' => $request->only('search', 'education_type_id'),
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            // Required (2026-10-13, by request): every field must be filled.
            'education_type_id' => ['required', 'exists:education_types,id'],
        ]);

        Stage::create($validated);

        return back()->with('success', 'Stage added.');
    }

    public function update(Request $request, Stage $stage): RedirectResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            // Required (2026-10-13, by request): every field must be filled.
            'education_type_id' => ['required', 'exists:education_types,id'],
        ]);

        $stage->update($validated);

        return back()->with('success', 'Stage updated.');
    }

    public function destroy(Stage $stage): RedirectResponse
    {
        $stage->delete();

        return back()->with('success', 'Stage deleted.');
    }
}
