<script setup>
/**
 * "الطلبات" tab of task progress (2026-10-14, by request): doctors'
 * requests to start a task. Staff preview the electronic case sheet or the
 * paper form's photo, then start the task or turn the request down.
 * Split into "بانتظار الموافقة" and "تم بدؤها" (plus the turned-down ones).
 * See App\Http\Controllers\TaskStartRequestController.
 */
import axios from 'axios';
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from '@/Components/Icon.vue';
import Modal from '@/Components/Modal.vue';
import ChatListCard from '@/Components/ChatList/ChatListCard.vue';
import ChatSearch from '@/Components/ChatList/ChatSearch.vue';

const { t } = useI18n();
const emit = defineEmits(['count']);

const data = ref({ pending: [], approved: [], rejected: [] });
const loading = ref(true);
const tab = ref('pending');
const search = ref('');
const busyId = ref(null);
const error = ref('');
const photo = ref(null);
const review = ref(null); // { request, action: 'approve' | 'reject' }
const note = ref('');

const load = async () => {
    loading.value = true;
    try {
        const res = await axios.get(route('task-progress.requests.index'));
        data.value = res.data;
        emit('count', res.data.pending_count);
    } finally {
        loading.value = false;
    }
};
onMounted(load);

const tabs = computed(() => [
    { key: 'pending', label: t('taskRequests.pendingTab'), count: data.value.pending.length },
    { key: 'approved', label: t('taskRequests.startedTab'), count: data.value.approved.length },
    { key: 'rejected', label: t('taskRequests.rejectedTab'), count: data.value.rejected.length },
]);

const rows = computed(() => {
    const q = search.value.trim().toLowerCase();
    return (data.value[tab.value] ?? []).filter((r) =>
        !q || [r.doctor.name, r.task.title, r.task.department, r.doctor.stage].some((v) => (v ?? '').toLowerCase().includes(q)),
    );
});

const fmt = (v) => (v ? new Date(v).toLocaleString(t('sessions.dateLocale'), { dateStyle: 'medium', timeStyle: 'short' }) : '');

const openReview = (request, action) => {
    review.value = { request, action };
    note.value = '';
    error.value = '';
};

const submitReview = async () => {
    const { request, action } = review.value;
    busyId.value = request.id;
    error.value = '';
    try {
        await axios.post(route(`task-progress.requests.${action}`, request.id), { note: note.value || null });
        review.value = null;
        await load();
    } catch (e) {
        error.value = e.response?.data?.message ?? t('taskRequests.actionFailed');
    } finally {
        busyId.value = null;
    }
};

defineExpose({ load });
</script>

