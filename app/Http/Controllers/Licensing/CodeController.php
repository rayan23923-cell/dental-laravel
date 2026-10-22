<?php

namespace App\Http\Controllers\Licensing;

use App\Http\Controllers\Controller;
use App\Models\LicenseUniversity;
use App\Models\OfflineLicense;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;

/** A university's activation codes on the licensing portal. */
class CodeController extends Controller
{
    public function store(Request $request, LicenseUniversity $university): RedirectResponse
    {
        $data = $request->validate([
            'count' => ['required', 'integer', 'min:1', 'max:50'],
            'notes' => ['nullable', 'string', 'max:255'],
        ]);

        for ($i = 0; $i < $data['count']; $i++) {
            OfflineLicense::create([
                'code' => OfflineLicense::newCode(),
                'university' => $university->name,
                'university_id' => $university->id,
                'notes' => $data['notes'] ?? null,
            ]);
        }

        return back()->with('success', $data['count'] > 1 ? 'تم إنشاء '.$data['count'].' رموز.' : 'تم إنشاء الرمز.');
    }

    /** Free the code for another computer, or stop / restart it. */
    public function update(Request $request, OfflineLicense $license): RedirectResponse
    {
        $action = $request->validate(['action' => ['required', 'in:release,revoke,restore']])['action'];

        // Restarting a stopped code brings its computer back: only within the limit.
        $university = $license->universityRecord;
        if ($action === 'restore' && $license->machine_id && $university && ! $university->hasRoomFor($license->machine_id)) {
            return back()->with('error', 'وصلت الجامعة إلى الحد الأقصى لعدد الأجهزة ('.$university->max_devices.'). حرّر أو أوقف حاسوباً آخر، أو ارفع الحد.');
        }

        $license->forceFill(match ($action) {
            'release' => ['machine_id' => null, 'machine_name' => null, 'activated_at' => null, 'installed_build' => null, 'last_ip' => null],
            'revoke' => ['revoked_at' => now()],
            'restore' => ['revoked_at' => null],
        })->save();

        return back()->with('success', match ($action) {
            'release' => 'تم تحرير الرمز، يمكن استخدامه على حاسوب آخر.',
            'revoke' => 'تم إيقاف الرمز.',
            'restore' => 'تمت إعادة تشغيل الرمز.',
        });
    }

    /** Only a code no computer has used. */
    public function destroy(OfflineLicense $license): RedirectResponse
    {
        if ($license->machine_id) {
            return back()->with('error', 'هذا الرمز مستخدم على حاسوب. أوقفه أو حرّره أولاً.');
        }
        $license->delete();

        return back()->with('success', 'تم حذف الرمز.');
    }
}
