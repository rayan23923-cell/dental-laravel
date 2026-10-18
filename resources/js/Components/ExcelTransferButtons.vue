<script setup>
/**
 * Excel export and import icons (2026-10-18, by request), for moving a
 * list between the hosted and the offline system.
 */
import Icon from '@/Components/Icon.vue';
import { router } from '@inertiajs/vue3';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
    exportUrl: { type: String, required: true },
    importUrl: { type: String, default: null },
});

const { t } = useI18n();
const input = ref(null);
const busy = ref(false);
const error = ref('');

const upload = (event) => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    busy.value = true;
    error.value = '';
    router.post(props.importUrl, { file }, {
        forceFormData: true,
        preserveScroll: true,
        onError: (errors) => { error.value = Object.values(errors).join(' '); },
        onFinish: () => { busy.value = false; },
    });
};
</script>

<template>
    <div class="flex items-center gap-2">
        <a :href="exportUrl" :title="t('common.exportExcel')" class="inline-flex h-10 w-10 items-center justify-center rounded-full bg-emerald-50 text-emerald-700 hover:bg-emerald-100">
            <Icon name="download" :label="t('common.exportExcel')" />
        </a>
        <template v-if="importUrl">
            <button type="button" :title="t('common.importExcel')" :disabled="busy" @click="input.click()" class="inline-flex h-10 w-10 items-center justify-center rounded-full bg-gray-100 text-gray-700 hover:bg-gray-200 disabled:opacity-50">
                <Icon :name="busy ? 'hourglass_top' : 'upload_file'" :label="t('common.importExcel')" />
            </button>
            <input ref="input" type="file" accept=".xlsx,.xls,.csv" class="hidden" @change="upload" />
        </template>
        <span v-if="error" class="text-xs text-red-600">{{ error }}</span>
    </div>
</template>
