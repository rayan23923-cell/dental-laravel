<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\DoctorResource;
use App\Http\Resources\UserResource;
use App\Models\Doctor;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

/**
 * Token-based authentication for the mobile (Flutter) client, backed by
 * Laravel Sanctum personal access tokens. Separate from the web session
 * auth used by the Inertia app (routes/web.php, auth.php).
 */
class AuthController extends Controller
{
    /**
     * Unified staff-or-doctor login. One `login` field (email or
     * username, auto-detected the same way `App\Http\Requests\Auth\LoginRequest`
     * does for the web) — tries `users` first, then `doctors`, so the
     * Flutter client never has to ask which kind of account this is
     * before submitting. `account_type` in the response tells the client
     * which resource shape `user`/`doctor` is and which one to persist
     * for session restore (see `AccountType` on the Flutter side).
     */
    public function login(Request $request): JsonResponse
    {
        $credentials = $request->validate([
            'login' => ['required', 'string'],
            'password' => ['required', 'string'],
            'device_name' => ['required', 'string'],
        ]);

        $field = filter_var($credentials['login'], FILTER_VALIDATE_EMAIL) ? 'email' : 'username';

        $user = User::where($field, $credentials['login'])->first();

        if ($user && Hash::check($credentials['password'], $user->password)) {
            $token = $user->createToken($credentials['device_name'])->plainTextToken;

            return response()->json([
                'token' => $token,
                'account_type' => 'staff',
                'user' => new UserResource($user),
            ]);
        }

        $doctor = Doctor::where($field, $credentials['login'])->first();

        if ($doctor && Hash::check($credentials['password'], $doctor->password)) {
            $token = $doctor->createToken($credentials['device_name'])->plainTextToken;

            return response()->json([
                'token' => $token,
                'account_type' => 'doctor',
                'doctor' => new DoctorResource($doctor),
            ]);
        }

        throw ValidationException::withMessages([
            'login' => ['The provided credentials are incorrect.'],
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['message' => 'Logged out.']);
    }

    public function me(Request $request): JsonResponse
    {
        $user = $request->user();

        return response()->json(
            $user instanceof Doctor ? new DoctorResource($user) : new UserResource($user)
        );
    }
}
