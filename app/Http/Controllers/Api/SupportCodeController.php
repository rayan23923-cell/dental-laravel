<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Concerns\HandlesSupportCodes;
use App\Http\Controllers\Controller;
use App\Models\SupportCode;
use App\Support\SupportCodes;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** Care codes for the app (2026-11-01), the web SupportCodeController's twin. */
class SupportCodeController extends Controller
{
    use HandlesSupportCodes;

    public function index(Request $request): JsonResponse
    {
        $page = $this->filteredCodes($request)->paginate(min(500, max(10, $request->integer('per_page', 50))));

        return response()->json([
            'data' => collect($page->items())->map(fn (SupportCode $c) => SupportCodes::present($c))->values(),
            'meta' => ['current_page' => $page->currentPage(), 'last_page' => $page->lastPage(), 'total' => $page->total()],
            'counts' => SupportCodes::counts(),
            'batches' => SupportCodes::batches(),
            'enabled' => SupportCodes::enabled(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $this->validatedGenerate($request);
        $codes = SupportCodes::generate((int) $validated['count'], $validated['note'] ?? null, $request->user());

        return response()->json([
            'data' => $codes->map(fn (SupportCode $c) => SupportCodes::present($c))->values(),
            'batch' => $codes->first()?->batch,
            'message' => 'تم توليد '.$codes->count().' رمز رعاية.',
        ], 201);
    }

    public function status(Request $request): JsonResponse
    {
        $v = $this->validatedStatus($request);
        $count = SupportCodes::setDisabled($v['ids'], $v['batch'], $v['disabled'], $request->user());

        return response()->json([
            'count' => $count,
            'message' => $v['disabled'] ? "تم إيقاف {$count} رمز." : "تم تفعيل {$count} رمز.",
        ]);
    }

    public function check(Request $request): JsonResponse
    {
        return response()->json($this->checkTyped($request));
    }
}
