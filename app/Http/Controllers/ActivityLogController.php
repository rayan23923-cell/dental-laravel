<?php

namespace App\Http\Controllers;

use App\Models\ActivityLog;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

class ActivityLogController extends Controller
{
    public function index(Request $request): Response
    {
        $logs = ActivityLog::query()
            ->when($request->string('module')->toString(), fn ($q, $module) => $q->where('module', $module))
            ->when($request->string('action')->toString(), fn ($q, $action) => $q->where('action', $action))
            ->when($request->string('search')->toString(), fn ($q, $search) => $q->where(function ($sub) use ($search) {
                $sub->where('username', 'like', "%{$search}%")
                    ->orWhere('description', 'like', "%{$search}%");
            }))
            ->latest('created_at')
            ->paginate(30)
            ->withQueryString();

        return Inertia::render('ActivityLogs/Index', [
            'logs' => $logs,
            'filters' => $request->only('module', 'action', 'search'),
            'modules' => ActivityLog::query()->distinct()->orderBy('module')->pluck('module'),
        ]);
    }
}
