<script setup>
/**
 * A single reusable table for the small "reference data" admin screens
 * (Education Types, Stages, Departments, Permissions) — replacing four
 * near-identical hand-written `<table>` blocks with one component, each of
 * which just describes its own columns and supplies custom cell content
 * via scoped slots (`#cell-{key}`) where a plain value isn't enough
 * (badges, links, counts).
 *
 * Two renderings share the same `columns`/`rows`/slots: a normal table
 * from `sm:` up, and a stacked card list below it — these lists are tiny
 * (dozens of rows, 3-4 columns), so `overflow-x-auto` alone would just
 * make a phone user scroll sideways to read one row; a card per row reads
 * far better at that width. A column with `key: 'actions'` renders as a
 * label-less button row at the card's bottom instead of a `label: value`
 * line, matching how the desktop table's own right-aligned Actions column
 * already reads (not "an action", just controls).
 *
 * Sorting is client-side (click a `sortable` column's header) — every
 * caller here already loads its full, small dataset in one
 * `Model::...->get()` (see each controller), so there's no server-side
 * page to lose by sorting what's already on the page. `searchable` adds
 * this component's own search box for a page with no existing one
 * (Permissions); the three pages that already have a working
 * server-side/debounced search+filter bar of their own keep it — this
 * prop stays off there rather than showing two competing search boxes.
 */
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

const props = defineProps({
    // { key, label, sortable?: boolean, align?: 'left'|'right'|'center' }
    columns: { type: Array, required: true },
    rows: { type: Array, required: true },
    rowKey: { type: String, default: 'id' },
    // null defaults (rather than a hardcoded English string) so a caller
    // that doesn't override these gets the current locale's text instead
    // of English leaking into an Arabic page.
    emptyText: { type: String, default: null },
    searchable: { type: Boolean, default: false },
    searchPlaceholder: { type: String, default: null },
});

const emptyTextResolved = computed(() => props.emptyText ?? t('table.noRecords'));
const searchPlaceholderResolved = computed(() => props.searchPlaceholder ?? t('table.search'));

const getPath = (obj, path) => path.split('.').reduce((v, key) => (v == null ? v : v[key]), obj);

const search = ref('');
const searchedRows = computed(() => {
    if (!props.searchable || !search.value.trim()) return props.rows;
    const q = search.value.trim().toLowerCase();
    return props.rows.filter((row) =>
        props.columns.some((col) => {
            if (col.key === 'actions') return false;
            const value = getPath(row, col.key);
            return value != null && String(value).toLowerCase().includes(q);
        }),
    );
});

const sortKey = ref(null);
const sortDir = ref('asc');
const toggleSort = (col) => {
    if (!col.sortable) return;
    if (sortKey.value === col.key) {
        sortDir.value = sortDir.value === 'asc' ? 'desc' : 'asc';
    } else {
        sortKey.value = col.key;
        sortDir.value = 'asc';
    }
};

const sortedRows = computed(() => {
    if (!sortKey.value) return searchedRows.value;
    const dir = sortDir.value === 'asc' ? 1 : -1;
    return [...searchedRows.value].sort((a, b) => {
        const av = getPath(a, sortKey.value);
        const bv = getPath(b, sortKey.value);
        if (av == null && bv == null) return 0;
        if (av == null) return 1;
        if (bv == null) return -1;
        if (typeof av === 'number' && typeof bv === 'number') return (av - bv) * dir;
        return String(av).localeCompare(String(bv)) * dir;
    });
});

const alignClass = (align) => (align === 'right' ? 'text-right' : align === 'center' ? 'text-center' : 'text-left');
</script>

<template>
    <div>
        <div v-if="searchable" class="mb-3">
            <input
                v-model="search"
                type="text"
                :placeholder="searchPlaceholderResolved"
                class="block w-full max-w-xs rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
            />
        </div>

        <!-- Table — sm and up. -->
        <div class="hidden overflow-hidden overflow-x-auto bg-white shadow-sm sm:block sm:rounded-lg">
            <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                    <tr>
                        <th
                            v-for="col in columns"
                            :key="col.key"
                            scope="col"
                            class="px-6 py-3 text-xs font-medium uppercase tracking-wider text-gray-500"
                            :class="[alignClass(col.align), col.sortable ? 'cursor-pointer select-none hover:text-gray-700' : '']"
                            @click="toggleSort(col)"
                        >
                            <span class="inline-flex items-center gap-1">
                                {{ col.label }}
                                <span v-if="col.sortable" class="text-gray-300" :class="{ '!text-gray-700': sortKey === col.key }">
                                    {{ sortKey === col.key ? (sortDir === 'asc' ? '▲' : '▼') : '⇅' }}
                                </span>
                            </span>
                        </th>
                    </tr>
                </thead>
                <tbody class="divide-y divide-gray-200 bg-white">
                    <tr v-for="row in sortedRows" :key="row[rowKey]">
                        <td
                            v-for="col in columns"
                            :key="col.key"
                            class="whitespace-nowrap px-6 py-4 text-sm"
                            :class="[alignClass(col.align), col.key === columns[0].key ? 'font-medium text-gray-900' : 'text-gray-500']"
                        >
                            <slot :name="`cell-${col.key}`" :row="row">{{ getPath(row, col.key) ?? '—' }}</slot>
                        </td>
                    </tr>
                    <tr v-if="sortedRows.length === 0">
                        <td :colspan="columns.length" class="px-6 py-8 text-center text-sm text-gray-500">
                            {{ emptyTextResolved }}
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>

        <!-- Card list — below sm. -->
        <div class="space-y-3 sm:hidden">
            <div
                v-for="row in sortedRows"
                :key="row[rowKey]"
                class="rounded-lg bg-white p-4 shadow-sm"
            >
                <dl class="space-y-1.5">
                    <template v-for="col in columns" :key="col.key">
                        <div v-if="col.key === 'actions'" class="mt-3 flex items-center gap-4 border-t border-gray-100 pt-3">
                            <slot :name="`cell-${col.key}`" :row="row">{{ getPath(row, col.key) ?? '—' }}</slot>
                        </div>
                        <div v-else class="flex items-baseline justify-between gap-3">
                            <dt class="shrink-0 text-xs font-medium uppercase tracking-wide text-gray-400">{{ col.label }}</dt>
                            <dd class="truncate text-sm text-gray-900">
                                <slot :name="`cell-${col.key}`" :row="row">{{ getPath(row, col.key) ?? '—' }}</slot>
                            </dd>
                        </div>
                    </template>
                </dl>
            </div>
            <div v-if="sortedRows.length === 0" class="rounded-lg bg-white p-8 text-center text-sm text-gray-500 shadow-sm">
                {{ emptyTextResolved }}
            </div>
        </div>
    </div>
</template>
