<script setup>
import DoctorLayout from '@/Layouts/DoctorLayout.vue';
import Modal from '@/Components/Modal.vue';
import PaperPhotos from '@/Components/PaperPhotos.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import { Head, Link, router } from '@inertiajs/vue3';
import { computed, ref } from 'vue';
import axios from 'axios';
import { useI18n } from 'vue-i18n';
import Icon from '@/Components/Icon.vue';

const { t } = useI18n();
const props = defineProps({
    stage: String,
    departments: Array,
    // The doctor's own start requests (2026-10-14).
    requests: { type: Array, default: () => [] },
});

// "كل المهام" | "بانتظار الموافقة" | "المعلقة" (2026-10-14, by request).
const tab = ref('all');
const waitingRequests = computed(() => props.requests.filter((r) => r.status === 'pending' || r.status === 'rejected'));
const pendingCount = computed(() => props.requests.filter((r) => r.status === 'pending').length);
// Tasks with a slot nobody has started yet.
const notStartedTasks = computed(() =>
    props.departments.flatMap((d) => d.tasks).filter((task) => task.slots.some((slot) => slot.status === 'unassigned')),
);

// Request to start a task: the electronic form (the doctor's draft) or a
// photo of the paper one.
const requestTask = ref(null);
const requestForm = ref({ form_type: 'electronic', photo: null, notes: '' });
const requestError = ref('');
const requestBusy = ref(false);
const openRequest = (task) => {
    requestTask.value = task;
    requestForm.value = { form_type: 'electronic', photo: null, notes: '' };
    requestError.value = '';
};
const submitRequest = async () => {
    requestBusy.value = true;
    requestError.value = '';
    const body = new FormData();
    body.append('task_id', requestTask.value.id);
    body.append('form_type', requestForm.value.form_type);
    if (requestForm.value.notes) body.append('notes', requestForm.value.notes);
    if (requestForm.value.form_type === 'paper' && requestForm.value.photo) body.append('photo', requestForm.value.photo);
    try {
        await axios.post(route('doctor.task-start-requests.store'), body);
        requestTask.value = null;
        tab.value = 'waiting';
        router.reload({ preserveScroll: true });
    } catch (e) {
        const errors = e.response?.data?.errors;
        requestError.value = errors ? Object.values(errors).flat()[0] : e.response?.data?.message ?? t('taskRequests.actionFailed');
    } finally {
        requestBusy.value = false;
    }
};
const cancelRequest = async (request) => {
    if (!confirm(t('taskRequests.cancelConfirm'))) return;
    await axios.delete(route('doctor.task-start-requests.destroy', request.id));
    router.reload({ preserveScroll: true });
};
const fmtTime = (v) => (v ? new Date(v).toLocaleString(t('sessions.dateLocale'), { dateStyle: 'medium', timeStyle: 'short' }) : '');

const openDepartments = ref(new Set());
const toggle = (name) => {
    const next = new Set(openDepartments.value);
    next.has(name) ? next.delete(name) : next.add(name);
    openDepartments.value = next;
};

const statusLabel = (s) =>
    ({ completed: t('dashboard.completed'), assigned: t('dashboard.inProgress'), pending: t('dashboard.pending'), unassigned: t('tasks.notStarted') }[s] ?? s);

const statusClass = (s) =>
    ({
        completed: 'bg-green-100 text-green-800 border-green-500',
        assigned: 'bg-amber-100 text-amber-800 border-amber-400',
        pending: 'bg-gray-200 text-gray-700 border-gray-400',
        unassigned: 'bg-gray-50 text-gray-500 border-indigo-400',
    }[s] ?? 'bg-gray-50 text-gray-500 border-gray-300');

const fmt = (v) => (v ? new Date(v).toLocaleDateString() : null);

// "تأكيد أنه ورقي" (2026-08-28) — a non-exclusive tag, never a mode
// switch: confirming never hides or disables "فتح النموذج" above it, the
// electronic form always stays available too.
const confirmPaper = (slot) => {
    if (!confirm(t('tasks.confirmPaperConfirmMsg'))) return;
    router.post(route('doctor.task-instances.confirm-paper', slot.instance_id), {}, { preserveScroll: true });
};

// Photos of the paper case sheet (2026-10-13), e.g. taken with this phone.
const photosSlot = ref(null);
const photosChanged = (slot, count, list) => {
    slot.attachments_count = count;
    if (list) slot.noted_attachments_count = list.filter((p) => p.note).length;
};

