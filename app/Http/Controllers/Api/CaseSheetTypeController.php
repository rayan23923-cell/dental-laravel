<?php

namespace App\Http\Controllers\Api;

use App\Support\LinkedRecords;
use App\Http\Controllers\Controller;
use App\Models\CaseSheetType;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Mirrors App\Http\Controllers\CaseSheetTypeController for the Flutter
 * client. See that controller's docblock for what was and wasn't ported.
 */
class CaseSheetTypeController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json(
            CaseSheetType::withCount('tasks')->orderBy('display_order')->orderBy('name_ar')->get()
        );
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'type_code' => ['required', 'string', 'max:50', 'regex:/^[a-z0-9_]+$/', Rule::unique('case_sheet_types', 'type_code')],
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
        $validated['display_order'] = (CaseSheetType::max('display_order') ?? 0) + 1;

        $type = CaseSheetType::create($validated);

        return response()->json($type, 201);
    }

    public function update(Request $request, CaseSheetType $caseSheetType): JsonResponse
    {
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

        return response()->json($caseSheetType);
    }

    public function destroy(CaseSheetType $caseSheetType): JsonResponse
    {
        if ($linked = LinkedRecords::message($caseSheetType)) {
            return response()->json(['message' => $linked, 'linked' => LinkedRecords::for($caseSheetType)], 422);
        }

        $caseSheetType->delete();

        return response()->json(null, 204);
    }
}
