<?php

namespace App\Http\Controllers;

use App\Models\Department;
use App\Models\EducationType;
use App\Models\Stage;
use App\Services\ScopeHelper;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

class DepartmentController extends Controller
{
    public function index(Request $request): Response
    {
        $user = $request->user();

        // Matches admin/ajax/departments_crud.php's getDepartmentScopeFilter():
        // department id, education type, and stage restrictions all apply
        // together (AND) when the user has rows for that dimension.
        $query = Department::with(['stage', 'educationType']);
        $query = ScopeHelper::scopeDepartments($query, $user, 'id');
        $query = ScopeHelper::scopeEducationTypes($query, $user, 'education_type_id');
        $query = ScopeHelper::scopeStages($query, $user, 'stage_id');

        $query
            ->when($request->string('search')->toString(), fn ($q, $search) => $q->where('name', 'like', "%{$search}%"))
            ->when($request->integer('stage_id'), fn ($q, $id) => $q->where('stage_id', $id))
            ->when($request->integer('education_type_id'), fn ($q, $id) => $q->where('education_type_id', $id));

        return Inertia::render('Departments/Index', [
            'departments' => $query->orderBy('name')->get(),
            'stages' => ScopeHelper::scopeStages(Stage::query(), $user)->orderBy('name')->get(),
            'educationTypes' => ScopeHelper::scopeEducationTypes(EducationType::query(), $user)->orderBy('name')->get(),
            'filters' => $request->only('search', 'stage_id', 'education_type_id'),
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'stage_id' => ['nullable', 'exists:stages,id'],
            'education_type_id' => ['nullable', 'exists:education_types,id'],
        ]);

        Department::create($validated);

        return back()->with('success', 'Department added.');
    }

    public function update(Request $request, Department $department): RedirectResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'stage_id' => ['nullable', 'exists:stages,id'],
            'education_type_id' => ['nullable', 'exists:education_types,id'],
        ]);

        $department->update($validated);

        return back()->with('success', 'Department updated.');
    }

    public function destroy(Department $department): RedirectResponse
    {
        $department->delete();

        return back()->with('success', 'Department deleted.');
    }
}
