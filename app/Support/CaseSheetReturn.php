<?php

namespace App\Support;

use Illuminate\Http\RedirectResponse;
use Illuminate\Support\Facades\Auth;

/**
 * Where a case sheet goes back to after "رجوع" or a save (2026-10-13, by
 * request: "عند العودة او حفظ النموذج السريري للطبيب لايعود الى السجل
 * السريري"). Sheets are opened from a task (the doctor's required tasks,
 * pending QR codes, staff task progress) through CaseSheetController, which
 * remembers that page here; saving or going back returns to it instead of
 * the per-type record list, which is no longer in any menu.
 */
class CaseSheetReturn
{
    private const KEY = 'case_sheet_return';

    /** Called when a sheet is opened from a task: remember the page it came from. */
    public static function remember(): void
    {
        $previous = url()->previous();
        $host = parse_url($previous, PHP_URL_HOST);

        // Same-site pages only, and never a sheet itself (a reload).
        if ($previous && $host === request()->getHost() && ! str_contains($previous, '/case-sheet')) {
            session()->put(self::KEY, $previous);
        }
    }

    public static function url(): string
    {
        $remembered = session(self::KEY);
        if (is_string($remembered) && $remembered !== '') {
            return $remembered;
        }

        return Auth::guard('doctor')->check()
            ? route('doctor.required-tasks')
            : route('dashboard');
    }

    public static function redirect(): RedirectResponse
    {
        return redirect()->to(self::url());
    }
}
