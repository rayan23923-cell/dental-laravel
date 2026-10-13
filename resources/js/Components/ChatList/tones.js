/**
 * Colour sets for the chat-list screens (2026-10-13, by request: the
 * reference-data pages styled like the permissions page, "انستقرام او
 * تليجرام"). `avatar` is the gradient behind a row's icon or initial,
 * `chip` a small coloured label under its name.
 */
export const TONES = {
    indigo: { avatar: 'from-indigo-500 to-purple-500', chip: 'bg-indigo-50 text-indigo-700' },
    sky: { avatar: 'from-sky-500 to-cyan-500', chip: 'bg-sky-50 text-sky-700' },
    emerald: { avatar: 'from-emerald-500 to-teal-500', chip: 'bg-emerald-50 text-emerald-700' },
    amber: { avatar: 'from-amber-500 to-orange-500', chip: 'bg-amber-50 text-amber-700' },
    fuchsia: { avatar: 'from-fuchsia-500 to-pink-500', chip: 'bg-fuchsia-50 text-fuchsia-700' },
    rose: { avatar: 'from-rose-500 to-red-500', chip: 'bg-rose-50 text-rose-700' },
    teal: { avatar: 'from-teal-500 to-green-500', chip: 'bg-teal-50 text-teal-700' },
    violet: { avatar: 'from-violet-500 to-indigo-500', chip: 'bg-violet-50 text-violet-700' },
    gray: { avatar: 'from-gray-400 to-gray-500', chip: 'bg-gray-100 text-gray-700' },
};

export const tone = (name) => TONES[name] ?? TONES.gray;

const ROTATION = ['indigo', 'emerald', 'sky', 'amber', 'fuchsia', 'teal', 'rose', 'violet'];

/** A stable tone per id, so rows of one list don't all share one colour. */
export const toneFor = (id) => ROTATION[Math.abs(Number(id) || 0) % ROTATION.length];
