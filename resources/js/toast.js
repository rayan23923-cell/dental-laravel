import Swal from 'sweetalert2';
import 'sweetalert2/dist/sweetalert2.min.css';

/**
 * Professional notifications for every page (2026-11-18, by request):
 * a toast for saved / updated / deleted («success» flash), errors and
 * validation problems, and a styled confirmation dialog instead of the
 * browser's plain confirm(). Shown from app.js for every Inertia visit, so
 * a page needs nothing of its own. Follows the page direction (RTL for
 * Arabic) and the app's font.
 */
// A page window (Modal.vue) is a native <dialog> opened with showModal(),
// which sits in the browser's top layer above everything, whatever its
// z-index. So notifications and confirmations open inside the topmost open
// window when there is one, else on the page (2026-11-18 fix: the delete
// confirmation showed behind «خدمات المختبر»).
const target = () => {
    const open = document.querySelectorAll('dialog[open]');
    return open.length ? open[open.length - 1] : document.body;
};

const Toast = Swal.mixin({
    toast: true,
    position: 'top-end',
    showConfirmButton: false,
    timer: 3500,
    timerProgressBar: true,
    customClass: { popup: 'app-toast' },
    didOpen: (el) => {
        el.addEventListener('mouseenter', Swal.stopTimer);
        el.addEventListener('mouseleave', Swal.resumeTimer);
    },
});

let last = { text: '', at: 0 };
const fresh = (text) => {
    const now = Date.now();
    if (text === last.text && now - last.at < 1500) return false;
    last = { text, at: now };
    return true;
};

export const toast = {
    success(text) {
        if (text && fresh(text)) Toast.fire({ icon: 'success', title: text, target: target() });
    },
    error(text) {
        if (text && fresh(text)) Toast.fire({ icon: 'error', title: text, timer: 7000, target: target() });
    },
    info(text) {
        if (text && fresh(text)) Toast.fire({ icon: 'info', title: text, target: target() });
    },
};

/** The flash messages a response carries (`flash.success` / `flash.error`). */
export function showFlash(flash) {
    if (!flash) return;
    toast.success(flash.success);
    toast.error(flash.error);
}

/** A validation failure: its first message, or a general hint. */
export function showErrors(errors) {
    const messages = Object.values(errors ?? {}).flat().filter(Boolean);
    if (!messages.length) return;
    const ar = document.documentElement.lang !== 'en';
    const head = ar ? 'تحقق من الحقول' : 'Please check the form';
    toast.error(messages.length === 1 ? messages[0] : `${head}: ${messages[0]}`);
}

/**
 * Styled replacement for window.confirm(): resolves true when confirmed.
 * Usage: `if (!(await confirmDialog(text))) return;`
 */
export async function confirmDialog(text, { danger = true } = {}) {
    const ar = document.documentElement.lang !== 'en';
    const host = target();
    // Esc closes the confirmation only, not the window it opened in.
    const keep = (e) => e.preventDefault();
    if (host !== document.body) host.addEventListener('cancel', keep);
    const result = await Swal.fire({
        text,
        target: host,
        icon: danger ? 'warning' : 'question',
        showCancelButton: true,
        focusCancel: true,
        confirmButtonText: ar ? 'نعم، متابعة' : 'Yes, continue',
        cancelButtonText: ar ? 'إلغاء' : 'Cancel',
        customClass: {
            popup: 'app-dialog',
            confirmButton: danger ? 'app-dialog-danger' : 'app-dialog-primary',
            cancelButton: 'app-dialog-cancel',
        },
        buttonsStyling: false,
    });
    if (host !== document.body) host.removeEventListener('cancel', keep);
    return result.isConfirmed;
}
