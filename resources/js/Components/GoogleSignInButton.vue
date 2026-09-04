<script setup>
/**
 * "Sign in with Google" — a plain link to
 * App\Http\Controllers\Auth\GoogleAuthController::redirect(), which starts
 * the OAuth handshake server-side. The callback auto-detects staff vs.
 * doctor from the Google account's email (tries `users` then `doctors`,
 * same as the unified login form) — this button no longer needs to say
 * which one in advance.
 *
 * Only rendered when `googleSignInEnabled` (shared globally by
 * HandleInertiaRequests) is true — the backend hides it the same way
 * whenever GOOGLE_CLIENT_ID/SECRET aren't set, so this component doesn't
 * duplicate that check.
 */
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
</script>

<template>
    <a
        :href="route('auth.google.redirect')"
        class="flex w-full items-center justify-center gap-2.5 rounded-lg border border-ig-border-light bg-white px-4 py-2.5 text-sm font-medium text-ig-near-black transition hover:bg-ig-off-white dark:border-ig-border-dark dark:bg-ig-black dark:text-ig-off-white dark:hover:bg-ig-dark-surface"
    >
        <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true">
            <path fill="#4285F4" d="M17.64 9.2c0-.64-.06-1.25-.16-1.84H9v3.48h4.84a4.14 4.14 0 0 1-1.8 2.72v2.26h2.91c1.7-1.57 2.69-3.88 2.69-6.62Z" />
            <path fill="#34A853" d="M9 18c2.43 0 4.47-.8 5.96-2.18l-2.91-2.26c-.81.54-1.84.86-3.05.86-2.34 0-4.33-1.58-5.04-3.71H.96v2.33A9 9 0 0 0 9 18Z" />
            <path fill="#FBBC05" d="M3.96 10.71A5.4 5.4 0 0 1 3.68 9c0-.59.1-1.17.28-1.71V4.96H.96A9 9 0 0 0 0 9c0 1.45.35 2.83.96 4.04l3-2.33Z" />
            <path fill="#EA4335" d="M9 3.58c1.32 0 2.51.45 3.44 1.35l2.58-2.58C13.46.89 11.43 0 9 0A9 9 0 0 0 .96 4.96l3 2.33C4.67 5.16 6.66 3.58 9 3.58Z" />
        </svg>
        {{ t('auth.signInWithGoogle') }}
    </a>
</template>
