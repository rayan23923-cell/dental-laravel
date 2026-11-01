<script setup>
// Today / this week / this month buttons beside the date filters
// (2026-11-01, by request). Emits the chosen range; tapping the active one
// clears it.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from '@/Components/Icon.vue';
import { PERIODS, activePeriod, periodRange } from '@/periodRange';

const props = defineProps({ from: { type: String, default: '' }, to: { type: String, default: '' } });
const emit = defineEmits(['change']);
const { t } = useI18n();

const icons = { today: 'today', week: 'date_range', month: 'calendar_month' };
const active = computed(() => activePeriod(props.from || '', props.to || ''));
const pick = (key) => emit('change', active.value === key ? { from: '', to: '' } : periodRange(key));
</script>

<template>
    <div class="flex flex-wrap items-center gap-2">
        <button
            v-for="key in PERIODS"
            :key="key"
            type="button"
            @click="pick(key)"
            class="inline-flex items-center gap-1 rounded-full px-3 py-1.5 text-sm font-medium transition"
            :class="active === key ? 'bg-indigo-600 text-white shadow-sm' : 'bg-white text-gray-700 shadow-sm ring-1 ring-gray-200 hover:bg-gray-50'"
        >
            <Icon :name="icons[key]" size="text-[18px]" />{{ t(`periods.${key}`) }}
        </button>
    </div>
</template>
