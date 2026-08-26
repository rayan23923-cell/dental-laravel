<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

/**
 * Doctor logout only — login itself is unified into `/login` now (see
 * `routes/auth.php`'s single route, `LoginRequest::authenticate()` trying
 * the `web` guard then the `doctor` guard). A doctor session still needs
 * its own logout though: `AuthenticatedSessionController::destroy()` only
 * logs out the `web` guard, and this route sits behind `auth:doctor`
 * middleware rather than the staff-only session state that controller
 * assumes.
 */
class DoctorAuthenticatedSessionController extends Controller
{
    public function destroy(Request $request): RedirectResponse
    {
        Auth::guard('doctor')->logout();

        $request->session()->invalidate();

        $request->session()->regenerateToken();

        return redirect('/');
    }
}
