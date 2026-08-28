<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import DoctorLayout from '@/Layouts/DoctorLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import Modal from '@/Components/Modal.vue';
import PerioChart from '@/Components/PerioChart.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import QuadrantTeeth from '@/Components/QuadrantTeeth.vue';
import ToothOdontogram from '@/Components/ToothOdontogram.vue';
import EndodonticsSection from '@/Components/EndodonticsSection.vue';
import HistoryOfComplaintSection from '@/Components/HistoryOfComplaintSection.vue';
import ValueDetailsChecklist from '@/Components/ValueDetailsChecklist.vue';
import SurgicalHistorySection from '@/Components/SurgicalHistorySection.vue';
import FamilyHistorySection from '@/Components/FamilyHistorySection.vue';
import SocialHistorySection from '@/Components/SocialHistorySection.vue';
import ExtraoralIntraoralExam from '@/Components/ExtraoralIntraoralExam.vue';
import TeethSquaresGrid from '@/Components/TeethSquaresGrid.vue';
import QuadrantRepeater from '@/Components/QuadrantRepeater.vue';
import SecondaryButton from '@/Components/SecondaryButton.vue';
import TextInput from '@/Components/TextInput.vue';
import { Head, Link, useForm, usePage } from '@inertiajs/vue3';
import { computed, reactive, ref } from 'vue';
import Icon from '@/Components/Icon.vue';

/**
 * Shared renderer for the faithfully-ported case sheets. Each specialty
 * supplies its own layout from an App\Support\*Form class — this page only
 * knows how to render sections/fields and, where a sheet has them, the
 * per-tooth charts.
 */
const props = defineProps({
    resource: String, // route-name prefix, e.g. "periodontal-charts"
    title: String,
    sections: Array,
    // Only sheets with per-tooth charts pass these.
    chartGroups: { type: Array, default: () => [] },
    chartField: { type: String, default: null }, // column the chart JSON lands in
    // Only sheets with a per-stage signature/date/grade table pass this.
    stages: { type: Array, default: () => [] },
    doctors: Array,
    record: Object,
    chartData: Object,
    readonly: Boolean,
    // Option lists for fields whose choices come from other tables
    // (e.g. a surgery picker), keyed by field key.
    lookups: { type: Object, default: () => ({}) },
    // Set when the sheet was opened from a task instance (see
    // CaseSheetController) — carried through so the saved sheet stays tied
    // to that task, as in the original.
    taskInstanceId: { type: [Number, String], default: null },
    // The optional pre-instance draft's linkage (2026-08-28) — mutually
    // exclusive with taskInstanceId: set instead when opened from a
    // not-yet-started slot via CaseSheetController::openForTask(). No
    // task-instance QR to show for this case (there's no instance yet),
    // so unlike taskInstanceId this doesn't gate the "رمز QR" button below.
    taskId: { type: [Number, String], default: null },
    // Sheets whose only actor is a parent record rather than a doctor
    // (surgery satellites, treatment plans) hide the doctor selector.
    hideDoctor: Boolean,
});

const page = usePage();
const isEdit = computed(() => props.record !== null);

// Field types whose value is a whole JSON-blob text column (Oral
// Medicine's history/exam sections) — see the JSON_BLOB_FIELD_TYPES branch
// below for why these parse/stringify manually rather than relying on an
// Eloquent cast the columns don't have.
const JSON_BLOB_FIELD_TYPES = [
    'history_complaint', 'pmh_checklist', 'surgical_history',
    'family_history', 'social_history', 'extraoral_exam',
];

// Only the sheets with a print page get the button; the list comes from
// App\Support\CaseSheetPrint so the two can't drift apart.
const printable = computed(() =>
    (page.props.printableCaseSheets ?? []).includes(props.resource)
);

