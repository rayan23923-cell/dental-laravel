/**
 * Number fields accept numbers only (2026-10-14, by request: "حقول الارقام
 * لاتقبل سوى الارقام"). One document-level guard instead of a rule per
 * field: every <input type="number">, <input type="tel"> and any input
 * with inputmode="numeric"/"decimal" refuses letters and symbols as they
 * are typed or pasted, and Arabic-Indic digits (٠-٩, ۰-۹) become 0-9.
 *
 * Allowed besides digits: "." when the field takes fractions (a step with
 * a decimal point, step="any" or inputmode="decimal"), "-" when min < 0,
 * and "+", spaces and "-" in phone (tel) fields. The server still
 * validates every value; this only stops wrong input at the keyboard.
 */

const ARABIC_DIGITS = /[٠-٩۰-۹]/g;
const toAscii = (s) => s.replace(ARABIC_DIGITS, (d) => String((d.charCodeAt(0) & 0xf) % 10));

const isNumeric = (el) =>
    el instanceof HTMLInputElement &&
    !el.readOnly &&
    (el.type === 'number' || el.type === 'tel' || ['numeric', 'decimal'].includes(el.inputMode));

const allowedChars = (el) => {
    if (el.type === 'tel') return /[0-9+\- ]/;
    const step = el.getAttribute('step') ?? '';
    const decimal = el.inputMode === 'decimal' || step === 'any' || step.includes('.');
    const negative = el.min !== '' && Number(el.min) < 0;
    return new RegExp(`[0-9${decimal ? '.' : ''}${negative ? '\\-' : ''}]`);
};

const clean = (el, text) => {
    const allowed = allowedChars(el);
    return [...toAscii(text)].filter((c) => allowed.test(c)).join('');
};

// Number inputs have no selection API, so their text is appended.
const insert = (el, text) => {
    if (!text) return;
    if (el.type === 'number') {
        el.value = `${el.value}${text}`;
    } else {
        el.setRangeText(text, el.selectionStart ?? el.value.length, el.selectionEnd ?? el.value.length, 'end');
    }
    el.dispatchEvent(new Event('input', { bubbles: true }));
};

export function installNumericInputs() {
    // Keyboards that report real keys (desktop).
    document.addEventListener(
        'keydown',
        (e) => {
            const el = e.target;
            if (!isNumeric(el) || e.ctrlKey || e.metaKey || e.altKey || e.key.length !== 1) return;
            if (allowedChars(el).test(e.key)) return;
            e.preventDefault();
            insert(el, clean(el, e.key));
        },
        true,
    );

    // Paste and drop.
    document.addEventListener(
        'paste',
        (e) => {
            const el = e.target;
            if (!isNumeric(el)) return;
            const text = e.clipboardData?.getData('text') ?? '';
            const cleaned = clean(el, text);
            if (cleaned === text) return;
            e.preventDefault();
            insert(el, cleaned);
        },
        true,
    );

    // Phone keyboards that don't report keys: tidy the value before v-model reads it.
    document.addEventListener(
        'input',
        (e) => {
            const el = e.target;
            if (!isNumeric(el) || el.type === 'number') return;
            const cleaned = clean(el, el.value);
            if (cleaned !== el.value) el.value = cleaned;
        },
        true,
    );
}
