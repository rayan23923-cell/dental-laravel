<?php

namespace App\Http\Middleware;

use App\Models\AcademicSession;
use App\Models\ClinicSetting;
use App\Services\AcademicSessionHelper;
use App\Support\CaseSheetPrint;
use Illuminate\Http\Request;
use Inertia\Middleware;

class HandleInertiaRequests extends Middleware
{
    /**
     * The root template that is loaded on the first page visit.
     *
     * @var string
     */
    protected $rootView = 'app';

    /**
     * Determine the current asset version.
     */
    public function version(Request $request): ?string
    {
        return parent::version($request);
    }

    /**
     * Define the props that are shared by default.
     *
     * @return array<string, mixed>
     */
    public function share(Request $request): array
    {
        return [
            ...parent::share($request),
            'auth' => [
                'user' => $request->user(),
                'doctor' => auth('doctor')->user(),
            ],
            // 'error' added 2026-08-19: AcademicSessionController::destroy()'s
            // delete-guard messages (->with('error', ...)) were silently
            // swallowed — this only ever shared 'success', so the guard's
            // rejection message never reached the page even though the
            // backend was behaving correctly.
            'flash' => [
                'success' => fn () => $request->session()->get('success'),
                'error' => fn () => $request->session()->get('error'),
            ],
            // Which case sheets have a printable version. Taken from the
            // registry itself rather than restated per controller, so the
            // "طباعة" button can never appear on a sheet with no print page
            // — the satellite sheets (follow-ups, images, treatment plans)
            // have none, matching the original.
            // `advanced-periodontal-charts` was excluded here from
            // 2026-08-31 to 2026-09-03: its print renderer only knows
            // `sections()`, and back then `sections()` was patient-info-only
            // (the real content lived in `chart_data.advancedChart`'s
            // 32-tooth grid, invisible to the generic print renderer). Now
            // that `AdvancedPeriodontalChartForm::sections()` has every
            // ordinary field merged in from `PeriodontalChartForm` (by
            // request — "اضافة طباعة الى ادفانسد بريو دنتل"), the same
            // sections-only print renderer produces a genuinely useful page;
            // only the 32-tooth grid itself still doesn't print, which is
            // what the request's own "ماعدا الجدول والمخططات السنية"
            // already excludes. Un-exclude `kCaseSheetPrintableResources` on
            // the Flutter side to match.
            'printableCaseSheets' => array_keys(CaseSheetPrint::SHEETS),
            // Gates the "Sign in with Google" button on both login screens —
            // see App\Http\Controllers\Auth\GoogleAuthController. Hidden
            // outright until GOOGLE_CLIENT_ID/SECRET are set, so an
            // unconfigured install never shows a button that can't work.
            'googleSignInEnabled' => filled(config('services.google.client_id'))
                && filled(config('services.google.client_secret')),
            // Matches the original's ClinicSettings helper being read on
            // every navbar.php render (logo/name shown app-wide) — shared
            // lazily so pages that don't touch the nav don't pay the query.
            'clinicSettings' => fn () => once(function () {
                $settings = ClinicSetting::current();

                return [
                    'name' => $settings->clinic_name,
                    'logo_url' => $settings->logoUrl(),
                    // College/university identity — added for the
                    // Instagram-style login screen (GuestLayout.vue,
                    // 2026-08-30), which shows the same academic branding
                    // Welcome.vue's own `clinic` prop already carries.
                    'college_name' => $settings->college_name,
                    'university_name' => $settings->university_name,
                    'university_logo_url' => $settings->universityLogoUrl(),
                ];
            }),
            // The doctor navbar carries SessionHelper::renderSwitcherWidget()
            // in the original — shared only for the doctor guard so the
            // staff pages don't pay for a list they don't render.
            'academicSessions' => fn () => auth('doctor')->check()
                ? AcademicSession::where('is_active', true)
                    ->orderByDesc('is_current')->orderByDesc('start_date')
                    ->get(['id', 'name', 'is_current'])
                : [],
            'selectedAcademicSessionId' => fn () => auth('doctor')->check()
                ? AcademicSessionHelper::resolveId()
                : null,
        ];
    }
}
