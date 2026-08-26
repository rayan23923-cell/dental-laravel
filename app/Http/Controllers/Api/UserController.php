<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\UserResource;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;

/**
 * Creating a new staff/admin account — genuinely new, not a port. The web
 * app never had this either: the only place `User::create()` happened was
 * Laravel Breeze's public, logged-out self-registration screen (hardcodes
 * `role: 'editor'`, no role choice). `Api\UserPermissionController`
 * (permissions_admin's backend) only edits permissions of users that
 * already exist.
 *
 * `role` can never be `super_admin` here — `UserPermissionController::index()`
 * already excludes `super_admin` accounts from the manageable list
 * (`User::where('role', '!=', 'super_admin')`), so this mirrors that same
 * "super_admin accounts aren't touched through this admin surface" rule at
 * creation time too, rather than letting a plain `admin` mint a new
 * `super_admin` and immediately break that assumption.
 */
class UserController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'full_name' => ['required', 'string', 'max:255'],
            'username' => ['required', 'string', 'max:100', Rule::unique('users', 'username')],
            'email' => ['required', 'email', 'max:255', Rule::unique('users', 'email')],
            'phone' => ['nullable', 'string', 'max:50'],
            'password' => ['required', 'string', 'min:6'],
            'role' => ['required', Rule::in(array_diff(User::ROLES, ['super_admin']))],
        ]);
        $validated['password'] = Hash::make($validated['password']);
        $validated['status'] = 'active';

        $user = User::create($validated);

        return (new UserResource($user))->response()->setStatusCode(201);
    }
}
