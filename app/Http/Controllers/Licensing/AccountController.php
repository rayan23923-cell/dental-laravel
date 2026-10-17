<?php

namespace App\Http\Controllers\Licensing;

use App\Http\Controllers\Controller;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rules\Password;
use Illuminate\View\View;

/** The signed-in portal account: name and password. */
class AccountController extends Controller
{
    public function edit(Request $request): View
    {
        return view('licensing.account', ['admin' => $request->user('license')]);
    }

    public function update(Request $request): RedirectResponse
    {
        $admin = $request->user('license');
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'current_password' => ['required', 'current_password:license'],
            'password' => ['nullable', 'confirmed', Password::min(10)],
        ], [], [
            'name' => 'الاسم',
            'current_password' => 'كلمة المرور الحالية',
            'password' => 'كلمة المرور الجديدة',
        ]);

        $admin->name = $data['name'];
        if (! empty($data['password'])) {
            $admin->password = $data['password'];
        }
        $admin->save();

        return back()->with('success', 'تم الحفظ.');
    }
}
