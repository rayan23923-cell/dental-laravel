<script setup>
import { Head } from '@inertiajs/vue3';
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';

const props = defineProps({
    educationTypes: Array,
    stages: Array,
});

const educationType = ref('');
const stage = ref('');
const patients = ref([]);
const appointments = ref([]);
const loading = ref(true);
let timer = null;

const visibleStages = computed(() =>
    educationType.value
        ? props.stages.filter((s) => String(s.education_type_id) === String(educationType.value))
        : props.stages,
);

const pinned = computed(() => appointments.value.filter((a) => a.pinned));

const load = async () => {
    const params = {};
    if (educationType.value) params.education_type = educationType.value;
    if (stage.value) params.stage = stage.value;

    const { data } = await window.axios.get('/api/v1/tv-board', { params });
    patients.value = data.patients;
    appointments.value = data.appointments;
    loading.value = false;
};

onMounted(() => {
    load();
    timer = setInterval(load, 20000);
});

onBeforeUnmount(() => {
    if (timer) clearInterval(timer);
});
</script>

<template>
    <Head title="Clinic Board" />

    <div class="min-h-screen bg-slate-900 p-8 text-white">
        <div class="mx-auto max-w-6xl">
            <div class="mb-8 flex items-center justify-between">
                <h1 class="text-3xl font-bold">Today's Schedule</h1>

                <div class="flex gap-3">
                    <select
                        v-model="educationType"
                        @change="stage = ''; load()"
                        class="rounded-md border-slate-600 bg-slate-800 text-white shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    >
                        <option value="">All Education Types</option>
                        <option v-for="t in educationTypes" :key="t.id" :value="t.id">{{ t.name }}</option>
                    </select>
                    <select
                        v-model="stage"
                        @change="load"
                        class="rounded-md border-slate-600 bg-slate-800 text-white shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                    >
                        <option value="">All Stages</option>
                        <option v-for="s in visibleStages" :key="s.id" :value="s.id">{{ s.name }}</option>
                    </select>
                </div>
            </div>

            <div v-if="loading" class="py-24 text-center text-slate-400">Loading…</div>

            <template v-else>
                <div v-if="pinned.length > 0" class="mb-8">
                    <h2 class="mb-3 text-lg font-semibold text-amber-400">Pinned Appointments</h2>
                    <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
                        <div
                            v-for="(a, i) in pinned"
                            :key="i"
                            class="rounded-lg border border-amber-500/40 bg-amber-500/10 p-4"
                        >
                            <div class="text-lg font-semibold">{{ a.patient_name }}</div>
                            <div class="text-sm text-amber-200">{{ a.doctor_name ?? 'Unassigned' }}</div>
                            <div class="mt-1 text-xs text-slate-400">{{ new Date(a.appointment_date).toLocaleDateString() }}</div>
                        </div>
                    </div>
                </div>

                <h2 class="mb-3 text-lg font-semibold text-slate-300">Scheduled Patients</h2>
                <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
                    <div
                        v-for="(p, i) in patients"
                        :key="i"
                        class="rounded-lg border border-slate-700 bg-slate-800 p-4"
                    >
                        <div class="text-lg font-semibold">{{ p.patient_name }}</div>
                        <div class="text-sm text-slate-400">{{ p.doctor_name ?? 'Unassigned' }}</div>
                        <div v-if="p.slots?.length" class="mt-2 space-y-1">
                            <div v-for="(slot, si) in p.slots" :key="si" class="text-xs text-indigo-300">
                                {{ slot.day }} · {{ slot.start_time }}–{{ slot.end_time }}
                            </div>
                        </div>
                    </div>
                    <div v-if="patients.length === 0" class="col-span-full py-12 text-center text-slate-500">
                        No scheduled patients.
                    </div>
                </div>
            </template>
        </div>
    </div>
</template>
