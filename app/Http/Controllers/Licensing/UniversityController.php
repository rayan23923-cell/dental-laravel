<?php

namespace App\Http\Controllers\Licensing;

use App\Http\Controllers\Controller;
use App\Models\LicenseUniversity;
use App\Models\OfflineLicense;
use App\Support\OfflineLicensing;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\View\View;

/** Universities on the licensing portal, each with its codes and computers. */
class UniversityController extends Controller
{
    public function index(): View
    {
        $universities = LicenseUniversity::withCount([
            'licenses',
            'licenses as used_count' => fn ($q) => $q->whereNotNull('machine_id'),
            'licenses as active_count' => fn ($q) => $q->whereNotNull('machine_id')->whereNull('revoked_at'),
            'licenses as revoked_count' => fn ($q) => $q->whereNotNull('revoked_at'),
            'licenses as dental_active_count' => fn ($q) => $q->where('product', 'dental')->whereNotNull('machine_id')->whereNull('revoked_at'),
            'licenses as filenest_active_count' => fn ($q) => $q->where('product', 'filenest')->whereNotNull('machine_id')->whereNull('revoked_at'),
        ])->withMax('licenses', 'last_seen_at')->orderBy('name')->get();

        return view('licensing.index', [
            'universities' => $universities,
            'latest' => OfflineLicensing::latestBuild(),
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        $data = $this->validated($request);
        $university = LicenseUniversity::create($data);

        return redirect()->route('licensing.universities.show', $university)->with('success', 'تمت إضافة الجامعة.');
    }

    public function show(Request $request, LicenseUniversity $university): View
    {
        // Each system has its own tab on the university page (2026-11-05).
        $product = $request->query('product');
        $product = array_key_exists((string) $product, OfflineLicense::PRODUCTS) ? $product : null;

        return view('licensing.university', [
            'university' => $university,
            'product' => $product,
            'products' => OfflineLicense::PRODUCTS,
            'counts' => $university->licenses()->selectRaw('product, count(*) as total')->groupBy('product')->pluck('total', 'product'),
            'licenses' => $university->licenses()->when($product, fn ($q) => $q->where('product', $product))
                ->orderByRaw('machine_id is null')->orderByDesc('activated_at')->orderByDesc('id')->get(),
            'latest' => OfflineLicensing::latestBuild(),
        ]);
    }

    public function update(Request $request, LicenseUniversity $university): RedirectResponse
    {
        $university->update($this->validated($request, $university));
        // Codes keep the name as text too: it goes into each signed licence.
        $university->licenses()->update(['university' => $university->name]);

        return back()->with('success', 'تم الحفظ.');
    }

    /** Only a university none of whose codes has been used. */
    public function destroy(LicenseUniversity $university): RedirectResponse
    {
        if ($university->licenses()->whereNotNull('machine_id')->exists()) {
            return back()->with('error', 'لا يمكن حذف جامعة لديها حواسيب مفعّلة. أوقف رموزها بدلاً من ذلك.');
        }
        $university->licenses()->delete();
        $university->delete();

        return redirect()->route('licensing.home')->with('success', 'تم حذف الجامعة.');
    }

    private function validated(Request $request, ?LicenseUniversity $university = null): array
    {
        return $request->validate([
            'name' => ['required', 'string', 'max:255', Rule::unique('license_universities', 'name')->ignore($university)],
            'contact' => ['nullable', 'string', 'max:255'],
            'notes' => ['nullable', 'string', 'max:255'],
            'max_devices' => ['nullable', 'integer', 'min:1', 'max:10000'],
        ], [], ['name' => 'اسم الجامعة', 'max_devices' => 'عدد الأجهزة']);
    }
}
