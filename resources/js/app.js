import '../css/app.css';
import './bootstrap';

import { createInertiaApp } from '@inertiajs/vue3';
import { resolvePageComponent } from 'laravel-vite-plugin/inertia-helpers';
import { createApp, h } from 'vue';
import { ZiggyVue } from '../../vendor/tightenco/ziggy';
import { createI18nInstance } from './i18n';
import { installNumericInputs } from './numericInputs';

const appName = import.meta.env.VITE_APP_NAME || 'Laravel';

installNumericInputs();

createInertiaApp({
    title: (title) => `${title} - ${appName}`,
    resolve: (name) =>
        resolvePageComponent(
            `./Pages/${name}.vue`,
            import.meta.glob('./Pages/**/*.vue'),
        ),
    setup({ el, App, props, plugin }) {
        // `props.initialPage.props.locale` — the same value ResolveLocale
        // resolved server-side and app.blade.php already rendered
        // `<html lang>` with (see i18n.js's own doc comment).
        return createApp({ render: () => h(App, props) })
            .use(plugin)
            .use(ZiggyVue)
            .use(createI18nInstance(props.initialPage.props.locale))
            .mount(el);
    },
    progress: {
        color: '#4B5563',
    },
});