// "رمز QR" — port of the button every case sheet in the original shows
// alongside Print once the sheet is tied to a task instance (both gated on
// `$existing_surgery`/`$existing_chart` together — see surgery.php:1123-1131).
// The original's own onclick calls a function only ever defined on a page
// this one never loads (showTaskQrCode(), defined in required_tasks.php's
// <script> block — dead in every case sheet that calls it); rebuilt here as
// an image modal against a route that actually resolves.
const taskInstanceId = computed(() => props.record?.task_instances_id ?? props.taskInstanceId ?? null);
const showQr = ref(false);

// Case sheets are reachable by both guards, so the shell has to follow the
// principal: AuthenticatedLayout dereferences auth.user.role unguarded and
// would throw on a doctor, whose auth.user is null.
const isDoctor = computed(() => !!page.props.auth?.doctor);
const Layout = computed(() => (isDoctor.value ? DoctorLayout : AuthenticatedLayout));

// Staff open every sheet read-only (the original's "View Only Mode"); the
// server sets `readonly` for them, this only explains why.
const staffViewOnly = computed(() => props.readonly && !isDoctor.value);

/**
 * `date`-cast Eloquent columns serialise to Inertia as full ISO datetimes
 * ("2026-08-01T00:00:00.000000Z"), which <input type="date"> silently
 * refuses to bind — the field would render blank when editing an existing
 * record and then wipe the stored date on save. Trim to YYYY-MM-DD.
 */
const toDateInput = (value) => {
    if (!value) return '';
    const match = String(value).match(/^(\d{4}-\d{2}-\d{2})/);
    return match ? match[1] : value;
};

/**
 * Some sheets group several inputs into one JSON text column — the original
 * posts them as `column[subkey]` (e.g. history_of_complaint[believed_cause])
 * and stores the group as JSON. A field with a `group` is one such subkey;
 * they're collected back into their column on submit.
 */
const parseGroup = (raw) => {
    if (!raw) return {};
    if (typeof raw === 'object') return raw;
    try {
        return JSON.parse(raw) ?? {};
    } catch {
        return {};
    }
};

// --- Scalar fields ---
const initial = {
    doctor_id: props.record?.doctor_id ?? '',
    task_instances_id: props.record?.task_instances_id ?? props.taskInstanceId ?? null,
    task_id: props.record?.task_id ?? props.taskId ?? null,
};
const groupCache = {};
props.sections.forEach((section) => {
    section.fields.forEach((f) => {
        let value;
        if (f.group) {
            groupCache[f.group] ??= parseGroup(props.record?.[f.group]);
            value = groupCache[f.group][f.key] ?? '';
        } else {
            value = props.record ? props.record[f.key] : null;
        }

        if (f.type === 'file') {
            // File inputs start empty; the existing path is shown as a
            // preview from `${key}_url` instead of being re-submitted.
            value = null;
        } else if (f.type === 'dental_chart') {
            // Unlike the periodontal chart's `chart_data` (a plain text
            // column, no Eloquent cast — hence the manual JSON.stringify()
            // dance in submit()), `dental_charts.tooth_data` has a real
            // `'array'` cast (App\Models\DentalChart::casts()). Eloquent
            // already decodes it to a PHP array on the way out and
            // re-encodes whatever's assigned on the way in, so it arrives
            // here as a genuine array and posts back the same way — no
            // manual (de)serialisation, which would double-encode it.
            value = Array.isArray(value) ? value : [];
        } else if (f.type === 'endodontics') {
            // Same reasoning as 'dental_chart' just above: endodontics_data
            // also carries a real 'array' cast, so it arrives as (and posts
            // back as) a plain object, never a JSON string.
            value = value && typeof value === 'object' ? value : {};
        } else if (f.type === 'checkboxes') {
            // Multi-select checkbox groups (Orthodontics' chief_complaint,
            // cross_bite, habits …) — the original posts these as
            // `key[]`; here the group subkey already carries an array once
            // parseGroup() has decoded its column, or the '' default from a
            // missing key when a record predates the field.
            value = Array.isArray(value) ? value : [];
        } else if (f.type === 'teeth_squares_grid' || f.type === 'quadrant_repeater') {
            // Whole-subkey widgets bound directly to an object value —
            // teeth_squares (`{square_id: mark}`) and treatment_stages /
            // appliance_designs (`{index: {info, quadrants}}`). Still a
            // `group` subkey under the hood, so the existing group
            // reassembly in submit() below already re-collapses it into its
            // JSON column with no extra handling needed there.
            value = value && typeof value === 'object' ? value : {};
        } else if (JSON_BLOB_FIELD_TYPES.includes(f.type)) {
            // Oral Medicine's JSON-blob columns (history_of_complaint,
            // past_medical_history, surgical_history, family_history,
            // social_history, extraoral_intraoral_examination) — unlike
            // dental_chart/endodontics above, none of these carry an
            // Eloquent 'array' cast (see App\Models\OralMedicineChart::
            // casts()), so they arrive as a JSON *string* and need parsing
            // here, then JSON.stringify()ing back in submit().
            try {
                value = value ? JSON.parse(value) : {};
            } catch {
                value = {};
            }
        } else if (f.type === 'boolean') {
            value = !!value;
        } else if (f.type === 'date') {
            value = toDateInput(value);
        } else if (f.type === 'time') {
            // MySQL TIME columns come back as HH:MM:SS; trim to the HH:MM
            // an <input type="time"> displays.
            value = value ? String(value).slice(0, 5) : '';
        } else {
            value = value ?? '';
        }
        // Grouped subkeys are namespaced in the form so two groups can share
        // a subkey name (both `notes`, say) without colliding.
        initial[f.group ? `${f.group}__${f.key}` : f.key] = value;
    });
});
if (props.chartField) {
    initial[props.chartField] = '';
}
// Stage rows bind to stage_{key}_{signature,date,grade} columns, the
// original's own naming.
props.stages.forEach((stage) => {
    ['signature', 'date', 'grade'].forEach((part) => {
        const key = `stage_${stage.key}_${part}`;
        const value = props.record?.[key] ?? '';
        initial[key] = part === 'date' ? toDateInput(value) : value;
    });
});

