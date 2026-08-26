<script setup>
/**
 * Interactive per-tooth chart — a faithful rebuild of the odontogram in
 * dental_clinics2/doctor/operative.php, which the earlier port never
 * actually built: `dental_charts.tooth_data` existed as a column, but
 * nothing in this app read or wrote it, and the "tooth chart" on screen was
 * really the quadrant chip-picker (QuadrantTeeth.vue) used for simple
 * "list these teeth" fields elsewhere — a different, much narrower feature
 * than a real per-surface odontogram.
 *
 * Every number in this file (surface geometry, colour, and status
 * vocabulary) was read directly out of the original's own <style> block and
 * JS (updateToothVisualStatus(), the surfaceStatusOptions/rootStatusOptions
 * arrays), not guessed:
 *
 *   Tooth-level status : present · non_vital · missing · extracted ·
 *                         retained_root · crown
 *   Surface status      : healthy · cavity · filling · crown · bridge
 *   Root status (non_vital only, root-1/2/3) :
 *                         healthy · root_canal · infected · treated
 *
 * Data shape matches `tooth_data` exactly, verified against real imported
 * rows (see the case-sheet import work): an array of
 *   { number, position, notes, status, toothStatus, polygons }
 * where `polygons` is a dict keyed by surface id ('top'/'left'/'bottom'/
 * 'right'/'center', or 'root-1'/'root-2'/'root-3' on a non_vital tooth)
 * holding { name, status }. Only touched teeth appear in the array — this
 * matches the original, which never pre-populates all 32.
 */
import { computed, ref } from 'vue';
import Modal from '@/Components/Modal.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import Icon from '@/Components/Icon.vue';

const props = defineProps({
    modelValue: { type: Array, default: () => [] },
    disabled: Boolean,
});

const emit = defineEmits(['update:modelValue']);

const UPPER = [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28];
const LOWER = [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38];

const positionOf = (number) => {
    const quadrant = Math.floor(number / 10);
    return { 1: 'upper_right', 2: 'upper_left', 3: 'lower_left', 4: 'lower_right' }[quadrant] ?? 'upper_right';
};

// The five non-root surfaces every tooth SVG draws, in the original's own
// "flower" target layout (mesial/distal/buccal/lingual/occlusal, expressed
// generically as top/left/bottom/right/center since the original itself
// doesn't distinguish left/right teeth's anatomical surface names either).
const SURFACES = ['top', 'left', 'bottom', 'right', 'center'];
const ROOTS = ['root-1', 'root-2', 'root-3'];

const TOOTH_STATUSES = [
    { value: 'present', label: 'سليم', icon: 'check_circle', color: 'text-emerald-600' },
    { value: 'non_vital', label: 'ميت العصب', icon: 'skull', color: 'text-red-700' },
    { value: 'missing', label: 'مفقود خلقياً', icon: 'remove_circle', color: 'text-gray-500' },
    { value: 'extracted', label: 'مخلوع', icon: 'cancel', color: 'text-gray-600' },
    { value: 'retained_root', label: 'جذر محتجز', icon: 'dentistry', color: 'text-orange-600' },
    { value: 'crown', label: 'تاج', icon: 'workspace_premium', color: 'text-gray-900' },
];

const SURFACE_STATUSES = [
    { value: 'healthy', label: 'سليم', color: '#ffffff' },
    { value: 'cavity', label: 'تسوس', color: '#ffc107' },
    { value: 'filling', label: 'حشوة', color: '#000000' },
    { value: 'crown', label: 'تاج', color: '#17a2b8' },
    { value: 'bridge', label: 'جسر', color: '#6f42c1' },
];

const ROOT_STATUSES = [
    { value: 'healthy', label: 'سليم', color: '#ffffff' },
    { value: 'root_canal', label: 'علاج عصب', color: '#dc3545' },
    { value: 'infected', label: 'ملتهب', color: '#ff9800' },
    { value: 'treated', label: 'مُعالَج', color: '#4caf50' },
];

const TOOTH_LEVEL_FILL = { missing: '#6c757d', extracted: '#6c757d', non_vital: '#8b0000' };
const TOOTH_LEVEL_OPACITY = { missing: 0.15, extracted: 0.35 };

const byNumber = computed(() => {
    const map = new Map();
    (props.modelValue ?? []).forEach((t) => map.set(String(t.number), t));
    return map;
});

const toothOf = (number) => byNumber.value.get(String(number)) ?? null;

