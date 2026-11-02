// "تثبيت التطبيق" (2026-11-02, by request): Chrome/Edge/Android fire
// beforeinstallprompt once, early; keep it so a button can use it later.
import { reactive } from 'vue';

export const installState = reactive({ deferred: null, installed: false });

if (typeof window !== 'undefined') {
    window.addEventListener('beforeinstallprompt', (e) => {
        e.preventDefault();
        installState.deferred = e;
    });
    window.addEventListener('appinstalled', () => {
        installState.deferred = null;
        installState.installed = true;
    });
}

export const isStandalone = () =>
    typeof window !== 'undefined' &&
    (window.matchMedia?.('(display-mode: standalone)').matches || window.navigator.standalone === true);

export const isIos = () =>
    typeof navigator !== 'undefined' &&
    (/iphone|ipad|ipod/i.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1));
