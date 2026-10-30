<script setup>
// The typeable case code under a case's QR (2026-10-30, by request), so a
// supervisor whose camera can't read the QR types it instead.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatCaseCode } from '@/caseCode';

const props = defineProps({ code: { type: String, required: true } });
const { t } = useI18n();
const shown = computed(() => formatCaseCode(props.code));
</script>

<template>
    <div class="mt-3 text-center">
        <p class="text-xs text-gray-500">{{ t('caseCode.manualLabel') }}</p>
        <p dir="ltr" class="mt-1 select-all font-mono text-2xl font-bold tracking-widest text-gray-900">{{ shown }}</p>
    </div>
</template>
