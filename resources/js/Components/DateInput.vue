<script setup>
// A date field shown with the month by name, "4 تشرين الثاني 2026"
// (2026-11-04, by request; was 15/10/2026 since 2026-10-15). The browser's
// own date text garbled in Arabic on some phones ("042026/11/"), so the
// native input sits invisibly on top and only opens the picker; the value
// stays yyyy-mm-dd.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatMonthDate } from '@/arabicDate';

const props = defineProps({
    modelValue: { type: String, default: '' },
    disabled: { type: Boolean, default: false },
    required: { type: Boolean, default: false },
    id: { type: String, default: undefined },
    // 'box' (form field) or 'pill' (inside a filter pill's label).
    variant: { type: String, default: 'box' },
});
const emit = defineEmits(['update:modelValue', 'change']);
const { locale } = useI18n();

const shown = computed(() => formatMonthDate(props.modelValue, locale.value));
const placeholder = computed(() => (locale.value === 'en' ? 'Pick a date' : 'اختر التاريخ'));

const onChange = (e) => {
    emit('update:modelValue', e.target.value);
    emit('change', e.target.value);
};
</script>

<template>
    <label
        class="relative block min-w-0 text-center text-sm"
        :class="[
            props.variant === 'pill'
                ? 'rounded-full px-3 py-1 text-gray-900 focus-within:ring-2 focus-within:ring-indigo-500'
                : 'w-full rounded-md border border-gray-300 px-3 py-2 shadow-sm focus-within:border-indigo-500 focus-within:ring-1 focus-within:ring-indigo-500',
            props.variant !== 'pill' && (props.disabled ? 'bg-gray-50 text-gray-500' : 'bg-white'),
        ]"
    >
        <span :dir="locale === 'en' ? 'ltr' : 'rtl'" class="whitespace-nowrap" :class="shown ? '' : 'text-gray-400'">{{ shown || placeholder }}</span>
        <input
            :id="props.id"
            :value="props.modelValue"
            type="date"
            :disabled="props.disabled"
            :required="props.required"
            class="absolute inset-0 h-full w-full cursor-pointer opacity-0 disabled:cursor-default"
            @change="onChange"
        />
    </label>
</template>
