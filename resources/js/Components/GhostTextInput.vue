<script setup>
/**
 * A text input with a faint inline completion (2026-11-04, by request:
 * "ظل خافت" while registering a returning patient). The rest of
 * `suggestion` is drawn after what was typed; Tab or End takes it, any
 * other key just keeps typing, so it never gets in the way at a busy desk.
 */
import { computed, onMounted, ref, useAttrs } from 'vue';

defineOptions({ inheritAttrs: false });

const model = defineModel({ type: String, required: true });
const props = defineProps({
    suggestion: { type: String, default: '' },
    dir: { type: String, default: 'auto' },
});
const emit = defineEmits(['accept']);

// The class goes on the wrapper (spacing), everything else on the input.
const attrs = useAttrs();
const inputAttrs = computed(() => {
    const { class: _class, ...rest } = attrs;
    return rest;
});

const input = ref(null);
onMounted(() => {
    if (input.value.hasAttribute('autofocus')) input.value.focus();
});
defineExpose({ focus: () => input.value.focus() });

const norm = (v) => String(v ?? '').toLocaleLowerCase();
const rest = computed(() => {
    const typed = model.value ?? '';
    const s = props.suggestion ?? '';
    if (!typed || s.length <= typed.length || !norm(s).startsWith(norm(typed))) return '';
    return s.slice(typed.length);
});

const onKeydown = (e) => {
    if (!rest.value) return;
    if ((e.key === 'Tab' && !e.shiftKey) || e.key === 'End') {
        const el = input.value;
        // Only from the end of what was typed.
        if (el.selectionStart !== el.value.length) return;
        e.preventDefault();
        emit('accept');
    }
};
</script>

<template>
    <div class="relative" :class="attrs.class">
        <input
            ref="input"
            v-model="model"
            :dir="dir"
            v-bind="inputAttrs"
            class="block w-full rounded-xl border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
            @keydown="onKeydown"
        />
        <div
            v-if="rest"
            aria-hidden="true"
            :dir="dir"
            class="pointer-events-none absolute inset-0 z-10 overflow-hidden whitespace-pre border border-transparent px-3 py-2 text-base leading-6"
        ><span class="invisible">{{ model }}</span><span class="text-gray-400">{{ rest }}</span></div>
    </div>
</template>
