<?php

namespace App\Http\Controllers;

use App\Models\CaseSheetType;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Ports admin/case_sheet_manager.php + admin/ajax/case_sheet_types_crud.php.
 * The original also implements an 'update_order' bulk-reorder action, but
 * its own front-end has no drag-handle UI wired to it (confirmed via
 * research — reorder exists at the API layer only, unreachable in the live
 * page) — not ported here either, same "build what's actually reachable,
 * not every latent capability" approach used elsewhere in this rebuild.
 * display_order is simply max+1 on create, matching the original.
 */
class CaseSheetTypeController extends Controller
{
    public function index(): Response
    {
        return Inertia::render('CaseSheetTypes/Index', [
            'caseSheetTypes' => CaseSheetType::withCount('tasks')->orderBy('display_order')->orderBy('name_ar')->get(),
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'type_code' => ['required', 'string', 'max:50', 'regex:/^[a-z0-9_]+$/', Rule::unique('case_sheet_types', 'type_code')],
            'name_ar' => ['required', 'string', 'max:100'],
            'name_en' => ['required', 'string', 'max:100'],
            'icon' => ['nullable', 'string', 'max:50'],
            'color' => ['nullable', 'string', 'max:20'],
            'description' => ['nullable', 'string'],
            'is_active' => ['boolean'],
        ], [
            'type_code.regex' => 'Type code must be lowercase English letters, numbers, and underscores only.',
        ]);

        $validated['icon'] ??= 'file-medical';
        $validated['color'] ??= 'secondary';
        $validated['is_active'] ??= true;
        $validated['display_order'] = (CaseSheetType::max('display_order') ?? 0) + 1;

        CaseSheetType::create($validated);

        return back()->with('success', 'Case sheet type added.');
    }

    public function update(Request $request, CaseSheetType $caseSheetType): RedirectResponse
    {
        // type_code is immutable after creation, matching the original
        // (the update ajax action never accepts it).
        $validated = $request->validate([
            'name_ar' => ['required', 'string', 'max:100'],
            'name_en' => ['required', 'string', 'max:100'],
            'icon' => ['nullable', 'string', 'max:50'],
            'color' => ['nullable', 'string', 'max:20'],
            'description' => ['nullable', 'string'],
            'is_active' => ['boolean'],
        ]);

        $validated['icon'] ??= 'file-medical';
        $validated['color'] ??= 'secondary';
        $validated['is_active'] ??= true;

        $caseSheetType->update($validated);

        return back()->with('success', 'Case sheet type updated.');
    }

    public function destroy(CaseSheetType $caseSheetType): RedirectResponse
    {
        $taskCount = $caseSheetType->tasks()->count();
        if ($taskCount > 0) {
            return back()->with('error', "Can't delete this type — it's used by {$taskCount} task(s).");
        }

        $caseSheetType->delete();

        return back()->with('success', 'Case sheet type deleted.');
    }
}
