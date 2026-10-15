<script setup>
/**
 * One chat-list row, as on the permissions page: a gradient avatar (an
 * icon, or the first letter of `title`), the name, a line of chips in the
 * `meta` slot, then icon actions in `actions`. With `href` the avatar and
 * text are a link (the actions stay outside it, so they never navigate),
 * and a row without actions ends in a chevron.
 */
import Icon from '@/Components/Icon.vue';
import { Link } from '@inertiajs/vue3';
import { computed, ref } from 'vue';
import { tone as toneOf } from './tones';

const props = defineProps({
    title: { type: String, required: true },
    subtitle: { type: String, default: '' },
    icon: { type: String, default: null },
    tone: { type: String, default: 'indigo' },
    href: { type: String, default: null },
    selected: { type: Boolean, default: false },
});

// On phones the actions fold behind a "⋮" and open as a strip under the
// row, so a row with several actions doesn't squeeze its name and chips.
const actionsOpen = ref(false);

const initial = computed(() => (props.title || '?').trim().charAt(0).toUpperCase());
</script>

<template>
    <div
        class="flex flex-wrap items-center gap-3 border-b border-gray-100 px-4 py-3 transition last:border-b-0 sm:flex-nowrap"
        :class="[href ? 'hover:bg-gray-50' : '', selected ? 'bg-indigo-50/60' : '']"
    >
        <slot name="leading" />
        <component :is="href ? Link : 'div'" :href="href ?? undefined" class="flex min-w-0 flex-1 items-center gap-3">
            <div
                class="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-gradient-to-br text-lg font-semibold text-white"
                :class="toneOf(tone).avatar"
            >
                <Icon v-if="icon" :name="icon" size="text-[24px]" />
                <template v-else>{{ initial }}</template>
            </div>
            <div class="min-w-0 flex-1">
                <div class="truncate text-[15px] font-semibold text-gray-900">{{ title }}</div>
                <div v-if="subtitle" class="truncate text-xs text-gray-500">{{ subtitle }}</div>
                <div v-if="$slots.meta" class="mt-1 flex flex-wrap items-center gap-1.5">
                    <slot name="meta" />
                </div>
            </div>
            <Icon v-if="href && !$slots.actions" name="chevron_left" class="shrink-0 text-gray-300 ltr:rotate-180" />
        </component>
        <div v-if="$slots.actions" class="hidden shrink-0 items-center sm:flex">
            <slot name="actions" />
        </div>
        <button
            v-if="$slots.actions"
            type="button"
            class="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-gray-500 hover:bg-gray-100 sm:hidden"
            :aria-expanded="actionsOpen"
            @click.stop="actionsOpen = !actionsOpen"
        >
            <Icon :name="actionsOpen ? 'close' : 'more_vert'" />
        </button>
        <div v-if="$slots.actions && actionsOpen" class="flex w-full items-center justify-end gap-1 sm:hidden" @click.stop>
            <slot name="actions" />
        </div>
    </div>
</template>
