/**
 * Grades on case sheets are numbers only (2026-10-15, by request): Arabic
 * digits become Western ones, an old "9/10" keeps its 9, and anything that
 * isn't a digit or one decimal point is dropped. TaskScoring reads these
 * as numbers, so "9/10" used to count as 0 points.
 */
export function toGrade(value) {
    if (value === null || value === undefined) return '';
    let s = String(value)
        .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660))
        .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0))
        .replace(/[٫,]/g, '.')
        .trim();
    if (s.includes('/')) s = s.split('/')[0];
    s = s.replace(/[^0-9.]/g, '');
    const dot = s.indexOf('.');
    return dot === -1 ? s : s.slice(0, dot + 1) + s.slice(dot + 1).replace(/\./g, '');
}
