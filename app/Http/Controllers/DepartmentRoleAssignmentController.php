<?php

namespace App\Http\Controllers;

use App\Models\Department;
use App\Models\DepartmentRoleActivityLog;
use App\Models\DepartmentRoleAssignment;
use App\Models\Stage;
use App\Models\User;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Inertia\Inertia;
use Inertia\Response;

class DepartmentRoleAssignmentController extends Controller
{
    public function index(): Response
    {
        $assignments = DepartmentRoleAssignment::with(['user', 'department', 'stage'])
            ->orderByDesc('id')
            ->get();

        return Inertia::render('DepartmentRoles/Index', [
            'assignments' => $assignments,
            'users' => User::where('role', '!=', 'super_admin')->orderBy('full_name')->get(['id', 'full_name']),
            'departments' => Department::orderBy('name')->get(['id', 'name']),
            'stages' => Stage::orderBy('name')->get(['id', 'name']),
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'user_id' => ['required', 'exists:users,id'],
            'department_id' => ['required', 'exists:departments,id'],
            'stage_id' => ['required', 'exists:stages,id'],
            'role_type' => ['required', 'in:senior,hr'],
            'notes' => ['nullable', 'string'],
        ]);

        $assignment = DepartmentRoleAssignment::create([
            ...$validated,
            'assigned_by' => Auth::id(),
            'assigned_at' => now(),
            'status' => 'active',
        ]);

        DepartmentRoleActivityLog::create([
            'role_assignment_id' => $assignment->id,
            'action' => 'assigned',
            'performed_by' => Auth::id(),
            'details' => "Assigned {$assignment->role_type} role",
            'ip_address' => $request->ip(),
        ]);

        return back()->with('success', 'Role assigned.');
    }

    public function toggle(Request $request, DepartmentRoleAssignment $departmentRoleAssignment): RedirectResponse
    {
        $departmentRoleAssignment->status = $departmentRoleAssignment->status === 'active' ? 'inactive' : 'active';
        $departmentRoleAssignment->save();

        DepartmentRoleActivityLog::create([
            'role_assignment_id' => $departmentRoleAssignment->id,
            'action' => $departmentRoleAssignment->status === 'active' ? 'reactivated' : 'deactivated',
            'performed_by' => Auth::id(),
            'ip_address' => $request->ip(),
        ]);

        return back()->with('success', 'Role assignment updated.');
    }

    public function destroy(DepartmentRoleAssignment $departmentRoleAssignment): RedirectResponse
    {
        // Not logging a "removed" activity row here: department_role_activity_log.role_assignment_id
        // has an ON DELETE CASCADE FK back to this table, so any log row
        // written here would be deleted along with the assignment in the
        // same statement — it would never actually persist. Deactivating
        // (toggle(), above) is the auditable path; hard delete is
        // intentionally silent in the log for that reason.
        $departmentRoleAssignment->delete();

        return back()->with('success', 'Role assignment removed.');
    }
}
