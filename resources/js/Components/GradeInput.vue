<script setup>
/**
 * A grade field that opens GradePicker in a modal (2026-10-22, by
 * request), in place of typing into a number box.
 */
import Modal from '@/Components/Modal.vue';
import GradePicker from '@/Components/GradePicker.vue';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
    modelValue: { type: Number, default: null },
    max: { type: Number, required: true },
    title: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const open = ref(false);
const draft = ref(null);
const show = () => {
    draft.value = props.modelValue;
    open.value = true;
};
const apply = () => {
    emit('update:modelValue', draft.value);
    open.value = false;
};
</script>

<template>
    <button
        type="button"
        class="inline-flex items-center gap-1 rounded-lg bg-white px-3 py-1 text-sm font-semibold tabular-nums text-indigo-700 shadow-sm ring-1 ring-indigo-200 hover:bg-indigo-50"
        :title="t('gradePicker.tapToPick')"
        @click="show"
    >
        {{ modelValue ?? '—' }}<span class="text-xs font-normal text-gray-500">/ {{ max }}</span>
    </button>
    <Modal :show="open" max-width="md" @close="open = false">
        <div class="space-y-4 p-5">
            <div>
                <h3 class="text-lg font-semibold text-gray-900">{{ t('gradePicker.title') }}</h3>
                <p v-if="title" class="text-sm text-gray-500">{{ title }}</p>
            </div>
            <GradePicker v-model="draft" :max="max" />
            <div class="flex justify-end gap-2">
                <button type="button" class="rounded-full px-4 py-2 text-sm text-gray-600 hover:bg-gray-100" @click="open = false">{{ t('common.cancel') }}</button>
                <button type="button" class="rounded-full bg-indigo-600 px-5 py-2 text-sm font-medium text-white hover:bg-indigo-700" @click="apply">
                    {{ t('gradePicker.confirm') }}
                </button>
            </div>
        </div>
    </Modal>
</template>
