<script setup>
/**
 * Camera QR scanner — ports the scanner modal from
 * dental_clinics2/admin/task_progress_view.php (start/stop, camera switch)
 * and adds a torch/flash control.
 *
 * Decoding strategy, chosen for device coverage rather than convenience:
 *  - `BarcodeDetector` when the browser has it (Chrome/Edge, Android) —
 *    hardware-accelerated and cheap;
 *  - `jsQR` otherwise (Safari/iOS, Firefox), decoding frames off a canvas.
 * Both paths feed the same callback, so behaviour doesn't change with the
 * browser.
 *
 * Torch is only exposable where the platform allows it: it needs an active
 * video track whose capabilities advertise `torch`. Android Chrome does;
 * **iOS Safari does not expose torch to web pages at all**, so the button
 * is hidden there rather than shown broken. Camera access also requires a
 * secure context — https, or localhost — which is why a plain-http LAN IP
 * gets an explicit warning instead of a silent failure.
 */
import { onBeforeUnmount, ref } from 'vue';
import jsQR from 'jsqr';
import Icon from '@/Components/Icon.vue';

const emit = defineEmits(['decoded', 'close']);

const video = ref(null);
const canvas = ref(null);
const scanning = ref(false);
const error = ref('');
const torchOn = ref(false);
const torchSupported = ref(false);
const cameras = ref([]);
const cameraIndex = ref(0);

let stream = null;
let track = null;
let detector = null;
let rafId = null;
let stopped = false;

const secureOk = () =>
    window.isSecureContext || ['localhost', '127.0.0.1'].includes(window.location.hostname);

const listCameras = async () => {
    const devices = await navigator.mediaDevices.enumerateDevices();
    cameras.value = devices.filter((d) => d.kind === 'videoinput');
};

const start = async () => {
    error.value = '';

    if (!navigator.mediaDevices?.getUserMedia) {
        error.value = 'هذا المتصفح لا يدعم الوصول إلى الكاميرا.';
        return;
    }
    if (!secureOk()) {
        error.value =
            'الكاميرا تتطلب اتصالاً آمناً (HTTPS) أو فتح الموقع عبر localhost. على عنوان الشبكة المحلية بدون HTTPS يمنع المتصفح تشغيل الكاميرا.';
        return;
    }

    try {
        stopped = false;
        const deviceId = cameras.value[cameraIndex.value]?.deviceId;
        stream = await navigator.mediaDevices.getUserMedia({
            video: deviceId
                ? { deviceId: { exact: deviceId } }
                : { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } },
            audio: false,
        });

        // Labels are only populated after permission is granted, so the
        // camera list is (re)read here rather than on mount.
        await listCameras();

        video.value.srcObject = stream;
        await video.value.play();

        track = stream.getVideoTracks()[0];
        torchSupported.value = !!track?.getCapabilities?.().torch;
        torchOn.value = false;

        if ('BarcodeDetector' in window) {
            const formats = await window.BarcodeDetector.getSupportedFormats();
            if (formats.includes('qr_code')) {
                detector = new window.BarcodeDetector({ formats: ['qr_code'] });
            }
        }

        scanning.value = true;
        tick();
    } catch (e) {
        error.value =
            e?.name === 'NotAllowedError'
                ? 'تم رفض إذن الكاميرا. اسمح بالوصول من إعدادات المتصفح ثم أعد المحاولة.'
                : `تعذر تشغيل الكاميرا: ${e?.message ?? e}`;
        stop();
    }
};

const handle = (text) => {
    if (!text || stopped) return;
    stopped = true;
    emit('decoded', text);
    stop();
};

