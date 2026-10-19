import axios from 'axios';
import { router } from '@inertiajs/vue3';
import { onMounted, onUnmounted } from 'vue';

/**
 * Reloads a registrations page's lists when a patient is registered or
 * changed elsewhere (2026-10-19, by request: the ticket desk and the lab
 * update by themselves). Asks the server for a small fingerprint every few
 * seconds while the page is visible and reloads only `only` when it changes.
 */
export function useLiveRegistrations(only, { every = 5000 } = {}) {
    let last = null;
    let timer = null;
    let busy = false;

    const check = async () => {
        if (busy || document.hidden) return;
        busy = true;
        try {
            const { data } = await axios.get(route('patient-registrations.stamp'));
            if (last !== null && data.stamp !== last) {
                router.reload({ only });
            }
            last = data.stamp;
        } catch {
            // Offline for a moment: try again next time.
        } finally {
            busy = false;
        }
    };

    onMounted(() => {
        check();
        timer = setInterval(check, every);
    });
    onUnmounted(() => clearInterval(timer));
}
