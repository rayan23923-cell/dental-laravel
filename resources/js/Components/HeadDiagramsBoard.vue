<script setup>
/**
 * Head pain-location diagrams — port of oral_medicine.php's four
 * `headDiagram{Frontal,Posterior,Right,Left}` canvases
 * (extraoral_intraoral_examination.head_diagrams). Each is the original's
 * real reference image (dental_clinics2/uploads/{front,back,right,left}.jpg,
 * copied to public/images/head-diagrams/) with click-to-mark points: pick a
 * pain-quality pattern from the dropdown, click the diagram, a symbol is
 * stamped there. Not freehand drawing — the original only ever adds one
 * point per click (`mousedown`/`touchstart`; `mouseup`/`touchend` just reset
 * a flag nothing else reads).
 *
 * modelValue is `{ frontal: [{x,y,type}], posterior: [...], right: [...],
 * left: [...] }`, points stored in the image's *natural* pixel space
 * (the original's `baseWidth`/`baseHeight`) so a chart saved at one screen
 * size still lines up when reopened at another — same reasoning the
 * original's own scaleX/scaleY conversion uses.
 *
 * Symbols are redrawn pixel-for-pixel from the original's
 * drawPainPatternForHeadDiagram(): ||||| mild, wavy MMM moderate, /////
 * severe, and single letters B/D/N/P/S/T/R for
 * burning/dull/numbing/pressure/sharp/tingling/radiating.
 */
import { onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue';

const props = defineProps({
    modelValue: { type: Object, default: () => ({}) },
    disabled: Boolean,
});

const emit = defineEmits(['update:modelValue']);

const VIEWS = [
    { key: 'frontal', label: 'Frontal', image: '/images/head-diagrams/frontal.jpg' },
    { key: 'posterior', label: 'Posterior', image: '/images/head-diagrams/posterior.jpg' },
    { key: 'right', label: 'Right', image: '/images/head-diagrams/right.jpg' },
    { key: 'left', label: 'Left', image: '/images/head-diagrams/left.jpg' },
];

const PATTERNS = [
    { value: 'mild', label: 'Mild (|||||)' },
    { value: 'moderate', label: 'Moderate (MMM)' },
    { value: 'severe', label: 'Severe (/////)' },
    { value: 'burning', label: 'B Burning' },
    { value: 'dull', label: 'D Dull' },
    { value: 'numbing', label: 'N Numbing' },
    { value: 'pressure', label: 'P Pressure' },
    { value: 'sharp', label: 'S Sharp' },
    { value: 'tingling', label: 'T Tingling' },
    { value: 'radiating', label: 'R Radiating' },
];

const canvasRefs = {};
const containerRefs = {};
const setCanvasRef = (key) => (el) => { canvasRefs[key] = el; };
const setContainerRef = (key) => (el) => { containerRefs[key] = el; };

const currentPattern = reactive(Object.fromEntries(VIEWS.map((v) => [v.key, 'mild'])));
const base = reactive(Object.fromEntries(VIEWS.map((v) => [v.key, { width: 200, height: 250 }])));
const images = {};

const drawings = (key) => props.modelValue?.[key] ?? [];

const drawSymbol = (ctx, x, y, type, scale) => {
    ctx.save();
    ctx.translate(x, y);
    const lineWidth = Math.max(1.2, 1.2 * scale);
    ctx.lineWidth = lineWidth;
    ctx.strokeStyle = '#000';
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    if (type === 'mild') {
        const spacing = 4 * scale, startX = -8 * scale, h = 20 * scale;
        for (let i = 0; i < 5; i++) {
            const xPos = startX + i * spacing;
            ctx.beginPath();
            ctx.moveTo(xPos, -h / 2);
            ctx.lineTo(xPos, h / 2);
            ctx.stroke();
        }
    } else if (type === 'moderate') {
        const spacing = 8 * scale, startX = -8 * scale, wh = 5 * scale;
        for (let i = 0; i < 3; i++) {
            const xPos = startX + i * spacing;
            ctx.beginPath();
            ctx.moveTo(xPos, 0);
            ctx.quadraticCurveTo(xPos + spacing / 4, -wh, xPos + spacing / 2, 0);
            ctx.quadraticCurveTo(xPos + (spacing * 3) / 4, wh, xPos + spacing, 0);
            ctx.stroke();
        }
    } else if (type === 'severe') {
        const spacing = 4 * scale, startX = -8 * scale, h = 20 * scale, diag = 3 * scale;
        for (let i = 0; i < 5; i++) {
            const xPos = startX + i * spacing;
            ctx.beginPath();
            ctx.moveTo(xPos, -h / 2);
            ctx.lineTo(xPos + diag, h / 2);
            ctx.stroke();
        }
    } else {
        const letters = { burning: 'B', dull: 'D', numbing: 'N', pressure: 'P', sharp: 'S', tingling: 'T', radiating: 'R' };
        if (letters[type]) {
            ctx.font = `${14 * scale}px Arial`;
            ctx.fillStyle = '#000';
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';
            ctx.fillText(letters[type], 0, 0);
        }
    }
    ctx.restore();
};

const redraw = (key) => {
    const canvas = canvasRefs[key];
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    const img = images[key];
    if (img && img.complete && img.naturalWidth > 0) {
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
    } else {
        ctx.fillStyle = '#f8f9fa';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.strokeStyle = '#ccc';
        ctx.strokeRect(5, 5, canvas.width - 10, canvas.height - 10);
    }

    const scale = Math.max(0.8, Math.min(canvas.width / base[key].width, canvas.height / base[key].height));
    drawings(key).forEach((p) => {
        const x = p.x * (canvas.width / base[key].width);
        const y = p.y * (canvas.height / base[key].height);
        drawSymbol(ctx, x, y, p.type, scale);
    });
};

const sizeCanvas = (key) => {
    const canvas = canvasRefs[key];
    const container = containerRefs[key];
    if (!canvas || !container) return;
    const maxWidth = Math.min(container.offsetWidth - 20, 300);
    const aspect = base[key].height / base[key].width;
    canvas.width = maxWidth;
    canvas.height = maxWidth * aspect;
    redraw(key);
};

const handleClick = (key, event) => {
    if (props.disabled) return;
    const canvas = canvasRefs[key];
    const rect = canvas.getBoundingClientRect();
    const point = event.touches?.[0] ?? event;
    const canvasX = (point.clientX - rect.left) * (canvas.width / rect.width);
    const canvasY = (point.clientY - rect.top) * (canvas.height / rect.height);
    const baseX = canvasX * (base[key].width / canvas.width);
    const baseY = canvasY * (base[key].height / canvas.height);

    const next = { ...props.modelValue, [key]: [...drawings(key), { x: baseX, y: baseY, type: currentPattern[key] }] };
    emit('update:modelValue', next);
};

const clearView = (key) => {
    if (props.disabled) return;
    emit('update:modelValue', { ...props.modelValue, [key]: [] });
};

let resizeTimeout;
const onResize = () => {
    clearTimeout(resizeTimeout);
    resizeTimeout = setTimeout(() => VIEWS.forEach((v) => sizeCanvas(v.key)), 200);
};

onMounted(() => {
    VIEWS.forEach((v) => {
        const img = new Image();
        images[v.key] = img;
        img.onload = () => {
            base[v.key] = { width: img.naturalWidth, height: img.naturalHeight };
            sizeCanvas(v.key);
        };
        img.onerror = () => sizeCanvas(v.key);
        img.src = v.image;
        sizeCanvas(v.key);
    });
    window.addEventListener('resize', onResize);
});

onBeforeUnmount(() => window.removeEventListener('resize', onResize));

// Redraw whenever the stored points change (e.g. loading an existing record).
watch(() => props.modelValue, () => VIEWS.forEach((v) => redraw(v.key)), { deep: true });
</script>

<template>
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div v-for="v in VIEWS" :key="v.key" :ref="setContainerRef(v.key)" class="rounded-lg border border-gray-200 p-3">
            <p class="mb-2 text-center text-xs font-bold uppercase tracking-wide text-gray-500">{{ v.label }}</p>
            <canvas
                :ref="setCanvasRef(v.key)"
                class="mx-auto block"
                :style="{ cursor: disabled ? 'default' : 'crosshair', touchAction: 'none' }"
                @mousedown="handleClick(v.key, $event)"
                @touchstart.prevent="handleClick(v.key, $event)"
            ></canvas>
            <div class="mt-2 flex items-center justify-center gap-2">
                <select v-model="currentPattern[v.key]" :disabled="disabled" class="rounded-md border-gray-300 text-xs shadow-sm focus:border-indigo-500 focus:ring-indigo-500">
                    <option v-for="p in PATTERNS" :key="p.value" :value="p.value">{{ p.label }}</option>
                </select>
                <button type="button" :disabled="disabled" class="rounded border border-gray-300 px-2 py-1 text-xs text-gray-600 hover:bg-gray-50 disabled:opacity-50" @click="clearView(v.key)">
                    Clear
                </button>
            </div>
        </div>
    </div>
</template>