const surfaceFill = (number, surfaceId) => {
    const tooth = toothOf(number);
    if (!tooth) return '#ffffff';
    if (tooth.toothStatus && TOOTH_LEVEL_FILL[tooth.toothStatus]) {
        return TOOTH_LEVEL_FILL[tooth.toothStatus];
    }
    const surface = tooth.polygons?.[surfaceId];
    if (!surface?.status) return '#ffffff';
    const pool = surfaceId.startsWith('root-') ? ROOT_STATUSES : SURFACE_STATUSES;
    return pool.find((s) => s.value === surface.status)?.color ?? '#ffffff';
};

const toothOpacity = (number) => {
    const status = toothOf(number)?.toothStatus;
    return status ? (TOOTH_LEVEL_OPACITY[status] ?? 1) : 1;
};

// The target-pattern surface polygon shared by every tooth, copied
// point-for-point from the original's SVG (operative.php).
const SURFACE_POINTS = {
    top: '0,0 30,0 20,10 10,10',
    left: '0,0 10,10 10,20 0,30',
    bottom: '0,30 10,20 20,20 30,30',
    right: '30,0 20,10 20,20 30,30',
    center: '10,10 20,10 20,20 10,20',
};

// --- Editing modal -------------------------------------------------------
const activeNumber = ref(null);
const activeTooth = computed(() => (activeNumber.value ? toothOf(activeNumber.value) : null));
const isNonVital = computed(() => activeTooth.value?.toothStatus === 'non_vital');
const activeSurfaces = computed(() => (isNonVital.value ? ROOTS : SURFACES));
const selectedSurface = ref(null);

const openTooth = (number) => {
    if (props.disabled) return;
    activeNumber.value = number;
    selectedSurface.value = null;
};

const closeModal = () => {
    activeNumber.value = null;
};

const mutate = (number, patch) => {
    const list = [...(props.modelValue ?? [])];
    const idx = list.findIndex((t) => String(t.number) === String(number));

    if (idx === -1) {
        list.push({
            number: String(number),
            position: positionOf(number),
            notes: '',
            status: 'planned',
            toothStatus: 'present',
            polygons: {},
            ...patch,
        });
    } else {
        list[idx] = { ...list[idx], ...patch };
    }

    emit('update:modelValue', list);
};

const setToothStatus = (status) => {
    if (!activeNumber.value) return;
    // Switching to/from non_vital changes which surface set applies
    // (root-1/2/3 instead of top/left/bottom/right/center), so stale
    // polygons from the other set are dropped rather than left orphaned.
    mutate(activeNumber.value, { toothStatus: status, polygons: {} });
    selectedSurface.value = null;
};

const setSurfaceStatus = (surfaceId, status) => {
    if (!activeNumber.value) return;
    const tooth = toothOf(activeNumber.value);
    const polygons = { ...(tooth?.polygons ?? {}) };
    const label = surfaceLabel(surfaceId);
    polygons[surfaceId] = { name: label, status };
    mutate(activeNumber.value, { polygons });
};

const surfaceLabel = (surfaceId) => {
    const labels = {
        top: 'الجزء العلوي', bottom: 'الجزء السفلي', left: 'الجانب الأيسر',
        right: 'الجانب الأيمن', center: 'الوسط',
        'root-1': 'الجذر الأول', 'root-2': 'الجذر الثاني', 'root-3': 'الجذر الثالث',
    };
    return labels[surfaceId] ?? surfaceId;
};

const setNotes = (notes) => activeNumber.value && mutate(activeNumber.value, { notes });
const setTreatmentStatus = (status) => activeNumber.value && mutate(activeNumber.value, { status });

const markedCount = computed(() => (props.modelValue ?? []).length);
</script>