// "رمز QR" (2026-08-30) — mirrors the Flutter app's "مهامي" screen: every
// slot shows a code, even an unstarted one, since scanning it is how a
// senior/admin *starts* the task for this doctor (the "pending_task" QR,
// same one the standalone "رموز المهام المعلقة" page already shows). Every
// remaining unstarted slot of the same task shares the identical code —
// there's no finer-grained identity until one is actually claimed (see
// `TaskStarter`'s pending-slot pooling) — so the QR is keyed by task, not
// by slot, until `slot.instance_id` exists.
const showingQr = ref(null);
const openQr = (task, slot) => {
    showingQr.value = slot.instance_id
        ? {
              imageUrl: route('doctor.task-instances.qr', slot.instance_id),
              title: t('tasks.qrCaseTitle'),
              caption: t('tasks.qrCaseCaption'),
          }
        : {
              imageUrl: route('doctor.pending-qr.image', task.id),
              title: t('tasks.qrStartTitle'),
              caption: t('tasks.qrStartCaption'),
          };
};
</script>

<template>
    <Head :title="t('doctorLayout.requiredTasks')" />

    <DoctorLayout>
        <h2 class="text-lg font-semibold text-gray-800"><Icon name="assignment" class="ml-1" />{{ t('requiredTasks.titleWithStage', { stage: stage ?? '—' }) }}</h2>

        <!-- Tabs (2026-10-14) -->
        <div class="mt-4 flex gap-1 rounded-full bg-white p-1 shadow-sm ring-1 ring-gray-100">
            <button
                v-for="item in [
                    { key: 'all', label: t('taskRequests.allTasksTab'), count: null },
                    { key: 'waiting', label: t('taskRequests.waitingTab'), count: pendingCount },
                    { key: 'notStarted', label: t('taskRequests.notStartedTab'), count: notStartedTasks.length },
                ]"
                :key="item.key"
                type="button"
                class="flex flex-1 items-center justify-center gap-1.5 rounded-full px-2 py-2 text-xs font-medium transition sm:text-sm"
                :class="tab === item.key ? 'bg-indigo-600 text-white shadow' : 'text-gray-600 hover:bg-gray-50'"
                @click="tab = item.key"
            >
                {{ item.label }}
                <span
                    v-if="item.count"
                    class="min-w-[1.25rem] rounded-full px-1.5 text-center text-xs leading-5"
                    :class="tab === item.key ? 'bg-white/25' : item.key === 'waiting' ? 'bg-red-500 text-white' : 'bg-gray-100 text-gray-700'"
                >{{ item.count }}</span>
            </button>
        </div>

        <!-- بانتظار الموافقة: pending requests, and turned-down ones with the reason -->
        <div v-if="tab === 'waiting'" class="mt-4 overflow-hidden rounded-2xl bg-white shadow-sm ring-1 ring-gray-100">
            <div v-if="waitingRequests.length === 0" class="flex flex-col items-center gap-2 px-4 py-12 text-center text-sm text-gray-500">
                <Icon name="hourglass_empty" size="text-4xl" class="text-gray-300" />{{ t('taskRequests.noWaiting') }}
            </div>
            <div v-for="r in waitingRequests" :key="r.id" class="flex items-start gap-3 border-b border-gray-100 px-4 py-3 last:border-b-0">
                <span
                    class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full"
                    :class="r.status === 'pending' ? 'bg-amber-100 text-amber-700' : 'bg-red-100 text-red-600'"
                >
                    <Icon :name="r.status === 'pending' ? 'hourglass_top' : 'block'" />
                </span>
                <div class="min-w-0 flex-1">
                    <div class="font-medium text-gray-900">{{ r.task.title }}</div>
                    <div class="text-xs text-gray-500">
                        {{ r.task.department }} · {{ r.form_type === 'paper' ? t('taskRequests.paperForm') : t('taskRequests.electronicForm') }} · {{ fmtTime(r.created_at) }}
                    </div>
                    <div v-if="r.status === 'pending'" class="mt-1 text-xs text-amber-700">{{ t('taskRequests.waitingApproval') }}</div>
                    <div v-else class="mt-1 text-xs text-red-600">
                        {{ t('taskRequests.rejectedShort') }}<template v-if="r.review_note">: {{ r.review_note }}</template>
                    </div>
                </div>
                <button
                    v-if="r.status === 'pending'"
                    type="button"
                    class="shrink-0 rounded-full px-3 py-1 text-xs text-gray-500 ring-1 ring-gray-200 hover:text-red-600"
                    @click="cancelRequest(r)"
                >
                    {{ t('taskRequests.cancel') }}
                </button>
            </div>
        </div>

        <!-- المعلقة: tasks with a case nobody has started yet -->
        <div v-else-if="tab === 'notStarted'" class="mt-4 overflow-hidden rounded-2xl bg-white shadow-sm ring-1 ring-gray-100">
            <div v-if="notStartedTasks.length === 0" class="flex flex-col items-center gap-2 px-4 py-12 text-center text-sm text-gray-500">
                <Icon name="task_alt" size="text-4xl" class="text-gray-300" />{{ t('taskRequests.noNotStarted') }}
            </div>
            <div v-for="task in notStartedTasks" :key="task.id" class="flex items-center gap-3 border-b border-gray-100 px-4 py-3 last:border-b-0">
                <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-indigo-100 text-indigo-700">
                    <Icon name="assignment" />
                </span>
                <div class="min-w-0 flex-1">
                    <div class="font-medium text-gray-900">{{ task.title }}</div>
                    <div class="text-xs text-gray-500">
                        {{ task.department }} · {{ t('requiredTasks.remainingLine', { remaining: task.remaining, total: task.required_count }) }}
                    </div>
                </div>
                <span v-if="task.request_pending" class="shrink-0 rounded-full bg-amber-50 px-3 py-1 text-xs text-amber-700">{{ t('taskRequests.waitingApproval') }}</span>
                <button
                    v-else
                    type="button"
                    class="shrink-0 rounded-full bg-indigo-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-indigo-700"
                    @click="openRequest(task)"
                >
                    <Icon name="send" size="text-[16px]" class="ml-1" />{{ t('taskRequests.requestStart') }}
                </button>
            </div>
        </div>

        <template v-else>
        <div v-if="departments.length === 0" class="mt-4 rounded-lg bg-white p-8 text-center text-sm text-gray-500 shadow-sm">
            {{ t('requiredTasks.noTasksInStage') }}
        </div>

        <div v-else class="mt-4 space-y-3">
            <div v-for="dept in departments" :key="dept.name" class="overflow-hidden rounded-lg bg-white shadow-sm">
                <button type="button" class="flex w-full items-center justify-between p-4 text-right hover:bg-gray-50" @click="toggle(dept.name)">
                    <span class="font-semibold text-indigo-700">
                        <span class="ml-1 text-gray-400">{{ openDepartments.has(dept.name) ? '▾' : '▸' }}</span>
                        <Icon name="folder" class="ml-1" />{{ dept.name }}
                    </span>
                    <span class="flex gap-1 text-xs">
                        <span class="rounded-full bg-sky-100 px-2 py-0.5 text-sky-800">{{ t('requiredTasks.taskCount', { n: dept.tasks.length }) }}</span>
                        <span class="rounded-full bg-indigo-100 px-2 py-0.5 text-indigo-800">{{ t('dashboard.requiredLabel') }}: {{ dept.required }}</span>
                        <span class="rounded-full bg-green-100 px-2 py-0.5 text-green-800">{{ t('dashboard.completed') }}: {{ dept.completed }}</span>
                    </span>
                </button>

                <div v-if="openDepartments.has(dept.name)" class="border-t border-gray-100 bg-gray-50 p-4">
                    <div v-for="task in dept.tasks" :key="task.id" class="mb-4 last:mb-0">
                        <div class="flex flex-wrap items-center justify-between gap-2">
                            <h4 class="font-medium text-gray-900">
                                {{ task.title }}
                                <span v-if="task.case_sheet" class="mr-1 rounded-full bg-indigo-100 px-2 py-0.5 text-xs text-indigo-700">{{ task.case_sheet }}</span>
                            </h4>
                            <span class="text-xs text-amber-700">{{ t('requiredTasks.remainingLine', { remaining: task.remaining, total: task.required_count }) }}</span>
                        </div>
                        <p v-if="task.notes" class="mt-1 text-xs text-gray-500">{{ task.notes }}</p>

                        <div class="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
                            <div
                                v-for="slot in task.slots"
                                :key="slot.slot"
                                class="rounded-lg border-r-4 bg-white p-3 shadow-sm"
                                :class="statusClass(slot.status)"
                            >
                                <div class="flex items-center justify-between">
                                    <span class="flex h-7 w-7 items-center justify-center rounded-full bg-indigo-600 text-xs font-bold text-white">
                                        {{ slot.slot }}
                                    </span>
                                    <span class="rounded-full px-2 py-0.5 text-xs" :class="statusClass(slot.status)">
                                        {{ statusLabel(slot.status) }}
                                    </span>
                                </div>
                                <div class="mt-2 space-y-0.5 text-xs text-gray-500">
                                    <div v-if="slot.assigned_date">{{ t('tasks.started') }}: {{ fmt(slot.assigned_date) }}</div>
                                    <div v-if="slot.completion_date">{{ t('tasks.completedAt') }}: {{ fmt(slot.completion_date) }}</div>
                                    <div v-if="slot.grade">{{ t('doctorDashboard.grade') }}: {{ slot.grade }}</div>
                                    <div v-if="slot.notes" class="text-gray-600">{{ slot.notes }}</div>
                                </div>

                                <!-- فتح النموذج — routes this instance to its case
                                     sheet by the task's case-sheet type. For a
                                     not-yet-started slot (2026-08-28), opens an
                                     optional pre-instance draft instead — see
                                     CaseSheetController::openForTask()'s doc
                                     comment for why this never starts the task
                                     itself (still requires the normal QR-scan/
                                     screening-gated flow). -->
                                <div class="mt-2 grid grid-cols-3 gap-1">
                                    <Link
                                        :href="slot.instance_id ? route('doctor.case-sheet', slot.instance_id) : route('doctor.case-sheet.for-task', task.id)"
                                        class="block rounded bg-indigo-600 px-2 py-1 text-center text-xs font-medium text-white hover:bg-indigo-700"
                                    >
                                        <Icon name="description" class="ml-1" />{{ t('tasks.openForm') }}
                                    </Link>
                                    <!-- Photos next to the form (2026-10-15, by request);
                                         the supervisor previews them and writes notes. -->
                                    <button
                                        type="button"
                                        :disabled="!slot.instance_id"
                                        :title="slot.instance_id ? '' : t('paperPhotos.needsStart')"
                                        @click="photosSlot = { task, slot }"
                                        class="relative block rounded px-2 py-1 text-center text-xs font-medium disabled:cursor-not-allowed disabled:opacity-50"
                                        :class="slot.attachments_count ? 'bg-emerald-600 text-white hover:bg-emerald-700' : 'bg-sky-600 text-white hover:bg-sky-700'"
                                    >
                                        <Icon name="add_a_photo" class="ml-1" />{{ t('paperPhotos.uploadShort') }}<template v-if="slot.attachments_count"> ({{ slot.attachments_count }})</template>
                                        <span
                                            v-if="slot.noted_attachments_count"
                                            class="absolute -left-1 -top-2 rounded-full bg-amber-500 px-1.5 text-[10px] leading-4 text-white shadow"
                                            :title="t('paperPhotos.notesCount', { count: slot.noted_attachments_count })"
                                        >
                                            <Icon name="sticky_note_2" size="text-[11px]" />{{ slot.noted_attachments_count }}
                                        </span>
                                    </button>
                                    <button
                                        type="button"
                                        @click="openQr(task, slot)"
                                        class="block rounded bg-gray-700 px-2 py-1 text-center text-xs font-medium text-white hover:bg-gray-800"
                                    >
                                        <Icon name="qr_code_2" class="ml-1" />{{ t('tasks.qrCode') }}
                                    </button>
                                </div>

                                <!-- Request to start (2026-10-14) -->
                                <template v-if="slot.status === 'unassigned'">
                                    <div v-if="task.request_pending" class="mt-2 rounded bg-amber-50 px-2 py-1 text-center text-xs text-amber-700">
                                        <Icon name="hourglass_top" class="ml-1" />{{ t('taskRequests.waitingApproval') }}
                                    </div>
                                    <button
                                        v-else
                                        type="button"
                                        @click="openRequest(task)"
                                        class="mt-2 block w-full rounded bg-emerald-600 px-2 py-1 text-center text-xs font-medium text-white hover:bg-emerald-700"
                                    >
                                        <Icon name="send" class="ml-1" />{{ t('taskRequests.requestStart') }}
                                    </button>
                                </template>

                                <!-- "تأكيد أنه ورقي" — only meaningful once
                                     the case has a real instance (a
                                     not-yet-started slot's optional draft
                                     isn't a documented case yet). -->
                                <div v-if="slot.instance_id && slot.paper_case_sheet_confirmed_at" class="mt-2 rounded bg-amber-50 px-2 py-1 text-center text-xs text-amber-800">
                                    <Icon name="check_circle" class="ml-1" />{{ t('tasks.confirmedPaperPrefix') }} {{ fmt(slot.paper_case_sheet_confirmed_at) }}
                                </div>
                                <button
                                    v-else-if="slot.instance_id"
                                    type="button"
                                    @click="confirmPaper(slot)"
                                    class="mt-2 block w-full rounded bg-gray-200 px-2 py-1 text-center text-xs font-medium text-gray-700 hover:bg-gray-300"
                                >
                                    <Icon name="edit_note" class="ml-1" />{{ t('tasks.confirmPaper') }}
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        </template>

        <Modal :show="photosSlot !== null" @close="photosSlot = null">
            <div v-if="photosSlot" class="p-6">
                <h3 class="text-lg font-medium text-gray-900"><Icon name="photo_library" class="ml-1" />{{ t('paperPhotos.title') }}</h3>
                <p class="mt-1 text-sm text-gray-500">{{ photosSlot.task.title }}</p>
                <PaperPhotos class="mt-4" mode="doctor" :instance-id="photosSlot.slot.instance_id" @changed="(n, list) => photosChanged(photosSlot.slot, n, list)" />
                <div class="mt-6 flex justify-end">
                    <SecondaryButton @click="photosSlot = null">{{ t('common.close') }}</SecondaryButton>
                </div>
            </div>
        </Modal>

        <Modal :show="showingQr !== null" @close="showingQr = null">
            <div class="p-6">
                <h3 class="text-lg font-medium text-gray-900"><Icon name="qr_code_2" class="ml-1" />{{ showingQr?.title }}</h3>
                <div class="mt-4 flex justify-center rounded-2xl bg-gray-50 p-4">
                    <img v-if="showingQr" :src="showingQr.imageUrl" alt="QR" class="h-56 w-56" />
                </div>
                <p class="mt-3 rounded-xl border border-amber-200 bg-amber-50 p-3 text-center text-sm text-amber-800">
                    {{ showingQr?.caption }}
                </p>
                <div class="mt-6 flex justify-end">
                    <SecondaryButton @click="showingQr = null">{{ t('common.close') }}</SecondaryButton>
                </div>
            </div>
        </Modal>
        <!-- Request to start a task -->
        <Modal :show="requestTask !== null" @close="requestTask = null">
            <form v-if="requestTask" class="space-y-4 p-6" @submit.prevent="submitRequest">
                <div>
                    <h3 class="text-lg font-medium text-gray-900"><Icon name="send" class="ml-1" />{{ t('taskRequests.requestTitle') }}</h3>
                    <p class="mt-1 text-sm text-gray-500">{{ requestTask.title }}</p>
                </div>
                <div class="grid grid-cols-2 gap-2">
                    <label
                        v-for="opt in [{ v: 'electronic', icon: 'description', label: t('taskRequests.electronicForm') }, { v: 'paper', icon: 'photo_camera', label: t('taskRequests.paperForm') }]"
                        :key="opt.v"
                        class="flex cursor-pointer flex-col items-center gap-1 rounded-xl border-2 p-3 text-sm"
                        :class="requestForm.form_type === opt.v ? 'border-indigo-500 bg-indigo-50 text-indigo-700' : 'border-gray-200 text-gray-600'"
                    >
                        <input v-model="requestForm.form_type" type="radio" :value="opt.v" class="sr-only" />
                        <Icon :name="opt.icon" size="text-2xl" />{{ opt.label }}
                    </label>
                </div>
                <div v-if="requestForm.form_type === 'electronic'" class="rounded-xl bg-sky-50 p-3 text-xs text-sky-800">
                    {{ t('taskRequests.electronicHint') }}
                    <Link :href="route('doctor.case-sheet.for-task', requestTask.id)" class="mt-2 block font-medium text-sky-700 underline">
                        {{ t('tasks.openForm') }}
                    </Link>
                </div>
                <div v-else>
                    <label class="text-sm text-gray-700">{{ t('taskRequests.paperPhoto') }}</label>
                    <input
                        type="file"
                        accept="image/*"
                        capture="environment"
                        class="mt-1 block w-full text-sm text-gray-700"
                        @change="requestForm.photo = $event.target.files[0] ?? null"
                    />
                </div>
                <textarea
                    v-model="requestForm.notes"
                    rows="2"
                    class="block w-full rounded-xl border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    :placeholder="t('taskRequests.notesPlaceholder')"
                ></textarea>
                <p v-if="requestError" class="text-sm text-red-600">{{ requestError }}</p>
                <div class="flex justify-end gap-2">
                    <button type="button" class="rounded-full px-4 py-2 text-sm text-gray-600 hover:bg-gray-100" @click="requestTask = null">{{ t('common.cancel') }}</button>
                    <button
                        type="submit"
                        :disabled="requestBusy || (requestForm.form_type === 'paper' && !requestForm.photo)"
                        class="rounded-full bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 disabled:opacity-50"
                    >
                        {{ t('taskRequests.send') }}
                    </button>
                </div>
            </form>
        </Modal>
    </DoctorLayout>
</template>
