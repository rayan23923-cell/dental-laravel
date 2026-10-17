<?php

namespace App\Http\Controllers\Licensing;

use App\Http\Controllers\Controller;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;

/** Sign-in to the licensing portal, with its own accounts (the `license` guard). */
class AuthController extends Controller
{
    public function show(): View|RedirectResponse
    {
        if (Auth::guard('license')->check()) {
            return redirect()->route('licensing.home');
        }

        return view('licensing.login');
    }

    public function store(Request $request): RedirectResponse
    {
        $credentials = $request->validate([
            'username' => ['required', 'string', 'max:100'],
            'password' => ['required', 'string', 'max:200'],
        ]);

        if (! Auth::guard('license')->attempt($credentials, $request->boolean('remember'))) {
            return back()->withInput($request->only('username'))->withErrors(['username' => 'اسم المستخدم أو كلمة المرور غير صحيحة.']);
        }

        $request->session()->regenerate();
        Auth::guard('license')->user()->forceFill(['last_login_at' => now()])->save();

        return redirect()->intended(route('licensing.home'));
    }

    public function destroy(Request $request): RedirectResponse
    {
        Auth::guard('license')->logout();
        $request->session()->regenerateToken();

        return redirect()->route('licensing.login');
    }
}