const form = useForm(initial);

const hasFileField = props.sections.some((s) => s.fields.some((f) => f.type === 'file'));

// --- Per-tooth charts, kept reactive and serialised on submit in the
// original's exact JSON shape (see the specialty's App\Support\*Form). ---
const charts = reactive({});
props.chartGroups.forEach((group) => {
    charts[group.key] = {};
    group.tables.forEach((table) => {
        charts[group.key][table.key] = props.chartData?.[group.key]?.[table.key] ?? {};
    });
});

const submit = () => {
    // Re-assemble grouped subkeys into their JSON column.
    const groups = {};
    props.sections.forEach((section) => {
        section.fields.forEach((f) => {
            if (!f.group) return;
            groups[f.group] ??= {};
            groups[f.group][f.key] = form[`${f.group}__${f.key}`];
        });
    });
    Object.entries(groups).forEach(([column, value]) => {
        form[column] = JSON.stringify(value);
    });

    if (props.chartField) {
        // `teeth` is a legacy placeholder the original always emits — kept so
        // a chart written here parses identically in the original app.
        form[props.chartField] = JSON.stringify({ teeth: {}, ...charts });
    }

    // Oral Medicine's JSON-blob fields — see JSON_BLOB_FIELD_TYPES above.
    // Held as live objects while editing; serialised back to the text
    // string the column actually stores only at the point of posting.
    props.sections.forEach((section) => {
        section.fields.forEach((f) => {
            if (JSON_BLOB_FIELD_TYPES.includes(f.type)) {
                form[f.key] = JSON.stringify(form[f.key] ?? {});
            }
        });
    });

    if (isEdit.value) {
        if (hasFileField) {
            // Laravel can't parse multipart PUT bodies — file uploads on
            // update go via POST with _method spoofing (Inertia's documented
            // pattern, same as the doctor photo form).
            form.transform((data) => ({ ...data, _method: 'put' })).post(route(`${props.resource}.update`, props.record.id));
        } else {
            form.put(route(`${props.resource}.update`, props.record.id));
        }
    } else {
        form.post(route(`${props.resource}.store`));
    }
};

