<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Department;
use App\Models\DepartmentRoleActivityLog;
use App\Models\DepartmentRoleAssignment;
use App\Models\Stage;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Mirrors App\Http\Controllers\DepartmentRoleAssignmentController for the
 * Flutter client (2026-10-17): assign a senior/HR role in a department,
 * switch it off and on, remove it — with the same activity log rows.
 */
class DepartmentRoleAssignmentController extends Controller
{
    private const WITH = ['user:id,full_name', 'department:id,name', 'stage:id,name'];

    public function index(): JsonResponse
    {
        return response()->json([
            'data' => [
                'assignments' => DepartmentRoleAssignment::with(self::WITH)
                    ->orderByDesc('id')
                    ->get()
                    ->map(fn (DepartmentRoleAssignment $a) => $this->row($a))
                    ->values(),
                'users' => User::where('role', '!=', 'super_admin')->orderBy('full_name')->get(['id', 'full_name']),
                // Each department belongs to one stage; the form lists only
                // the chosen stage's departments, as on the web.
                'departments' => Department::orderBy('name')->get(['id', 'name', 'stage_id']),
                'stages' => Stage::orderBy('name')->get(['id', 'name']),
            ],
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'user_id' => ['required', 'exists:users,id'],
            'stage_id' => ['required', 'exists:stages,id'],
            'department_id' => ['required', Rule::exists('departments', 'id')->where('stage_id', $request->integer('stage_id'))],
            'role_type' => ['required', 'in:senior,hr'],
            'notes' => ['nullable', 'string'],
        ]);

        $assignment = DepartmentRoleAssignment::create([
            ...$validated,
            'assigned_by' => $request->user()->id,
            'assigned_at' => now(),
            'status' => 'active',
        ]);

        DepartmentRoleActivityLog::create([
            'role_assignment_id' => $assignment->id,
            'action' => 'assigned',
            'performed_by' => $request->user()->id,
            'details' => "Assigned {$assignment->role_type} role",
            'ip_address' => $request->ip(),
        ]);

        return response()->json(['data' => $this->row($assignment->load(self::WITH))], 201);
    }

    public function toggle(Request $request, DepartmentRoleAssignment $departmentRoleAssignment): JsonResponse
    {
        $departmentRoleAssignment->status = $departmentRoleAssignment->status === 'active' ? 'inactive' : 'active';
        $departmentRoleAssignment->save();

        DepartmentRoleActivityLog::create([
            'role_assignment_id' => $departmentRoleAssignment->id,
            'action' => $departmentRoleAssignment->status === 'active' ? 'reactivated' : 'deactivated',
            'performed_by' => $request->user()->id,
            'ip_address' => $request->ip(),
        ]);

        return response()->json(['data' => $this->row($departmentRoleAssignment->load(self::WITH))]);
    }

    /** No "removed" log row: it would cascade away with the assignment (see the web controller). */
    public function destroy(DepartmentRoleAssignment $departmentRoleAssignment): JsonResponse
    {
        $departmentRoleAssignment->delete();

        return response()->json(null, 204);
    }

    private function row(DepartmentRoleAssignment $a): array
    {
        return [
            'id' => $a->id,
            'user_id' => $a->user_id,
            'user_name' => $a->user?->full_name,
            'stage_id' => $a->stage_id,
            'stage_name' => $a->stage?->name,
            'department_id' => $a->department_id,
            'department_name' => $a->department?->name,
            'role_type' => $a->role_type,
            'status' => $a->status,
            'notes' => $a->notes,
            'assigned_at' => $a->assigned_at?->toIso8601String(),
        ];
    }
}
