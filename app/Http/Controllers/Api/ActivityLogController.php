<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\ActivityLogResource;
use App\Models\ActivityLog;
use App\Models\Doctor;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Mirrors App\Http\Controllers\ActivityLogController for the Flutter
 * client. `search` was missing here relative to the web controller (only
 * `module`/`action` were ported) — added to match, since a mobile admin
 * scrolling a possibly-long log benefits from it at least as much as the
 * web page does.
 */
class ActivityLogController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        abort_if($request->user() instanceof Doctor, 403, 'Staff only.');

        $logs = ActivityLog::query()
            ->when($request->string('module')->toString(), fn ($q, $module) => $q->where('module', $module))
            ->when($request->string('action')->toString(), fn ($q, $action) => $q->where('action', $action))
            ->when($request->string('search')->toString(), fn ($q, $search) => $q->where(function ($sub) use ($search) {
                $sub->where('username', 'like', "%{$search}%")
                    ->orWhere('description', 'like', "%{$search}%");
            }))
            ->latest('created_at')
            ->paginate(30);

        return ActivityLogResource::collection($logs)->response();
    }
}
