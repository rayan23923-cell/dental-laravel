import { createI18n } from 'vue-i18n';
import ar from './locales/ar.json';
import en from './locales/en.json';

/**
 * Bilingual UI support (2026-09-04, by request — "اضف اللغة العربية
 * والإنجليزية"). Deliberately scoped: only chrome around the app
 * (navigation, login, profile) goes through this — case-sheet field
 * labels are plain PHP arrays in `App\Support\*Form` classes, entirely
 * outside vue-i18n, and stay exactly as they are regardless of locale,
 * by request ("ماعدا الاسماء الطبية تبقى على وضعها في الكيس شيت").
 *
 * `locale` comes from the `locale` Inertia shared prop (see
 * `HandleInertiaRequests::share()`), itself resolved server-side by
 * `App\Http\Middleware\ResolveLocale` — so the very first client-side
 * render already matches what the server sent, no flash of the wrong
 * language.
 */
export function createI18nInstance(locale) {
    return createI18n({
        legacy: false,
        locale: locale && ['ar', 'en'].includes(locale) ? locale : 'ar',
        fallbackLocale: 'ar',
        messages: { ar, en },
    });
}