<template>
    <div>
        <div class="mb-2 flex items-center justify-between text-xs text-gray-500">
            <span>اضغط على أي سن لتحديد حالته وأسطحه.</span>
            <span v-if="markedCount">{{ markedCount }} سن مسجَّل</span>
        </div>

        <!--
            Horizontal scroll on a narrow (mobile) viewport: `overflow-x-auto`
            alone isn't enough — a flex row with no explicit width shrinks its
            children to fit instead of overflowing, which is why this
            couldn't be scrolled before. `w-max` on the row stops it
            collapsing (forces its natural, un-shrunk width), and `shrink-0`
            on every tooth button stops the browser's default flex-shrink
            from squeezing them individually; together the row genuinely
            overflows its container and the outer `overflow-x-auto` can
            scroll it.
        -->
        <div class="overflow-x-auto rounded-lg border border-gray-200 bg-gray-50 p-3" style="-webkit-overflow-scrolling: touch;">
            <div v-for="(arch, archIdx) in [{ label: 'الفك العلوي', teeth: UPPER }, { label: 'الفك السفلي', teeth: LOWER }]" :key="arch.label" class="w-max min-w-full" :class="archIdx ? 'mt-4' : ''">
                <div class="mb-1 flex w-full justify-between text-[11px] font-medium text-gray-400">
                    <span>يمين</span>
                    <span>{{ arch.label }}</span>
                    <span>يسار</span>
                </div>
                <div class="flex w-max justify-center gap-0.5">
                    <button
                        v-for="n in arch.teeth"
                        :key="n"
                        type="button"
                        :disabled="disabled"
                        class="group relative flex shrink-0 flex-col items-center rounded p-0.5 transition hover:bg-white disabled:cursor-default"
                        @click="openTooth(n)"
                    >
                        <svg width="22" height="22" viewBox="0 0 30 30" class="drop-shadow-sm" :style="{ opacity: toothOpacity(n) }">
                            <polygon
                                v-for="(points, surfaceId) in SURFACE_POINTS"
                                :key="surfaceId"
                                :points="points"
                                :fill="surfaceFill(n, surfaceId)"
                                stroke="#000"
                                stroke-width="1.5"
                                vector-effect="non-scaling-stroke"
                            />
                            <line
                                v-if="toothOf(n)?.toothStatus === 'extracted'"
                                x1="3" y1="3" x2="27" y2="27" stroke="#dc3545" stroke-width="3" stroke-linecap="round"
                            />
                            <line
                                v-if="toothOf(n)?.toothStatus === 'extracted'"
                                x1="27" y1="3" x2="3" y2="27" stroke="#dc3545" stroke-width="3" stroke-linecap="round"
                            />
                            <circle
                                v-if="toothOf(n)?.toothStatus === 'retained_root'"
                                cx="15" cy="15" r="14" fill="none" stroke="#fd7e14" stroke-width="2"
                            />
                            <circle
                                v-if="toothOf(n)?.toothStatus === 'crown'"
                                cx="15" cy="15" r="14" fill="none" stroke="#000" stroke-width="2"
                            />
                        </svg>
                        <span class="text-[10px] leading-none text-gray-600 group-hover:text-gray-900">{{ n }}</span>
                    </button>
                </div>
            </div>
        </div>

        <!-- Legend — the exact colour vocabulary from the original's CSS. -->
        <div class="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-gray-500">
            <span v-for="s in SURFACE_STATUSES" :key="s.value" class="inline-flex items-center gap-1">
                <span class="h-2.5 w-2.5 rounded-sm border border-gray-400" :style="{ backgroundColor: s.color }"></span>{{ s.label }}
            </span>
            <span class="inline-flex items-center gap-1">
                <span class="h-2.5 w-2.5 rounded-sm border border-gray-400" style="background-color:#8b0000"></span>ميت العصب
            </span>
            <span class="inline-flex items-center gap-1">
                <span class="h-2.5 w-2.5 rounded-sm border border-gray-400 opacity-30" style="background-color:#6c757d"></span>مفقود / مخلوع
            </span>
        </div>

        <Modal :show="activeNumber !== null" @close="closeModal">
            <div class="p-6" v-if="activeTooth || activeNumber">
                <div class="mb-4 text-center">
                    <h3 class="text-lg font-semibold text-gray-900"><Icon name="dentistry" class="ml-1" />السن رقم {{ activeNumber }}</h3>
                    <p class="text-xs text-gray-500">{{ positionOf(activeNumber ?? 0) }}</p>
                </div>

                <!-- The tooth box — a large live preview of the same
                     target-pattern SVG as the main grid (port of the
                     original's #modalToothSvg), so a surface's colour is
                     visible immediately after it's set below. Its polygons
                     are clickable too: clicking one jumps straight to that
                     surface's status row instead of scrolling to find it. -->
                <div class="mb-4 flex justify-center">
                    <svg width="140" height="140" viewBox="0 0 30 30" class="drop-shadow">
                        <polygon
                            v-for="(points, surfaceId) in SURFACE_POINTS"
                            :key="surfaceId"
                            :points="points"
                            :fill="activeNumber ? surfaceFill(activeNumber, surfaceId) : '#ffffff'"
                            stroke="#000"
                            stroke-width="1"
                            vector-effect="non-scaling-stroke"
                            class="cursor-pointer transition hover:opacity-80"
                            :class="{ 'stroke-indigo-500': selectedSurface === surfaceId }"
                            :style="selectedSurface === surfaceId ? { stroke: '#6366f1', strokeWidth: 2 } : {}"
                            @click="!disabled && !isNonVital && (selectedSurface = surfaceId)"
                        />
                        <line v-if="activeTooth?.toothStatus === 'extracted'" x1="3" y1="3" x2="27" y2="27" stroke="#dc3545" stroke-width="2" stroke-linecap="round" />
                        <line v-if="activeTooth?.toothStatus === 'extracted'" x1="27" y1="3" x2="3" y2="27" stroke="#dc3545" stroke-width="2" stroke-linecap="round" />
                        <circle v-if="activeTooth?.toothStatus === 'retained_root'" cx="15" cy="15" r="14" fill="none" stroke="#fd7e14" stroke-width="1.5" />
                        <circle v-if="activeTooth?.toothStatus === 'crown'" cx="15" cy="15" r="14" fill="none" stroke="#000" stroke-width="1.5" />
                    </svg>
                </div>

                <!-- General tooth status -->
                <div class="mb-4">
                    <label class="mb-1.5 block text-sm font-medium text-gray-700">الحالة العامة للسن</label>
                    <div class="grid grid-cols-2 gap-1.5 sm:grid-cols-3">
                        <button
                            v-for="opt in TOOTH_STATUSES"
                            :key="opt.value"
                            type="button"
                            :disabled="disabled"
                            @click="setToothStatus(opt.value)"
                            class="flex items-center gap-1.5 rounded-md border px-2 py-1.5 text-xs transition"
                            :class="(activeTooth?.toothStatus ?? 'present') === opt.value
                                ? 'border-indigo-500 bg-indigo-50 text-indigo-700'
                                : 'border-gray-200 text-gray-600 hover:border-gray-300'"
                        >
                            <Icon :name="opt.icon" size="text-[16px]" :class="opt.color" />{{ opt.label }}
                        </button>
                    </div>
                </div>

                <!-- Per-surface status: five surfaces normally, three roots
                     once the tooth is marked non_vital — matches the
                     original's togglePolygonSection(). -->
                <div v-if="(activeTooth?.toothStatus ?? 'present') === 'present' || isNonVital">
                    <label class="mb-1.5 block text-sm font-medium text-gray-700">
                        {{ isNonVital ? 'حالة الجذور' : 'حالة الأسطح' }}
                    </label>
                    <div class="space-y-2">
                        <div
                            v-for="surfaceId in activeSurfaces"
                            :key="surfaceId"
                            :ref="(el) => selectedSurface === surfaceId && el?.scrollIntoView?.({ block: 'nearest' })"
                            class="rounded-md border p-2 transition"
                            :class="selectedSurface === surfaceId ? 'border-indigo-400 bg-indigo-50/50' : 'border-gray-200'"
                        >
                            <div class="mb-1 text-xs font-medium text-gray-600">{{ surfaceLabel(surfaceId) }}</div>
                            <div class="flex flex-wrap gap-1">
                                <button
                                    v-for="opt in (isNonVital ? ROOT_STATUSES : SURFACE_STATUSES)"
                                    :key="opt.value"
                                    type="button"
                                    :disabled="disabled"
                                    @click="setSurfaceStatus(surfaceId, opt.value)"
                                    class="flex items-center gap-1 rounded border px-2 py-1 text-[11px] transition"
                                    :class="(activeTooth?.polygons?.[surfaceId]?.status ?? 'healthy') === opt.value
                                        ? 'border-gray-900 font-medium'
                                        : 'border-gray-200 text-gray-500 hover:border-gray-300'"
                                >
                                    <span class="h-2.5 w-2.5 rounded-sm border border-gray-400" :style="{ backgroundColor: opt.color }"></span>
                                    {{ opt.label }}
                                </button>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="mt-4">
                    <label class="mb-1 block text-sm font-medium text-gray-700">ملاحظات</label>
                    <textarea
                        :value="activeTooth?.notes ?? ''"
                        :disabled="disabled"
                        rows="2"
                        class="block w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                        @input="setNotes($event.target.value)"
                    ></textarea>
                </div>

                <div class="mt-3">
                    <label class="mb-1 block text-sm font-medium text-gray-700">حالة العلاج</label>
                    <select
                        :value="activeTooth?.status ?? 'planned'"
                        :disabled="disabled"
                        class="block w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                        @change="setTreatmentStatus($event.target.value)"
                    >
                        <option value="planned">مخطط له</option>
                        <option value="in_progress">قيد التنفيذ</option>
                        <option value="completed">مكتمل</option>
                        <option value="failed">فشل</option>
                    </select>
                </div>

                <div class="mt-6 flex justify-end">
                    <SecondaryButton @click="closeModal">إغلاق</SecondaryButton>
                </div>
            </div>
        </Modal>
    </div>
</template>
