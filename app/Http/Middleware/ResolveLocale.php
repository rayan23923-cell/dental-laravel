<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\App;
use Symfony\Component\HttpFoundation\Response;

/**
 * Resolves the active locale for the request (2026-09-04, by request —
 * "اضف اللغة العربية والإنجليزية ... ليتم اختيارها حسب لغة النظام او حسب
 * اختيار المستخدم"). Order of precedence:
 *   1. The authenticated principal's own `locale` column (either guard —
 *      `web` for staff `User`, `doctor` for `Doctor`), when set.
 *   2. The browser's `Accept-Language` header ("حسب لغة النظام") — only
 *      `ar`/`en` are supported today, so anything else falls through.
 *   3. `ar` — the app's existing all-Arabic default, unchanged for anyone
 *      who never touches the new language setting.
 *
 * Registered in `bootstrap/app.php`'s `web` middleware stack, *before*
 * `HandleInertiaRequests`, since that shares `app()->getLocale()` with the
 * frontend and needs the final resolved value.
 *
 * Deliberately does not touch case-sheet content — `App\Support\*Form`
 * classes are plain PHP arrays with their own hardcoded labels, entirely
 * separate from `app()->getLocale()`/Laravel's translator, so nothing
 * here can affect them either way.
 */
class ResolveLocale
{
    private const SUPPORTED = ['ar', 'en'];

    public function handle(Request $request, Closure $next): Response
    {
        App::setLocale($this->resolve($request));

        return $next($request);
    }

    private function resolve(Request $request): string
    {
        $principal = $request->user('web') ?? $request->user('doctor');

        if ($principal && in_array($principal->locale, self::SUPPORTED, true)) {
            return $principal->locale;
        }

        $preferred = $request->getPreferredLanguage(self::SUPPORTED);

        return $preferred ?? 'ar';
    }
}
