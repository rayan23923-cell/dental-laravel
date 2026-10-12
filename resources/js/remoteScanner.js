/**
 * The computer's side of "the phone as a QR scanner" (2026-10-12, by
 * request). One shared pairing per browser tab, kept in localStorage so it
 * survives page visits and reloads, polled about once a second for what
 * the phone scanned. Each code is dispatched as a `remote-scan` window
 * event `{ payload, handled }`: an open QrScanner, or a page that scans
 * without opening one (the lab), takes it and sets `handled`. Codes nobody
 * takes are kept in `unhandled` so the pairing button can show them.
 */
import axios from 'axios';
import { onBeforeUnmount, onMounted, reactive } from 'vue';

const STORAGE_KEY = 'scanner-pairing';

export const remoteScanner = reactive({
    pairing: null, // { id, code, url, enter_url, qr, phone_joined, expires_at }
    lastId: 0,
    lastScan: null, // { payload, at }
    unhandled: null,
    error: '',
});

let timer = null;
// After a reload, codes the phone sent while no page was polling are
// dropped, so an old scan never acts on whatever page opens next.
let skipBacklog = false;

const save = () => {
    try {
        if (remoteScanner.pairing) {
            localStorage.setItem(STORAGE_KEY, JSON.stringify({ pairing: remoteScanner.pairing, lastId: remoteScanner.lastId }));
        } else {
            localStorage.removeItem(STORAGE_KEY);
        }
    } catch {
        // Private mode: the pairing just won't survive a reload.
    }
};

const dispatch = (payload) => {
    const detail = { payload, handled: false };
    window.dispatchEvent(new CustomEvent('remote-scan', { detail }));
    remoteScanner.lastScan = { payload, at: Date.now() };
    remoteScanner.unhandled = detail.handled ? null : payload;
};

const poll = async () => {
    const pairing = remoteScanner.pairing;
    if (!pairing) return;
    try {
        const { data } = await axios.get(route('scanner-pairings.scans', pairing.id), { params: { after: remoteScanner.lastId } });
        pairing.phone_joined = data.data.phone_joined;
        const skip = skipBacklog;
        skipBacklog = false;
        for (const scan of data.data.scans) {
            remoteScanner.lastId = scan.id;
            if (!skip) dispatch(scan.payload);
        }
        remoteScanner.error = '';
        save();
    } catch (e) {
        if ([404, 410].includes(e?.response?.status)) {
            remoteScanner.pairing = null;
            save();
            stopPolling();
        }
    }
};

const startPolling = () => {
    if (!timer) timer = setInterval(poll, 1000);
};
const stopPolling = () => {
    clearInterval(timer);
    timer = null;
};

/** Re-attach a pairing saved by an earlier page of this browser. */
export const restoreRemoteScanner = () => {
    if (remoteScanner.pairing) return startPolling();
    try {
        const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null');
        if (saved?.pairing && new Date(saved.pairing.expires_at) > new Date()) {
            remoteScanner.pairing = saved.pairing;
            remoteScanner.lastId = saved.lastId ?? 0;
            skipBacklog = true;
            startPolling();
        }
    } catch {
        // Nothing saved, or unreadable: start unpaired.
    }
};

export const openRemoteScanner = async () => {
    remoteScanner.error = '';
    const { data } = await axios.post(route('scanner-pairings.store'));
    remoteScanner.pairing = data.data;
    remoteScanner.lastId = 0;
    remoteScanner.unhandled = null;
    save();
    startPolling();
};

export const closeRemoteScanner = async () => {
    const pairing = remoteScanner.pairing;
    remoteScanner.pairing = null;
    remoteScanner.unhandled = null;
    save();
    stopPolling();
    if (pairing) await axios.delete(route('scanner-pairings.destroy', pairing.id)).catch(() => {});
};

/**
 * For pages that act on a scan without a camera open (e.g. the lab):
 * `handler(payload)` runs for each phone scan nothing else took while
 * `isFree()` is true. Call from setup(); it unregisters on unmount.
 */
export const onRemoteScan = (handler, isFree = () => true) => {
    const listener = (event) => {
        if (event.detail.handled || !isFree()) return;
        event.detail.handled = true;
        handler(event.detail.payload);
    };
    onMounted(() => window.addEventListener('remote-scan', listener));
    onBeforeUnmount(() => window.removeEventListener('remote-scan', listener));
};