const tick = async () => {
    if (stopped || !video.value || video.value.readyState !== video.value.HAVE_ENOUGH_DATA) {
        rafId = requestAnimationFrame(tick);
        return;
    }

    try {
        if (detector) {
            const codes = await detector.detect(video.value);
            if (codes.length) return handle(codes[0].rawValue);
        } else {
            const c = canvas.value;
            const w = video.value.videoWidth;
            const h = video.value.videoHeight;
            if (w && h) {
                c.width = w;
                c.height = h;
                const ctx = c.getContext('2d', { willReadFrequently: true });
                ctx.drawImage(video.value, 0, 0, w, h);
                const img = ctx.getImageData(0, 0, w, h);
                const code = jsQR(img.data, w, h, { inversionAttempts: 'dontInvert' });
                if (code?.data) return handle(code.data);
            }
        }
    } catch {
        // A single bad frame shouldn't kill the loop.
    }

    rafId = requestAnimationFrame(tick);
};

const toggleTorch = async () => {
    if (!track) return;
    try {
        await track.applyConstraints({ advanced: [{ torch: !torchOn.value }] });
        torchOn.value = !torchOn.value;
    } catch {
        torchSupported.value = false;
        error.value = 'هذا الجهاز لا يسمح بالتحكم بالفلاش من المتصفح.';
    }
};

const switchCamera = async () => {
    if (cameras.value.length < 2) return;
    cameraIndex.value = (cameraIndex.value + 1) % cameras.value.length;
    stop();
    await start();
};

const stop = () => {
    stopped = true;
    scanning.value = false;
    if (rafId) cancelAnimationFrame(rafId);
    rafId = null;
    // Turning the torch off before releasing the track avoids leaving the
    // LED on after the modal closes on some Android devices.
    if (torchOn.value && track) {
        track.applyConstraints({ advanced: [{ torch: false }] }).catch(() => {});
        torchOn.value = false;
    }
    stream?.getTracks().forEach((t) => t.stop());
    stream = null;
    track = null;
    detector = null;
};

onBeforeUnmount(stop);

defineExpose({ start, stop });
</script>

<template>
    <div>
        <div v-if="error" class="mb-3 rounded-md bg-red-50 p-3 text-sm text-red-700">{{ error }}</div>

        <div class="relative overflow-hidden rounded-xl bg-black" style="aspect-ratio: 4 / 3">
            <video ref="video" playsinline muted class="h-full w-full object-cover"></video>
            <canvas ref="canvas" class="hidden"></canvas>

            <!-- Aiming frame -->
            <div v-if="scanning" class="pointer-events-none absolute inset-0 flex items-center justify-center">
                <div class="h-2/3 w-2/3 rounded-xl border-4 border-green-400/80"></div>
            </div>

            <div v-if="!scanning" class="absolute inset-0 flex items-center justify-center text-sm text-white/70">
                الكاميرا متوقفة
            </div>
        </div>

        <div class="mt-3 flex flex-wrap justify-center gap-2">
            <button v-if="!scanning" type="button" @click="start" class="rounded-md bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700">
                <Icon name="play_arrow" class="ml-1" />بدء المسح
            </button>
            <button v-else type="button" @click="stop" class="rounded-md bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700">
                <Icon name="stop" class="ml-1" />إيقاف
            </button>

            <button
                v-if="scanning && torchSupported"
                type="button"
                @click="toggleTorch"
                class="rounded-md px-4 py-2 text-sm font-medium"
                :class="torchOn ? 'bg-amber-400 text-gray-900' : 'bg-gray-200 text-gray-700 hover:bg-gray-300'"
            >
                <Icon :name="torchOn ? 'flashlight_off' : 'flashlight_on'" class="ml-1" />
                {{ torchOn ? 'إطفاء الفلاش' : 'تشغيل الفلاش' }}
            </button>

            <button
                v-if="scanning && cameras.length > 1"
                type="button"
                @click="switchCamera"
                class="rounded-md bg-gray-200 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-300"
            >
                <Icon name="autorenew" class="ml-1" />تبديل الكاميرا
            </button>
        </div>

        <p v-if="scanning && !torchSupported" class="mt-2 text-center text-xs text-gray-400">
            الفلاش غير متاح على هذا الجهاز/المتصفح (متصفح iOS لا يتيح التحكم بالفلاش للمواقع).
        </p>
    </div>
</template>
