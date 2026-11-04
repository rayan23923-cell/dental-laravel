/**
 * Dates with the month by name (2026-11-04, by request): the browser's own
 * date text came out garbled on some phones ("042026/11/"), so dates are
 * shown as "4 تشرين الثاني 2026", with the Iraqi month names.
 */
export const ARABIC_MONTHS = [
    'كانون الثاني',
    'شباط',
    'آذار',
    'نيسان',
    'أيار',
    'حزيران',
    'تموز',
    'آب',
    'أيلول',
    'تشرين الأول',
    'تشرين الثاني',
    'كانون الأول',
];

const EN_MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** "2026-11-04" (or an ISO datetime) → "4 تشرين الثاني 2026"; '' if not a date. */
export function formatMonthDate(value, locale = 'ar') {
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(value ?? ''));
    if (!m) return '';
    const month = Number(m[2]) - 1;
    if (month < 0 || month > 11) return '';
    const names = locale === 'en' ? EN_MONTHS : ARABIC_MONTHS;
    return `${Number(m[3])} ${names[month]} ${m[1]}`;
}
