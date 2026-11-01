<?php

namespace App\Http\Controllers;

use App\Http\Controllers\Concerns\HandlesSupportCodes;
use App\Models\ClinicSetting;
use App\Models\SupportCode;
use App\Services\PermissionManager;
use App\Support\SupportCodes;
use Illuminate\Contracts\View\View;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * "بطاقات الرعاية" page (2026-11-01, by request): generate one-time 5-digit
 * codes, print them as cards to cut out, and stop unused ones. See
 * App\Support\SupportCodes.
 */
class SupportCodeController extends Controller
{
    use HandlesSupportCodes;

    public function index(Request $request): Response
    {
        $perm = new PermissionManager($request->user());

        return Inertia::render('SupportCodes/Index', [
            'codes' => $this->filteredCodes($request)->paginate(50)->withQueryString()
                ->through(fn (SupportCode $c) => SupportCodes::present($c)),
            'counts' => SupportCodes::counts(),
            'batches' => SupportCodes::batches(),
            'filters' => [
                'status' => $request->string('status')->toString() ?: null,
                'search' => $request->string('search')->toString(),
                'batch' => $request->integer('batch') ?: null,
            ],
            'enabled' => SupportCodes::enabled(),
            'maxBatch' => SupportCodes::MAX_BATCH,
            'can' => [
                'generate' => $perm->can('support_codes', 'generate'),
                'disable' => $perm->can('support_codes', 'disable'),
                'settings' => $perm->can('register_settings', 'edit'),
            ],
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        $validated = $this->validatedGenerate($request);
        $codes = SupportCodes::generate((int) $validated['count'], $validated['note'] ?? null, $request->user());

        return redirect()->route('support-codes.index', ['batch' => $codes->first()?->batch])
            ->with('success', 'تم توليد '.$codes->count().' رمز رعاية — يمكنك طباعتها الآن.');
    }

    public function status(Request $request): RedirectResponse
    {
        $v = $this->validatedStatus($request);
        $count = SupportCodes::setDisabled($v['ids'], $v['batch'], $v['disabled'], $request->user());

        return back()->with('success', $v['disabled'] ? "تم إيقاف {$count} رمز." : "تم تفعيل {$count} رمز.");
    }

    public function check(Request $request): JsonResponse
    {
        return response()->json($this->checkTyped($request));
    }

    /**
     * The cards to print and cut (2026-11-01): ten to an A4 page with cut
     * lines. Only active codes print; picked by ids, a batch, or all active.
     */
    public function cards(Request $request): View
    {
        $ids = array_filter(array_map('intval', explode(',', $request->string('ids')->toString())));
        $batch = $request->integer('batch') ?: null;

        $codes = SupportCode::query()
            ->inStatus(SupportCode::ACTIVE)
            ->when($ids !== [], fn ($q) => $q->whereIn('id', $ids))
            ->when($ids === [] && $batch, fn ($q) => $q->where('batch', $batch))
            ->orderBy('id')
            ->limit(SupportCodes::MAX_BATCH)
            ->get();

        $settings = ClinicSetting::current();

        return view('print.support-cards', [
            'codes' => $codes,
            'settings' => $settings,
            'title' => $settings->clinic_name ?: config('app.name'),
            'autoprint' => $request->boolean('autoprint'),
        ]);
    }
}
