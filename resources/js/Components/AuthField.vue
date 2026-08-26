<script setup>
/**
 * One labelled field for the auth screens.
 *
 * Separate from the app-wide TextInput/InputLabel pair on purpose: those are
 * used by ~50 light-styled pages, so repainting them with the theme tokens
 * would turn their text near-white on white cards under a dark theme. The
 * auth screens are the part of the app that lives entirely inside the theme,
 * so they get their own field.
 */
import Icon from '@/Components/Icon.vue';
import InputError from '@/Components/InputError.vue';
import { computed, ref } from 'vue';

const props = defineProps({
    modelValue: { type: [String, Number], default: '' },
    label: { type: String, required: true },
    type: { type: String, default: 'text' },
    icon: { type: String, default: null },
    error: { type: String, default: null },
    placeholder: { type: String, default: '' },
    autocomplete: { type: String, default: null },
    autofocus: Boolean,
    required: Boolean,
    id: { type: String, required: true },
});

defineEmits(['update:modelValue']);

const revealed = ref(false);
const isPassword = computed(() => props.type === 'password');
const resolvedType = computed(() => (isPassword.value && revealed.value ? 'text' : props.type));
</script>

<template>
    <div>
        <label :for="id" class="mb-1.5 block text-xs font-medium uppercase tracking-wide text-muted">
            {{ label }}
        </label>
        <div class="relative">
            <Icon v-if="icon" :name="icon" class="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-muted" />
            <input
                :id="id"
                :type="resolvedType"
                :value="modelValue"
                :placeholder="placeholder"
                :autocomplete="autocomplete"
                :autofocus="autofocus"
                :required="required"
                dir="ltr"
                class="w-full rounded-xl border border-hairline bg-surface-2 px-4 py-3 text-content placeholder:text-muted/70 focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/40"
                :class="[icon ? 'pr-11' : '', isPassword ? 'pl-11' : '']"
                @input="$emit('update:modelValue', $event.target.value)"
            />
            <button
                v-if="isPassword"
                type="button"
                @click="revealed = !revealed"
                class="absolute left-2 top-1/2 -translate-y-1/2 rounded-lg p-1.5 text-muted transition hover:bg-surface hover:text-content"
                :aria-label="revealed ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور'"
            >
                <Icon :name="revealed ? 'visibility_off' : 'visibility'" />
            </button>
        </div>
        <InputError class="mt-2" :message="error" />
    </div>
</template>
