<script setup>
import WorkItemsInput from '@/Components/Tasks/WorkItemsInput.vue';
import { hasWork, workItemsToForm } from '@/Components/Tasks/workItems.js';
import axios from 'axios';
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

/**
 * The linked task's points on its case sheet (2026-10-15, by request): the
 * same work, grades and checklist the task-progress dialogs record, read
 * from and saved to the task instance, so both always agree. A task graded
 * by the sheet's own steps (prosthodontics) shows what they add up to.
 */
const { t } = useI18n();
const props = defineProps({ taskInstanceId: { type: [Number, String], required: true } });

const data = ref(null);
const items = ref([]);
const saving = ref(false);
const message = ref('');
const error = ref('');

const load = async () => {
    try {
        const { data: d } = await axios.get(route('case-sheets.instance-work', props.taskInstanceId));
        data.value = d;
        items.value = d.from_sheet ? [] : workItemsToForm(d.scoring, d.work_items);
    } catch {
        data.value = null;
    }
};
onMounted(load);

const save = async () => {
    saving.value = true;
    message.value = error.value = '';
    try {
        const { data: d } = await axios.put(route('case-sheets.instance-work.update', props.taskInstanceId), { work_items: items.value });
        data.value = { ...data.value, work_items: d.work_items, points: d.points };
        message.value = t('taskScoring.saved');
    } catch (e) {
        error.value = Object.values(e.response?.data?.errors ?? {})[0]?.[0] ?? e.response?.data?.message ?? t('taskScoring.saveFailed');
    } finally {
        saving.value = false;
    }
};
</script>

<template>
    <section v-if="data && (data.from_sheet || hasWork(data.scoring))" class="rounded-lg border border-indigo-200 bg-white p-4 shadow-sm">
        <div class="mb-3 flex flex-wrap items-center justify-between gap-2">
            <div>
                <h3 class="font-semibold text-gray-900">{{ t('taskScoring.sheetPanel') }}</h3>
                <p class="text-xs text-gray-500">{{ data.title }}</p>
            </div>
            <span v-if="data.points !== null && data.points !== undefined" class="rounded-full bg-indigo-600 px-3 py-1 text-sm text-white">{{ t('taskScoring.pointsValue', { n: data.points }) }}</span>
        </div>

        <template v-if="data.from_sheet">
            <p class="mb-2 text-xs text-gray-500">{{ t('taskScoring.fromSheet') }}</p>
            <div v-for="(w, i) in data.work_items" :key="i" class="flex items-center justify-between border-b border-gray-100 py-1 text-sm">
                <span class="text-gray-700">{{ w.option }}</span>
                <span class="text-gray-900">{{ w.points }}</span>
            </div>
        </template>

        <template v-else>
            <fieldset :disabled="!data.can_edit">
                <WorkItemsInput v-model="items" :scoring="data.scoring" />
            </fieldset>
            <p v-if="!data.can_edit" class="mt-2 text-xs text-gray-500">{{ t('taskScoring.supervisorOnly') }}</p>
            <div v-else class="mt-3 flex items-center gap-3">
                <button type="button" class="rounded-md bg-indigo-600 px-4 py-2 text-sm text-white hover:bg-indigo-700 disabled:opacity-50" :disabled="saving" @click="save">
                    {{ t('taskScoring.savePoints') }}
                </button>
                <span v-if="message" class="text-sm text-emerald-700">{{ message }}</span>
                <span v-if="error" class="text-sm text-red-600">{{ error }}</span>
            </div>
        </template>
    </section>
</template>
