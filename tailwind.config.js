import defaultTheme from 'tailwindcss/defaultTheme';
import forms from '@tailwindcss/forms';

/** @type {import('tailwindcss').Config} */
export default {
    content: [
        './vendor/laravel/framework/src/Illuminate/Pagination/resources/views/*.blade.php',
        './storage/framework/views/*.php',
        './resources/views/**/*.blade.php',
        './resources/js/**/*.vue',
    ],

    theme: {
        extend: {
            fontFamily: {
                sans: ['Figtree', ...defaultTheme.fontFamily.sans],
            },

            /**
             * Semantic colours backed by the CSS variables the root Blade
             * view writes onto <html> (see App\Support\ThemePalette). Using
             * variables rather than fixed values means switching theme is a
             * settings change, not a rebuild.
             *
             * The `<alpha-value>` placeholder is why those variables hold
             * space-separated RGB channels — it is what lets `bg-accent/20`
             * and `border-hairline/60` work.
             */
            colors: {
                app: 'rgb(var(--c-bg) / <alpha-value>)',
                'app-soft': 'rgb(var(--c-bg-soft) / <alpha-value>)',
                surface: 'rgb(var(--c-surface) / <alpha-value>)',
                'surface-2': 'rgb(var(--c-surface-2) / <alpha-value>)',
                hairline: 'rgb(var(--c-border) / <alpha-value>)',
                content: 'rgb(var(--c-text) / <alpha-value>)',
                muted: 'rgb(var(--c-muted) / <alpha-value>)',
                accent: {
                    DEFAULT: 'rgb(var(--c-accent) / <alpha-value>)',
                    deep: 'rgb(var(--c-accent-2) / <alpha-value>)',
                    fg: 'rgb(var(--c-accent-fg) / <alpha-value>)',
                },
            },

            borderRadius: {
                card: '1.25rem',
            },

            boxShadow: {
                // The unit panel's cards read as raised slabs: a soft drop
                // shadow plus a faint inner top highlight.
                panel: '0 10px 30px -12px rgb(0 0 0 / 0.55), inset 0 1px 0 0 rgb(255 255 255 / 0.05)',
                glow: '0 8px 26px -6px rgb(var(--c-accent) / 0.45)',
            },
        },
    },

    plugins: [forms],
};
