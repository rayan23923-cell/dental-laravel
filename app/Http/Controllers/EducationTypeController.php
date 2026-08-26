<?php

namespace App\Http\Controllers;

use App\Models\EducationType;
use App\Services\ScopeHelper;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Inertia\Inertia;
use Inertia\Response;

class EducationTypeController extends Controller
{
    public function index(Request $request): Response
    {
        $query = ScopeHelper::scopeEducationTypes(EducationType::withCount('stages'), $request->user())
            ->when($request->string('search')->toString(), fn ($q, $search) => $q->where('name', 'like', "%{$search}%"));

        return Inertia::render('EducationTypes/Index', [
            'educationTypes' => $query->orderBy('name')->get(),
            'filters' => $request->only('search'),
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100', Rule::unique('education_types', 'name')],
        ]);

        EducationType::create($validated);

        return back()->with('success', 'Education type added.');
    }

    public function update(Request $request, EducationType $educationType): RedirectResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:100', Rule::unique('education_types', 'name')->ignore($educationType->id)],
        ]);

        $educationType->update($validated);

        return back()->with('success', 'Education type updated.');
    }

    public function destroy(EducationType $educationType): RedirectResponse
    {
        $educationType->delete();

        return back()->with('success', 'Education type deleted.');
    }
}
