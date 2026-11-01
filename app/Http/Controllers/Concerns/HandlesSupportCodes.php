<?php

namespace App\Http\Controllers\Concerns;

use App\Models\SupportCode;
use App\Support\SupportCodes;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * The parts of the care codes page (2026-11-01) the web and the API share:
 * the filtered list, generating and stopping codes, and checking a typed
 * code at the desk. See App\Support\SupportCodes.
 */
trait HandlesSupportCodes
{
    protected function filteredCodes(Request $request)
    {
        $status = $request->string('status')->toString();
        $search = SupportCodes::normalize($request->string('search')->toString());
        $batch = $request->integer('batch') ?: null;

        return SupportCode::query()
            ->with('registration:id,name,phone')
            ->inStatus(in_array($status, [SupportCode::ACTIVE, SupportCode::USED, SupportCode::DISABLED], true) ? $status : null)
            ->when($search !== '', fn ($q) => $q->where('code', 'like', "%{$search}%"))
            ->when($batch, fn ($q) => $q->where('batch', $batch))
            ->orderByDesc('id');
    }

    protected function validatedGenerate(Request $request): array
    {
        return $request->validate([
            'count' => ['required', 'integer', 'min:1', 'max:'.SupportCodes::MAX_BATCH],
            'note' => ['nullable', 'string', 'max:255'],
        ]);
    }

    /** @return array{ids: array<int>, batch: ?int, disabled: bool} */
    protected function validatedStatus(Request $request): array
    {
        $validated = $request->validate([
            'ids' => ['array'],
            'ids.*' => ['integer'],
            'batch' => ['nullable', 'integer'],
            'disabled' => ['required', 'boolean'],
        ]);

        return [
            'ids' => array_map('intval', $validated['ids'] ?? []),
            'batch' => isset($validated['batch']) ? (int) $validated['batch'] : null,
            'disabled' => (bool) $validated['disabled'],
        ];
    }

    /** {valid: true} or a 422 with why the typed code cannot be used. */
    protected function checkTyped(Request $request): array
    {
        $request->validate(['code' => ['required', 'string', 'max:20']]);
        $code = SupportCodes::lookup($request->string('code')->toString(), $request->user());

        return ['valid' => true, 'code' => $code->code, 'message' => 'الرمز صالح — الخدمة والمختبر بدون أجور.'];
    }
}
