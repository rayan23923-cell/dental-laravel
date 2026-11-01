import '../css/app.css';
import './bootstrap';

import { createInertiaApp } from '@inertiajs/vue3';
import { resolvePageComponent } from 'laravel-vite-plugin/inertia-helpers';
import { createApp, h } from 'vue';
import { ZiggyVue } from '../../vendor/tightenco/ziggy';
import { createI18nInstance } from './i18n';
import ConnectionStatus from './Components/ConnectionStatus.vue';
import { installNumericInputs } from './numericInputs';

// The clinic's name from its settings, rendered by app.blade.php; never the framework's "Laravel".
const appName = document.querySelector('meta[name="app-name"]')?.content || import.meta.env.VITE_APP_NAME || 'Dental Clinic';

installNumericInputs();

createInertiaApp({
    title: (title) => (title ? `${title} - ${appName}` : appName),
    resolve: (name) =>
        resolvePageComponent(
            `./Pages/${name}.vue`,
            import.meta.glob('./Pages/**/*.vue'),
        ),
    setup({ el, App, props, plugin }) {
        // `props.initialPage.props.locale` — the same value ResolveLocale
        // resolved server-side and app.blade.php already rendered
        // `<html lang>` with (see i18n.js's own doc comment).
        // ConnectionStatus: the network / server bar on every page (2026-11-01).
        return createApp({ render: () => [h(App, props), h(ConnectionStatus)] })
            .use(plugin)
            .use(ZiggyVue)
            .use(createI18nInstance(props.initialPage.props.locale))
            .mount(el);
    },
    progress: {
        color: '#4B5563',
    },
});
