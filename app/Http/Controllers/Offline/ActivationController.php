<?php

namespace App\Http\Controllers\Offline;

use App\Http\Controllers\Controller;
use App\Support\OfflineLicensing;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\View\View;

/**
 * The offline copy's activation page (2026-10-17, by request): the
 * university's code is sent once to the hosted system, which ties it to this
 * computer and returns a signed licence kept in storage/app.
 */
class ActivationController extends Controller
{
    public function show(): View|RedirectResponse
    {
        abort_unless(OfflineLicensing::required(), 404);
        if (OfflineLicensing::current()) {
            return redirect('/login');
        }

        return view('activate', [
            'machineId' => OfflineLicensing::machineId(),
            'machineName' => OfflineLicensing::machineName(),
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        abort_unless(OfflineLicensing::required(), 404);
        $request->validate(['code' => ['required', 'string', 'max:40']]);

        try {
            $response = Http::timeout(30)->acceptJson()->post(config('offline.server').'/api/v1/offline/activate', [
                'code' => $request->input('code'),
                'machine_id' => OfflineLicensing::machineId(),
                'machine_name' => OfflineLicensing::machineName(),
            ]);
        } catch (\Throwable $e) {
            report($e);

            return back()->withInput()->withErrors(['code' => 'تعذّر الاتصال بالخادم. التفعيل يحتاج اتصال إنترنت مرة واحدة فقط، تأكد من الاتصال وحاول مرة أخرى.']);
        }

        if (! $response->successful()) {
            return back()->withInput()->withErrors(['code' => $response->json('message') ?: 'تعذّر التفعيل، حاول مرة أخرى.']);
        }

        $license = $response->json('license');
        $data = OfflineLicensing::verify(is_array($license) ? $license : null);
        if (! $data || ($data['machine_id'] ?? null) !== OfflineLicensing::machineId()) {
            return back()->withInput()->withErrors(['code' => 'ردّ الخادم غير صالح، حاول مرة أخرى.']);
        }

        OfflineLicensing::save($license);

        return redirect('/login')->with('status', 'تم تفعيل النظام لـ '.$data['university'].'.');
    }
}
