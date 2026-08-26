import { defineConfig } from 'vite';
import laravel from 'laravel-vite-plugin';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
    /**
     * Relative asset URLs.
     *
     * The app is served from a sub-directory (`/dental_laravel/public`), not
     * a domain root. With Vite's default base, `url()` references inside the
     * built CSS come out root-absolute — `/build/assets/…woff2` — which
     * resolves to `http://host/build/…` and 404s. The stylesheet itself still
     * loads (Laravel's @vite tag builds that URL from the app path), so the
     * page looks right while the icon font silently fails and every
     * Material Symbols ligature renders as its literal name ("mail", "lock").
     *
     * `./` makes those URLs relative to the stylesheet, so they resolve
     * wherever the folder is deployed. Preferred over setting ASSET_URL,
     * which would hard-code this particular sub-directory into the build.
     */
    base: './',

    plugins: [
        laravel({
            input: 'resources/js/app.js',
            refresh: true,
        }),
        vue({
            template: {
                transformAssetUrls: {
                    base: null,
                    includeAbsolute: false,
                },
            },
        }),
    ],
});
