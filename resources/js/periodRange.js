// Quick date ranges (2026-11-01, by request): today, this week (from
// Saturday, the local week start) and this month, as yyyy-mm-dd.
const ymd = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

export const PERIODS = ['today', 'week', 'month'];

export function periodRange(key, now = new Date()) {
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    if (key === 'week') {
        const start = new Date(today);
        start.setDate(today.getDate() - ((today.getDay() + 1) % 7));
        return { from: ymd(start), to: ymd(today) };
    }
    if (key === 'month') {
        return { from: ymd(new Date(today.getFullYear(), today.getMonth(), 1)), to: ymd(today) };
    }
    return { from: ymd(today), to: ymd(today) };
}

/** Which quick range [from, to] matches, if any. */
export function activePeriod(from, to, now = new Date()) {
    return PERIODS.find((k) => {
        const r = periodRange(k, now);
        return r.from === from && r.to === to;
    }) ?? null;
}