<template>
    <div class="space-y-4">
        <!-- Sub-tabs -->
        <div class="flex gap-2 overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            <button
                v-for="item in tabs"
                :key="item.key"
                type="button"
                class="flex shrink-0 items-center gap-1.5 rounded-full px-4 py-1.5 text-sm font-medium transition"
                :class="tab === item.key ? 'bg-indigo-600 text-white' : 'bg-white text-gray-600 ring-1 ring-gray-200 hover:bg-gray-50'"
                @click="tab = item.key"
            >
                {{ item.label }}
                <span
                    class="min-w-[1.25rem] rounded-full px-1.5 text-xs"
                    :class="tab === item.key ? 'bg-white/25' : item.key === 'pending' && item.count ? 'bg-red-500 text-white' : 'bg-gray-100'"
                >{{ item.count }}</span>
            </button>
        </div>

        <ChatSearch v-model="search" :placeholder="t('taskRequests.searchPlaceholder')" />

        <ChatListCard :empty="!loading && rows.length === 0" :empty-text="t('taskRequests.empty')" empty-icon="assignment_turned_in">
            <div v-if="loading" class="p-8 text-center text-sm text-gray-500">{{ t('common.loading') }}</div>
            <div v-for="r in rows" v-else :key="r.id" class="border-b border-gray-100 px-4 py-3 last:border-b-0">
                <div class="flex items-start gap-3">
                    <img v-if="r.doctor.photo_url" :src="r.doctor.photo_url" class="h-11 w-11 shrink-0 rounded-full object-cover" />
                    <span v-else class="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-indigo-100 font-semibold text-indigo-700">
                        {{ (r.doctor.name ?? '?').trim().charAt(0) }}
                    </span>
                    <div class="min-w-0 flex-1">
                        <div class="flex flex-wrap items-center gap-x-2">
                            <span class="font-semibold text-gray-900">{{ r.doctor.name }}</span>
                            <span class="text-xs text-gray-400">{{ fmt(r.created_at) }}</span>
                        </div>
                        <div class="text-sm text-gray-700">{{ r.task.title }}</div>
                        <div class="mt-1 flex flex-wrap gap-1.5 text-xs">
                            <span v-if="r.task.department" class="rounded-full bg-gray-100 px-2 py-0.5 text-gray-600">{{ r.task.department }}</span>
                            <span v-if="r.doctor.stage" class="rounded-full bg-gray-100 px-2 py-0.5 text-gray-600">{{ r.doctor.stage }}</span>
                            <span
                                class="rounded-full px-2 py-0.5"
                                :class="r.form_type === 'paper' ? 'bg-amber-50 text-amber-700' : 'bg-sky-50 text-sky-700'"
                            >
                                {{ r.form_type === 'paper' ? t('taskRequests.paperForm') : t('taskRequests.electronicForm') }}
                            </span>
                        </div>
                        <p v-if="r.notes" class="mt-1 text-xs text-gray-500">{{ t('taskRequests.doctorNote') }}: {{ r.notes }}</p>
                        <p v-if="r.status !== 'pending'" class="mt-1 text-xs" :class="r.status === 'approved' ? 'text-green-700' : 'text-red-600'">
                            {{ r.status === 'approved' ? t('taskRequests.startedBy', { name: r.reviewer ?? '—' }) : t('taskRequests.rejectedBy', { name: r.reviewer ?? '—' }) }}
                            · {{ fmt(r.reviewed_at) }}<template v-if="r.review_note"> · {{ r.review_note }}</template>
                        </p>

                        <div class="mt-2 flex flex-wrap gap-2">
                            <button
                                v-if="r.photo_url"
                                type="button"
                                class="inline-flex items-center gap-1 rounded-full bg-amber-50 px-3 py-1 text-xs font-medium text-amber-700 hover:bg-amber-100"
                                @click="photo = r.photo_url"
                            >
                                <Icon name="image" size="text-[16px]" />{{ t('taskRequests.viewPhoto') }}
                            </button>
                            <a
                                v-if="r.case_sheet_url"
                                :href="r.case_sheet_url"
                                target="_blank"
                                class="inline-flex items-center gap-1 rounded-full bg-sky-50 px-3 py-1 text-xs font-medium text-sky-700 hover:bg-sky-100"
                            >
                                <Icon name="description" size="text-[16px]" />{{ t('taskRequests.viewForm') }}
                            </a>
                            <span v-else-if="r.form_type === 'electronic'" class="rounded-full bg-gray-50 px-3 py-1 text-xs text-gray-400">
                                {{ t('taskRequests.formNotFilled') }}
                            </span>
                            <template v-if="r.status === 'pending'">
                                <button
                                    type="button"
                                    :disabled="busyId === r.id"
                                    class="inline-flex items-center gap-1 rounded-full bg-green-600 px-3 py-1 text-xs font-medium text-white hover:bg-green-700 disabled:opacity-50"
                                    @click="openReview(r, 'approve')"
                                >
                                    <Icon name="play_arrow" size="text-[16px]" />{{ t('taskRequests.start') }}
                                </button>
                                <button
                                    type="button"
                                    :disabled="busyId === r.id"
                                    class="inline-flex items-center gap-1 rounded-full bg-white px-3 py-1 text-xs font-medium text-red-600 ring-1 ring-red-200 hover:bg-red-50 disabled:opacity-50"
                                    @click="openReview(r, 'reject')"
                                >
                                    <Icon name="close" size="text-[16px]" />{{ t('taskRequests.reject') }}
                                </button>
                            </template>
                        </div>
                    </div>
                </div>
            </div>
        </ChatListCard>

        <!-- Paper form photo -->
        <Modal :show="photo !== null" @close="photo = null" max-width="2xl">
            <div class="p-3">
                <img :src="photo" class="max-h-[80vh] w-full rounded-lg object-contain" />
                <div class="mt-2 flex justify-between">
                    <a :href="photo" target="_blank" class="text-sm text-indigo-600 hover:underline">{{ t('taskRequests.openFull') }}</a>
                    <button type="button" class="text-sm text-gray-500" @click="photo = null">{{ t('common.close') }}</button>
                </div>
            </div>
        </Modal>

        <!-- Start / turn down -->
        <Modal :show="review !== null" @close="review = null">
            <form v-if="review" class="space-y-3 p-6" @submit.prevent="submitReview">
                <h3 class="text-lg font-medium text-gray-900">
                    {{ review.action === 'approve' ? t('taskRequests.startTitle') : t('taskRequests.rejectTitle') }}
                </h3>
                <p class="text-sm text-gray-600">{{ review.request.doctor.name }} · {{ review.request.task.title }}</p>
                <textarea
                    v-model="note"
                    rows="3"
                    class="block w-full rounded-xl border-gray-300 text-sm shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    :placeholder="review.action === 'approve' ? t('taskRequests.startNotePlaceholder') : t('taskRequests.rejectNotePlaceholder')"
                ></textarea>
                <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
                <div class="flex justify-end gap-2">
                    <button type="button" class="rounded-full px-4 py-2 text-sm text-gray-600 hover:bg-gray-100" @click="review = null">{{ t('common.cancel') }}</button>
                    <button
                        type="submit"
                        :disabled="busyId !== null"
                        class="rounded-full px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
                        :class="review.action === 'approve' ? 'bg-green-600 hover:bg-green-700' : 'bg-red-600 hover:bg-red-700'"
                    >
                        {{ review.action === 'approve' ? t('taskRequests.start') : t('taskRequests.reject') }}
                    </button>
                </div>
            </form>
        </Modal>
    </div>
</template>
