import plugin from 'tailwindcss/plugin';
import colors from 'tailwindcss/colors';

/**
 * Repaints page bodies for the dark themes (App\Support\ThemePalette).
 *
 * Most pages were written for a light background with fixed Tailwind greys
 * (`bg-white`, `text-gray-800`, `border-gray-200`) and pastel status tints
 * (`bg-green-50 text-green-700`). Rewriting every page to semantic classes
 * would be a very large diff, so instead, while <html> carries `theme-dark`,
 * these rules remap exactly those light utilities onto the theme tokens:
 *
 * - white / light-grey backgrounds become the theme's surfaces;
 * - dark-grey text becomes the theme's text and muted colours;
 * - light-grey borders, rings and dividers become the hairline colour;
 * - pastel tints become a translucent wash of the same hue, and the dark
 *   text that sits on them is lifted to a light shade so it stays readable.
 *
 * Deliberately dark utilities (`bg-gray-900`, `text-white`, …) are left
 * alone, so the TV board, tooltips and coloured buttons look the same in
 * every theme. The light theme gets none of this: it already matches.
 *
 * Every selector is `html.theme-dark .x` (plus the variant pseudo-class),
 * which outranks the single-class utility it overrides without needing
 * `!important`.
 */
const scope = 'html.theme-dark';
const esc = (cls) => cls.replace(/[:/.]/g, (m) => `\\${m}`);

const token = (name, alpha = 1) => `rgb(var(--c-${name}) / ${alpha})`;
const rgba = (hex, alpha) => {
    const n = parseInt(hex.slice(1), 16);
    return `rgb(${(n >> 16) & 255} ${(n >> 8) & 255} ${n & 255} / ${alpha})`;
};

// [utility prefix, CSS property]
const BG = ['bg', 'background-color'];
const TEXT = ['text', 'color'];
const BORDER = ['border', 'border-color'];
const RING = ['ring', '--tw-ring-color'];

const VARIANTS = {
    '': '',
    'hover:': ':hover',
    'focus:': ':focus',
    'group-hover:': null, // handled separately below
};

const rules = {};
const add = (variant, cls, prop, value) => {
    const pseudo = VARIANTS[variant];
    const selector =
        variant === 'group-hover:'
            ? `${scope} .group:hover .${esc(variant + cls)}`
            : `${scope} .${esc(variant + cls)}${pseudo}`;
    rules[selector] = { ...(rules[selector] || {}), [prop]: value };
};
const addAll = ([prefix, prop], suffix, value) => {
    for (const variant of Object.keys(VARIANTS)) add(variant, `${prefix}-${suffix}`, prop, value);
};

// --- Neutrals ---------------------------------------------------------------
const GREYS = ['gray', 'slate', 'zinc', 'neutral', 'stone'];

addAll(BG, 'white', token('surface'));
for (const a of [95, 90, 80, 75, 70, 60, 50]) addAll(BG, `white/${a}`, token('surface', a / 100));
for (const g of GREYS) {
    addAll(BG, `${g}-50`, token('surface-2'));
    addAll(BG, `${g}-100`, token('surface-2'));
    addAll(BG, `${g}-200`, token('border'));
    addAll(BG, `${g}-300`, token('border'));

    for (const s of [900, 800, 700]) addAll(TEXT, `${g}-${s}`, token('text'));
    for (const s of [600, 500]) addAll(TEXT, `${g}-${s}`, token('muted'));
    for (const s of [400, 300]) addAll(TEXT, `${g}-${s}`, token('muted', 0.75));

    for (const s of [50, 100, 200, 300, 400]) {
        addAll(BORDER, `${g}-${s}`, token('border'));
        addAll(RING, `${g}-${s}`, token('border'));
        rules[`${scope} .${esc(`divide-${g}-${s}`)} > :not([hidden]) ~ :not([hidden])`] = {
            'border-color': token('border'),
        };
    }
}

// --- Status tints -----------------------------------------------------------
const HUES = [
    'red', 'orange', 'amber', 'yellow', 'lime', 'green', 'emerald', 'teal', 'cyan',
    'sky', 'blue', 'indigo', 'violet', 'purple', 'fuchsia', 'pink', 'rose',
];
for (const h of HUES) {
    const c = colors[h];
    addAll(BG, `${h}-50`, rgba(c[500], 0.12));
    addAll(BG, `${h}-100`, rgba(c[500], 0.18));
    addAll(BG, `${h}-200`, rgba(c[500], 0.28));
    for (const s of [100, 200, 300]) {
        addAll(BORDER, `${h}-${s}`, rgba(c[500], 0.35));
        addAll(RING, `${h}-${s}`, rgba(c[500], 0.35));
    }
    addAll(TEXT, `${h}-600`, c[400]);
    for (const s of [700, 800, 900]) addAll(TEXT, `${h}-${s}`, c[300]);
}

// --- SVG charts and form controls ------------------------------------------
for (const g of GREYS) {
    for (const s of [100, 200, 300]) rules[`${scope} .${esc(`stroke-${g}-${s}`)}`] = { stroke: token('border') };
    for (const s of [400, 500, 600, 700]) rules[`${scope} .${esc(`fill-${g}-${s}`)}`] = { fill: token('muted') };
}

export default plugin(({ addBase }) => {
    addBase({
        // Native date pickers, scrollbars and checkboxes follow the theme too.
        [`${scope}`]: { 'color-scheme': 'dark' },
        [`${scope} body`]: { 'background-color': token('bg'), color: token('text') },
        // @tailwindcss/forms paints inputs white; give them the raised surface.
        [`${scope} :where(input:not([type=checkbox]):not([type=radio]):not([type=range]):not([type=color]), select, textarea)`]: {
            'background-color': token('surface-2'),
            color: token('text'),
            'border-color': token('border'),
        },
        [`${scope} :where(input, textarea)::placeholder`]: { color: token('muted', 0.8) },
        [`${scope} .bg-transparent`]: { 'background-color': 'transparent !important' },
        ...rules,
    });
});