// The original shows its "Women Only" block off the gender field, which is
// named differently per sheet (patient_gender vs sex) — accept either.
const isFemale = computed(() => [form.patient_gender, form.sex].includes('female'));

const sectionVisible = (section) => !section.femaleOnly || isFemale.value;

const fieldVisible = (field) => {
    if (!field.showWhen) return true;
    return form[field.showWhen.field] === field.showWhen.value;
};

// Grouped subkeys live under `${group}__${key}` in the form (see the
// grouping note above); plain fields bind to their column name directly.
const formKey = (field) => (field.group ? `${field.group}__${field.key}` : field.key);

const widthClass = (field) =>
    ({ full: 'sm:col-span-4', half: 'sm:col-span-2' }[field.width] ?? 'sm:col-span-1');
</script>

<template>
    <Head :title="`${isEdit ? 'Edit' : 'New'} ${title}`" />

    <component :is="Layout">
        <template #header>
            <div class="flex items-center justify-between">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">
                    {{ readonly ? title : `${isEdit ? 'Edit' : 'New'} ${title}` }}
                </h2>
                <div class="flex items-center gap-3">
                    <!-- Printing needs a saved record, so the button appears
                         only when editing — the same condition the original
                         uses (`<?php if ($existing_chart): ?>`). -->
                    <a
                        v-if="isEdit && printable"
                        :href="route('case-sheets.print', { resource, record: record.id })"
                        target="_blank"
                        class="inline-flex items-center rounded-md bg-sky-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-sky-700"
                    >
                        <Icon name="print" class="ml-1" />طباعة
                    </a>
                    <!-- Same condition as Print in the original (both gated
                         on the existing-record check together) plus needing
                         a task instance to encode — a sheet opened outside
                         the task flow has nothing for the QR to point at. -->
                    <button
                        v-if="isEdit && taskInstanceId"
                        type="button"
                        @click="showQr = true"
                        class="inline-flex items-center rounded-md bg-cyan-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-cyan-700"
                    >
                        <Icon name="qr_code_2" class="ml-1" />رمز QR
                    </button>
                    <Link :href="route(`${resource}.index`)" class="text-sm text-indigo-600 hover:underline">Back to list</Link>
                </div>
            </div>
        </template>

        <div class="py-12">
            <div class="mx-auto max-w-6xl space-y-6 sm:px-6 lg:px-8">
                <div v-if="page.props.flash?.success" class="rounded-md bg-green-50 p-4 text-sm text-green-700">
                    {{ page.props.flash.success }}
                </div>

                <!-- "View Only Mode" — the original shows this banner to
                     admins and permissioned users, who may read a case sheet
                     but never save it. -->
                <div v-if="staffViewOnly" class="flex items-start gap-3 rounded-lg border border-amber-300 bg-amber-50 p-4">
                    <Icon name="visibility" class="mt-0.5 text-amber-600" />
                    <div class="text-sm text-amber-900">
                        <strong class="block">وضع العرض فقط</strong>
                        هذه الحالة يملكها الطبيب المسؤول عنها؛ يمكنك عرضها وطباعتها ولا يمكنك حفظ أي تعديل عليها.
                    </div>
                </div>

                <div v-if="form.task_instances_id" class="rounded-md bg-sky-50 p-3 text-sm text-sky-800">
                    <Icon name="assignment" class="ml-1" />هذا النموذج مرتبط بحالة المهمة رقم <strong>{{ form.task_instances_id }}</strong> — سيُحفظ باسمها.
                </div>

                <!-- Optional pre-instance draft (2026-08-28) — see
                     CaseSheetController::openForTask()'s doc comment: not
                     linked to a real task case yet, filling it in is
                     optional prep work. -->
                <div v-else-if="form.task_id" class="rounded-md bg-amber-50 p-3 text-sm text-amber-800">
                    <Icon name="assignment" class="ml-1" />هذه مسودة اختيارية غير مرتبطة بحالة مهمة بعد — ابدأ المهمة من "مهامي" لربطها رسمياً.
                </div>

                <form @submit.prevent="submit" class="space-y-6">
                    <!-- Doctor. Hidden from a signed-in doctor: the sheet is
                         always filed under them (the server forces doctor_id
                         from the session, as the original does), so offering
                         a picker would only suggest otherwise. -->
                    <div v-if="!hideDoctor && !isDoctor" class="rounded-lg bg-white p-6 shadow-sm">
                        <h3 class="mb-4 text-sm font-semibold uppercase tracking-wide text-gray-500">Doctor</h3>
                        <div>
                            <InputLabel for="doctor_id" value="Doctor *" />
                            <select id="doctor_id" v-model="form.doctor_id" :disabled="readonly" class="mt-1 block w-full max-w-sm rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                                <option value="" disabled>Select a doctor</option>
                                <option v-for="d in doctors" :key="d.id" :value="d.id">{{ d.name }}</option>
                            </select>
                            <InputError class="mt-2" :message="form.errors.doctor_id" />
                        </div>
                    </div>

                    <!-- Scalar sections -->
                    <div v-for="section in sections.filter(sectionVisible)" :key="section.title" class="rounded-lg bg-white p-6 shadow-sm">
                        <h3 class="text-sm font-semibold uppercase tracking-wide text-gray-500">{{ section.title }}</h3>
                        <p v-if="section.note" class="mt-1 text-xs text-gray-400">{{ section.note }}</p>

                        <div class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-4">
                            <template v-for="field in section.fields" :key="formKey(field)">
                                <div v-if="fieldVisible(field)" :class="widthClass(field)">
                                    <!-- Boolean -->
                                    <label v-if="field.type === 'boolean'" class="flex items-center gap-2 pt-6 text-sm text-gray-700">
                                        <input type="checkbox" v-model="form[formKey(field)]" :disabled="readonly" class="rounded border-gray-300" />
                                        {{ field.label }}
                                    </label>

                                    <template v-else>
                                        <InputLabel :for="formKey(field)" :value="field.label + (field.required ? ' *' : '')" />

                                        <select
                                            v-if="field.type === 'select'"
                                            :id="formKey(field)"
                                            v-model="form[formKey(field)]"
                                            :disabled="readonly"
                                            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                                        >
                                            <option value="">— Select —</option>
                                            <option v-for="o in field.options" :key="o.value" :value="o.value">{{ o.label }}</option>
                                        </select>

                                        <div v-else-if="field.type === 'radio'" class="mt-2 flex flex-wrap gap-4">
                                            <label v-for="o in field.options" :key="o.value" class="flex items-center gap-1 text-sm text-gray-700">
                                                <input type="radio" :value="o.value" v-model="form[formKey(field)]" :disabled="readonly" class="border-gray-300" />
                                                {{ o.label }}
                                            </label>
                                        </div>

                                        <div v-else-if="field.type === 'checkboxes'" class="mt-2 flex flex-wrap gap-4">
                                            <label v-for="o in field.options" :key="o.value" class="flex items-center gap-1 text-sm text-gray-700">
                                                <input
                                                    type="checkbox"
                                                    :value="o.value"
                                                    :checked="(form[formKey(field)] ?? []).includes(o.value)"
                                                    :disabled="readonly"
                                                    class="rounded border-gray-300"
                                                    @change="
                                                        form[formKey(field)] = $event.target.checked
                                                            ? [...(form[formKey(field)] ?? []), o.value]
                                                            : (form[formKey(field)] ?? []).filter((v) => v !== o.value)
                                                    "
                                                />
                                                {{ o.label }}
                                            </label>
                                        </div>

                                        <select
                                            v-else-if="field.type === 'lookup'"
                                            :id="formKey(field)"
                                            v-model="form[formKey(field)]"
                                            :disabled="readonly"
                                            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                                            :required="field.required"
                                        >
                                            <option value="">— Select —</option>
                                            <option v-for="o in (lookups[field.key] ?? [])" :key="o.id" :value="o.id">{{ o.label }}</option>
                                        </select>

                                        <div v-else-if="field.type === 'file'" class="mt-1">
                                            <img
                                                v-if="record?.[`${field.key}_url`]"
                                                :src="record[`${field.key}_url`]"
                                                class="mb-2 h-32 rounded border object-contain"
                                            />
                                            <input
                                                v-if="!readonly"
                                                :id="formKey(field)"
                                                type="file"
                                                accept="image/*"
                                                class="block w-full text-sm text-gray-700"
                                                @input="form[formKey(field)] = $event.target.files[0]"
                                            />
                                        </div>

                                        <QuadrantTeeth
                                            v-else-if="field.type === 'teeth'"
                                            v-model="form[formKey(field)]"
                                            :disabled="readonly"
                                            class="mt-1"
                                        />

                                        <ToothOdontogram
                                            v-else-if="field.type === 'dental_chart'"
                                            v-model="form[formKey(field)]"
                                            :disabled="readonly"
                                            class="mt-1"
                                        />

                                        <EndodonticsSection
                                            v-else-if="field.type === 'endodontics'"
                                            v-model="form[formKey(field)]"
                                            :disabled="readonly"
                                            class="mt-1"
                                        />

                                        <!-- Orthodontics' "Number of Teeth"
                                             marking grid and its two
                                             info+quadrant repeaters
                                             (Stages of treatment, Appliance
                                             type & Design) — see
                                             App\Support\OrthodonticsForm. -->
                                        <TeethSquaresGrid
                                            v-else-if="field.type === 'teeth_squares_grid'"
                                            v-model="form[formKey(field)]"
                                            :disabled="readonly"
                                            class="mt-1"
                                        />
                                        <QuadrantRepeater
                                            v-else-if="field.type === 'quadrant_repeater'"
                                            v-model="form[formKey(field)]"
                                            :disabled="readonly"
                                            :item-label="field.itemLabel"
                                            :info-label="field.infoLabel"
                                            class="mt-1"
                                        />

                                        <!-- Oral Medicine's dedicated JSON-blob
                                             sections — see App\Support\OralMedicineForm
                                             for why each is one field rather than
                                             split across grouped subkeys. -->
                                        <HistoryOfComplaintSection
                                            v-else-if="field.type === 'history_complaint'"
                                            v-model="form[formKey(field)]"
                                            :disabled="readonly"
                                            class="mt-1"
                                        />
                                        <ValueDetailsChecklist
                                            v-else-if="field.type === 'pmh_checklist'"
                                            v-model="form[formKey(field)]"
                                            :items="field.options"
                                            :disabled="readonly"
                                            class="mt-1"
                                        />
                                        <SurgicalHistorySection
                                            v-else-if="field.type === 'surgical_history'"
                                            v-model="form[formKey(field)]"
                                            :disabled="readonly"
                                            class="mt-1"
                                        />
                                        <FamilyHistorySection
                                            v-else-if="field.type === 'family_history'"
                                            v-model="form[formKey(field)]"
                                            :disabled="readonly"
                                            class="mt-1"
                                        />
                                        <SocialHistorySection
                                            v-else-if="field.type === 'social_history'"
                                            v-model="form[formKey(field)]"
                                            :disabled="readonly"
                                            class="mt-1"
                                        />
                                        <ExtraoralIntraoralExam
                                            v-else-if="field.type === 'extraoral_exam'"
                                            v-model="form[formKey(field)]"
                                            :disabled="readonly"
                                            class="mt-1"
                                        />

                                        <textarea
                                            v-else-if="field.type === 'textarea'"
                                            :id="formKey(field)"
                                            v-model="form[formKey(field)]"
                                            :disabled="readonly"
                                            rows="3"
                                            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                                        ></textarea>

                                        <TextInput
                                            v-else
                                            :id="formKey(field)"
                                            v-model="form[formKey(field)]"
                                            :type="['number', 'date', 'time'].includes(field.type) ? field.type : field.type === 'decimal' ? 'number' : 'text'"
                                            :step="field.type === 'decimal' ? '0.01' : undefined"
                                            :disabled="readonly"
                                            class="mt-1 block w-full"
                                            :required="field.required"
                                        />

                                        <p v-if="field.help" class="mt-1 text-xs text-gray-400">{{ field.help }}</p>
                                        <InputError class="mt-2" :message="form.errors[formKey(field)] || form.errors[field.group]" />
                                    </template>
                                </div>
                            </template>
                        </div>
                    </div>

                    <!-- Stages and evaluation -->
                    <div v-if="stages.length" class="overflow-hidden rounded-lg bg-white shadow-sm">
                        <h3 class="border-b border-gray-200 px-6 py-4 text-sm font-semibold uppercase tracking-wide text-gray-500">
                            Stages and evaluation
                        </h3>
                        <div class="overflow-x-auto">
                            <table class="min-w-full divide-y divide-gray-200">
                                <thead class="bg-gray-50">
                                    <tr>
                                        <th class="px-4 py-2 text-left text-xs font-medium uppercase text-gray-500">Stage</th>
                                        <th class="px-4 py-2 text-left text-xs font-medium uppercase text-gray-500">Signature of instructor</th>
                                        <th class="px-4 py-2 text-left text-xs font-medium uppercase text-gray-500">Date</th>
                                        <th class="px-4 py-2 text-left text-xs font-medium uppercase text-gray-500">Grade</th>
                                    </tr>
                                </thead>
                                <tbody class="divide-y divide-gray-200 bg-white">
                                    <tr v-for="stage in stages" :key="stage.key">
                                        <td class="px-4 py-2 text-sm text-gray-900">
                                            {{ stage.label }}
                                            <div v-if="stage.note" class="text-xs text-gray-400">{{ stage.note }}</div>
                                        </td>
                                        <td class="px-4 py-2">
                                            <TextInput v-model="form[`stage_${stage.key}_signature`]" type="text" :disabled="readonly" class="block w-full text-sm" />
                                        </td>
                                        <td class="px-4 py-2">
                                            <TextInput v-model="form[`stage_${stage.key}_date`]" type="date" :disabled="readonly" class="block w-full text-sm" />
                                        </td>
                                        <td class="px-4 py-2">
                                            <TextInput v-model="form[`stage_${stage.key}_grade`]" type="text" :disabled="readonly" placeholder="e.g. 9/10" class="block w-full text-sm" />
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                        </div>
                    </div>

                    <!-- Per-tooth periodontal charts -->
                    <div v-for="group in chartGroups" :key="group.key" class="rounded-lg bg-white p-6 shadow-sm">
                        <h3 class="mb-4 text-sm font-semibold uppercase tracking-wide text-gray-500">{{ group.title }}</h3>
                        <div class="space-y-4">
                            <PerioChart
                                v-for="table in group.tables"
                                :key="`${group.key}-${table.key}`"
                                v-model="charts[group.key][table.key]"
                                :type="table.type"
                                :label="table.label"
                                :disabled="readonly"
                            />
                        </div>
                    </div>

                    <div v-if="!readonly" class="flex justify-end">
                        <PrimaryButton :disabled="form.processing">{{ isEdit ? 'Update' : 'Save' }}</PrimaryButton>
                    </div>
                </form>
            </div>
        </div>

        <Modal :show="showQr" @close="showQr = false">
            <div class="p-6 text-center">
                <h3 class="text-lg font-medium text-gray-900"><Icon name="qr_code_2" class="ml-1" />رمز الحالة</h3>
                <div class="mt-4 flex items-center justify-center rounded-2xl bg-gray-50 p-6">
                    <img
                        v-if="showQr"
                        :src="route('case-sheets.instance-qr', taskInstanceId)"
                        alt="QR"
                        class="h-56 w-56"
                    />
                </div>
                <p class="mt-3 text-sm text-gray-500">امسح هذا الرمز لإعادة فتح هذه الحالة مباشرة.</p>
                <div class="mt-6 flex justify-center">
                    <SecondaryButton @click="showQr = false">إغلاق</SecondaryButton>
                </div>
            </div>
        </Modal>
    </component>
</template>
