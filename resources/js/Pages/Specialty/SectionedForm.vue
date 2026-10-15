<script setup>
import AuthenticatedLayout from '@/Layouts/AuthenticatedLayout.vue';
import DoctorLayout from '@/Layouts/DoctorLayout.vue';
import InputError from '@/Components/InputError.vue';
import InputLabel from '@/Components/InputLabel.vue';
import Modal from '@/Components/Modal.vue';
import AdvancedPerioChartSessions from '@/Components/AdvancedPerioChartSessions.vue';
import PerioChart from '@/Components/PerioChart.vue';
import PlaqueChart from '@/Components/PlaqueChart.vue';
import PrimaryButton from '@/Components/PrimaryButton.vue';
import QuadrantTeeth from '@/Components/QuadrantTeeth.vue';
import ProsthodonticsDentalArch from '@/Components/ProsthodonticsDentalArch.vue';
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
import QrScanner from '@/Components/QrScanner.vue';
import { Head, Link, useForm, usePage } from '@inertiajs/vue3';
import { computed, nextTick, reactive, ref } from 'vue';
import Icon from '@/Components/Icon.vue';
import TaskWorkPanel from '@/Components/Tasks/TaskWorkPanel.vue';
import axios from 'axios';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

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
    // "Plaque Index" per visit — a separate feature from chartGroups
    // despite sharing the same chart_data column, under its own
    // `dentalCharts` key (see App\Support\PlaqueChart). periodontal-charts
    // only, same gate as chartGroups.
    plaqueVisits: { type: Array, default: () => [] },
    // "Advanced Periodontal Chart" (2026-08-31, sessions added 2026-09-03) —
    // a completely separate 32-tooth grid mechanism from chartGroups/
    // plaqueVisits above (this resource has neither), sharing the same
    // chart_data column under its own `advancedChart` key, which now holds
    // a doctor-managed list of sessions rather than one snapshot. See
    // AdvancedPerioChartSessions.vue's own doc comment. advanced-periodontal-charts only.
    advancedPerioChart: Boolean,
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
    // The sheet's doctor, or the task case's doctor it was opened from
    // (2026-10-15): shown as a name instead of the picker.
    linkedDoctor: { type: Object, default: null },
    // Operative only: the task is a root filling, so Endodontics starts on.
    rootFilling: Boolean,
    // The optional pre-instance draft's linkage (2026-08-28) — mutually
    // exclusive with taskInstanceId: set instead when opened from a
    // not-yet-started slot via CaseSheetController::openForTask(). No
    // task-instance QR to show for this case (there's no instance yet),
    // so unlike taskInstanceId this doesn't gate the "رمز QR" button below.
    taskId: { type: [Number, String], default: null },
    // Sheets whose only actor is a parent record rather than a doctor
    // (surgery satellites, treatment plans) hide the doctor selector.
    hideDoctor: Boolean,
    // The resource's own supervisor-editable fields (App\Support\
    // CaseSheetSupervisorFields), populated server-side only for a staff
    // viewer — a doctor's own edit always gets []. These stay editable
    // even though `readonly` is true for staff, per the supervisor-preview
    // feature (2026-08-28): staff may view but never save, except these.
    supervisorEditableFields: { type: Array, default: () => [] },
    // The same registry's full, unconditional list (2026-08-29) — sent
    // regardless of viewer, since it's static layout metadata rather than
    // a permission grant. Lets fieldDisabled() below tell "supervisor-only
    // field the doctor may only *view*" apart from "ordinary field the
    // doctor may edit", which supervisorEditableFields alone can't: for a
    // doctor it's always [], so without this a supervisor field would be
    // indistinguishable from any other and render fully editable on the
    // doctor's own page — the actual bug reported (2026-08-29): "معلومات
    // المشرف... يجب ازالتهما من صفحة الطبيب" (the supervisor's info must
    // not be editable from the doctor's page), then clarified to keep it
    // visible, just locked: "فقط اظهر ملاحظات ومعلومات المشرف لكن لايمكن
    // تعديلها من الطبيب" (show it, just make it non-editable for a doctor).
    supervisorFields: { type: Array, default: () => [] },
    // Patient fields to seed a brand-new sheet with (2026-09-02, by
    // request — "عند بدء مهمة من قبل المشرف ومسح كيوار المريض يتم ملئ
    // معلومات المريض الى الكيس شيت بصورة تلقائية"), resolved server-side
    // from whichever patient TaskStarter::start() already tied this task
    // instance to (see App\Support\CaseSheetPatientFieldMap) — a doctor
    // opening a brand-new sheet for an already-started task no longer has
    // to re-scan the same patient's registration QR by hand the way the
    // standalone "مسح رمز المريض" flow below still does when there's no
    // task instance to resolve a patient from at all. Deliberately a
    // *separate* prop from `record`, never merged into it — `isEdit`
    // above is `props.record !== null`, so a non-null `record` on a
    // create would misreport edit mode (wrong title/button text, and a
    // PUT to `/undefined` since a plain prefill object has no `id`).
    patientPrefill: { type: Object, default: () => ({}) },
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

// "مسح رمز المريض" (2026-08-28) — autofills the patient-identity fields
// reception already captured at registration, read from the same ticket QR
// used elsewhere (payments, task start). Per-resource because each of the
// 8 sheets names these columns differently — confirmed against every
// model's own $fillable rather than assumed uniform. `prevention-records`
// packs its patient fields into the `patient_data` JSON group instead of
// real columns, so its map targets the grouped `patient_data__*` form keys
// (see formKey()/the group-reassembly in submit()) — same flat `form[key]`
// target either way, no special-casing needed at the point of use below.
const PATIENT_FIELD_MAP = {
    'dental-charts': { name: 'patient_id', phone: 'patient_phone', age: 'patient_age', sex: 'patient_sex', address: 'patient_address', occupation: 'patient_occupation' },
    'oral-medicine-charts': { name: 'patient_id', phone: 'patient_phone', age: 'patient_age', sex: 'patient_sex', address: 'patient_address', occupation: 'patient_occupation' },
    surgeries: { name: 'patient_name', phone: 'patient_phone', age: 'patient_age', sex: 'patient_gender', address: 'patient_address', occupation: 'patient_occupation' },
    'periodontal-charts': { name: 'patient_name', phone: 'patient_phone', age: 'patient_age', sex: 'patient_gender', address: 'patient_address', occupation: 'patient_occupation' },
    'prosthodontics-records': { name: 'patient_name', phone: 'telephone', age: 'age', sex: 'sex', address: 'address', occupation: 'occupation' },
    'complete-denture-records': { name: 'patient_name', phone: 'telephone', age: 'age', sex: 'sex', address: 'address', occupation: 'occupation' },
    'orthodontics-records': { name: 'patient_name', phone: 'patient_phone', age: 'patient_age', sex: 'patient_sex', address: 'patient_address' },
    'prevention-records': { name: 'patient_data__child_name', phone: 'patient_data__phone_number', age: 'patient_data__patient_age', sex: 'patient_data__patient_gender' },
    // Only `sex` is a plain single-field target here — this resource
    // splits the patient's name into `patient_first_name`/
    // `patient_last_name` rather than one `name` column, so filling it
    // from a scan needs an actual split, handled as a special case in
    // onPatientDecoded() below (mirrors
    // App\Support\CaseSheetPatientFieldMap::advancedPeriodontalPrefill()
    // on the server) rather than by this map's flat shape. Still needs an
    // entry here so `patientFieldMap` keeps gating the scan button on for
    // this resource too.
    'advanced-periodontal-charts': { sex: 'patient_gender' },
};
const patientFieldMap = computed(() => PATIENT_FIELD_MAP[props.resource] ?? null);

const showPatientScan = ref(false);
const patientScannerRef = ref(null);
const patientScanError = ref('');

const openPatientScan = async () => {
    patientScanError.value = '';
    showPatientScan.value = true;
    await nextTick();
    patientScannerRef.value?.start();
};

// Only fills blank fields — never overwrites something the doctor already
// typed, per the user's own framing of this feature.
const onPatientDecoded = async (text) => {
    patientScanError.value = '';
    try {
        // Doctor-only route (2026-08-28) — this button only ever shows for
        // a doctor (readonly is always true for staff), and the staff-only
        // `patient-registrations.scan` route rejects any Doctor principal
        // outright (`EnsureUserHasPermission`'s `permission:patients,view`
        // gate). Also enforces `PatientScreeningGate` server-side — a
        // patient not yet screened clear can't be autofilled here either.
        const { data } = await axios.post(route('patient-registrations.scan-for-case-sheet'), { payload: text });
        const r = data.data.registration;
        const map = patientFieldMap.value;
        if (map) {
            // Advanced Periodontal Chart splits the patient's name into two
            // fields — see PATIENT_FIELD_MAP's own doc comment on this
            // resource's entry for why it's handled here instead of via
            // `map.name`.
            if (props.resource === 'advanced-periodontal-charts' && r.name) {
                const parts = String(r.name).trim().split(/\s+/);
                if (!form.patient_first_name) form.patient_first_name = parts[0];
                if (!form.patient_last_name && parts.length > 1) form.patient_last_name = parts.slice(1).join(' ');
            } else if (map.name && !form[map.name] && r.name) {
                form[map.name] = r.name;
            }
            if (map.phone && !form[map.phone] && r.phone) form[map.phone] = r.phone;
            if (map.age && !form[map.age] && r.age != null) form[map.age] = r.age;
            if (map.sex && !form[map.sex] && r.sex) form[map.sex] = r.sex;
            if (map.address && !form[map.address] && r.address) form[map.address] = r.address;
            if (map.occupation && !form[map.occupation] && r.occupation) form[map.occupation] = r.occupation;
        }
        patientScannerRef.value?.stop();
        showPatientScan.value = false;
    } catch (e) {
        patientScanError.value = e?.response?.data?.message ?? t('specialtyForms.scanReadFailedMsg');
    }
};

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
    doctor_id: props.record?.doctor_id ?? props.linkedDoctor?.id ?? '',
    task_instances_id: props.record?.task_instances_id ?? props.taskInstanceId ?? null,
    task_id: props.record?.task_id ?? props.taskId ?? null,
};
const groupCache = {};
props.sections.forEach((section) => {
    section.fields.forEach((f) => {
        let value;
        if (f.group) {
            // `patientPrefill` only ever carries a *whole* group object
            // (e.g. `{patient_data: {child_name: '...'}}`), never
            // individual scalar fields — matching the grouped shape a
            // real record's own column would already have.
            groupCache[f.group] ??= parseGroup(props.record?.[f.group] ?? props.patientPrefill?.[f.group]);
            value = groupCache[f.group][f.key] ?? '';
        } else {
            value = props.record ? props.record[f.key] : (props.patientPrefill?.[f.key] ?? null);
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
// "Plaque Index" — a sibling top-level key in the same `charts` object
// (see PlaqueChart.vue's own doc comment), so it rides along with the
// `{ teeth: {}, ...charts }` spread at submit below with no extra
// handling needed.
if (props.plaqueVisits.length) {
    charts.dentalCharts = props.chartData?.dentalCharts ?? {};
}
if (props.advancedPerioChart) {
    charts.advancedChart = props.chartData?.advancedChart ?? { teeth: {} };
}

// FDI tooth numbers marked extracted in the Plaque Index chart — fed into
// every PerioChart (BOP/PPD/CAL) table below so a tooth pulled at any
// visit shows the same "missing" greyed-out column everywhere, port of
// the original's own syncDentalToPerio()/syncPerioFromDental(). All 5
// visits are kept in sync with each other already (PlaqueChart.vue's own
// toggleExtractedAllVisits()), so reading across every visit here is
// belt-and-braces rather than strictly necessary.
const extractedTeeth = computed(() => {
    const ids = new Set();
    for (const visit of props.plaqueVisits) {
        const teeth = charts.dentalCharts?.[visit.key]?.teeth ?? {};
        for (const [id, data] of Object.entries(teeth)) {
            if (data?.extracted === true) ids.add(Number(id));
        }
    }
    return [...ids];
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

/**
 * `"UR8, UL1"` → `[18, 21]` — same canonical-code rule as
 * `CaseSheetPrintRenderer::normalizeToothCode()`/`quadrantCodeToFdi()`
 * (see `ProsthodonticsDentalArch.vue`'s own doc comment). `QuadrantTeeth.vue`
 * only ever emits this canonical shape, so the legacy `U1-U16`/`L1-L16`
 * branch that PHP method also handles (surgery sheets' own older format)
 * doesn't apply here.
 */
const quadrantCodesToFdi = (raw) => {
    const prefixes = { UR: 1, UL: 2, LL: 3, LR: 4 };
    return (raw ?? '')
        .split(',')
        .map((c) => c.trim().toUpperCase())
        .map((c) => c.match(/^(UR|UL|LR|LL)([1-8])$/))
        .filter(Boolean)
        .map((m) => prefixes[m[1]] * 10 + Number(m[2]));
};

// Live preview of the same anatomical dental-arch illustration the
// printed document shows — prosthodontics-records only, matching
// Api\CaseSheetPrintController's own `dental_arch` scoping.
const missingFdi = computed(() => quadrantCodesToFdi(form.missing_teeth));
const cariousFdi = computed(() => quadrantCodesToFdi(form.caries_teeth));

const widthClass = (field) =>
    ({ full: 'sm:col-span-4', half: 'sm:col-span-2' }[field.width] ?? 'sm:col-span-1');

// Two independent reasons a field can be locked (2026-08-29, reworked):
//
// 1. It's a *supervisor-only* field (`props.supervisorFields`, the
//    registry's full list, sent to every viewer) that this viewer isn't
//    the one supervisor role allowed to edit — locked for a doctor
//    unconditionally, not just under `readonly`, since a doctor's own
//    edit page has `readonly === false`. Previously these rendered as
//    plain, fully-editable inputs on a doctor's own page (the field.key
//    just never matched anything since supervisorEditableFields is always
//    [] for a doctor) — reported as "معلومات المشرف... يجب ازالتهما من
//    صفحة الطبيب", then clarified to keep them visible, just locked
//    rather than removed: "فقط اظهر... لكن لايمكن تعديلها من الطبيب".
// 2. Every *other* field stays locked under the existing `readonly` rule
//    (a staff supervisor-preview may look but not touch anything outside
//    their own 2-or-so fields).
//
// Grouped subkeys use `field.key` (not formKey()) since that's the bare
// name the registry lists (e.g. Prevention's `senior_name`, packed inside
// the `patient_data` column) — a plain array-cast column's numeric list
// indices never collide with a real supervisor-field name, so this is
// safe for every field shape the registry can describe.
const fieldDisabled = (field) =>
    props.supervisorFields.includes(field.key)
        ? !props.supervisorEditableFields.includes(field.key)
        : props.readonly && !props.supervisorEditableFields.includes(field.key);

// "يجب ان يملئ حقل الدرجة والتاريخ حتى يوقع" (2026-08-30) — a stage can't
// be signed off until its own Grade and Date are filled in, so the
// signature never attests to a still-blank evaluation. Enforced again,
// robustly, server-side in App\Support\CaseSheetSignatures — this is only
// the client-side convenience (disables the button before a wasted trip).
const stageReadyToSign = (stageKey) => !!form[`stage_${stageKey}_date`] && !!form[`stage_${stageKey}_grade`];

// Same idea for the "Stages and evaluation" table, whose rows aren't part
// of `sections` and so aren't covered by fieldDisabled() above — mirrors
// its two-reason logic identically rather than assuming every stage
// column is always supervisor-gated (true for both tables that have this
// table today, but this stays correct even if that ever weren't so).
const stageFieldDisabled = (stageKey, part) => {
    const key = `stage_${stageKey}_${part}`;
    return props.supervisorFields.includes(key)
        ? !props.supervisorEditableFields.includes(key)
        : props.readonly && !props.supervisorEditableFields.includes(key);
};

// The Update/Save button was unconditionally hidden under `readonly` —
// correct while staff were fully locked out, but a supervisor with actual
// editable fields (notes/signature/stage sign-off) needs it to save those.
const canSubmit = computed(() => !props.readonly || props.supervisorEditableFields.length > 0);
</script>

<template>
    <Head :title="isEdit ? t('specialtyForms.editPrefixTemplate', { title }) : t('specialtyForms.newPrefixTemplate', { title })" />

    <component :is="Layout">
        <template #header>
            <div class="flex items-center justify-between">
                <h2 class="text-xl font-semibold leading-tight text-gray-800">
                    {{ readonly ? title : (isEdit ? t('specialtyForms.editPrefixTemplate', { title }) : t('specialtyForms.newPrefixTemplate', { title })) }}
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
                        <Icon name="print" class="ml-1" />{{ t('specialtyForms.printAction') }}
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
                        <Icon name="qr_code_2" class="ml-1" />{{ t('specialtyForms.qrCodeAction') }}
                    </button>
                    <!-- Autofill patient-identity fields from the same
                         registration ticket QR used for payment/screening,
                         instead of retyping what reception already
                         captured. -->
                    <button
                        v-if="!readonly && patientFieldMap"
                        type="button"
                        @click="openPatientScan"
                        class="inline-flex items-center rounded-md bg-emerald-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-emerald-700"
                    >
                        <Icon name="qr_code_scanner" class="ml-1" />{{ t('specialtyForms.scanPatientAction') }}
                    </button>
                    <Link :href="page.props.caseSheetBackUrl ?? route(`${resource}.index`)" class="text-sm text-indigo-600 hover:underline">{{ t('specialtyForms.backAction') }}</Link>
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
                        <strong class="block">{{ t('specialtyForms.viewOnlyModeHeading') }}</strong>
                        {{ t('specialtyForms.viewOnlyModeDesc') }}
                    </div>
                </div>

                <div v-if="form.task_instances_id" class="rounded-md bg-sky-50 p-3 text-sm text-sky-800">
                    <Icon name="assignment" class="ml-1" />{{ t('specialtyForms.linkedTaskPrefix') }} <strong>{{ form.task_instances_id }}</strong> {{ t('specialtyForms.linkedTaskSuffix') }}
                </div>

                <!-- The linked task's points, the same ones task progress records (2026-10-15). -->
                <TaskWorkPanel v-if="taskInstanceId" :task-instance-id="taskInstanceId" />

                <!-- Optional pre-instance draft (2026-08-28) — see
                     CaseSheetController::openForTask()'s doc comment: not
                     linked to a real task case yet, filling it in is
                     optional prep work. -->
                <div v-else-if="form.task_id" class="rounded-md bg-amber-50 p-3 text-sm text-amber-800">
                    <Icon name="assignment" class="ml-1" />{{ t('specialtyForms.draftNote') }}
                </div>

                <form @submit.prevent="submit" class="space-y-6">
                    <!-- Doctor. Hidden from a signed-in doctor: the sheet is
                         always filed under them (the server forces doctor_id
                         from the session, as the original does), so offering
                         a picker would only suggest otherwise. -->
                    <div v-if="!hideDoctor && !isDoctor" class="rounded-lg bg-white p-6 shadow-sm">
                        <h3 class="mb-4 text-sm font-semibold uppercase tracking-wide text-gray-500">{{ t('specialtyForms.doctorLabel') }}</h3>
                        <!-- Opened from a task case, or an existing sheet: its doctor is
                             fixed, so show the name; only a new unlinked sheet picks one. -->
                        <div v-if="linkedDoctor && (record?.id || taskInstanceId)" class="flex items-center gap-2 text-base font-medium text-gray-900">
                            <Icon name="person" class="text-indigo-600" />{{ linkedDoctor.name }}
                        </div>
                        <div v-else>
                            <InputLabel for="doctor_id" :value="`${t('specialtyForms.doctorLabel')} *`" />
                            <select id="doctor_id" v-model="form.doctor_id" :disabled="readonly" class="mt-1 block w-full max-w-sm rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" required>
                                <option value="" disabled>{{ t('specialtyForms.selectDoctorPlaceholder') }}</option>
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
                                        <input type="checkbox" v-model="form[formKey(field)]" :disabled="fieldDisabled(field)" class="rounded border-gray-300" />
                                        {{ field.label }}
                                    </label>

                                    <template v-else>
                                        <InputLabel :for="formKey(field)" :value="field.label + (field.required ? ' *' : '')" />

                                        <select
                                            v-if="field.type === 'select'"
                                            :id="formKey(field)"
                                            v-model="form[formKey(field)]"
                                            :disabled="fieldDisabled(field)"
                                            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                                        >
                                            <option value="">{{ t('specialtyForms.selectOptionPlaceholder') }}</option>
                                            <option v-for="o in field.options" :key="o.value" :value="o.value">{{ o.label }}</option>
                                        </select>

                                        <div v-else-if="field.type === 'radio'" class="mt-2 flex flex-wrap gap-4">
                                            <label v-for="o in field.options" :key="o.value" class="flex items-center gap-1 text-sm text-gray-700">
                                                <input type="radio" :value="o.value" v-model="form[formKey(field)]" :disabled="fieldDisabled(field)" class="border-gray-300" />
                                                {{ o.label }}
                                            </label>
                                        </div>

                                        <div v-else-if="field.type === 'checkboxes'" class="mt-2 flex flex-wrap gap-4">
                                            <label v-for="o in field.options" :key="o.value" class="flex items-center gap-1 text-sm text-gray-700">
                                                <input
                                                    type="checkbox"
                                                    :value="o.value"
                                                    :checked="(form[formKey(field)] ?? []).includes(o.value)"
                                                    :disabled="fieldDisabled(field)"
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
                                            :disabled="fieldDisabled(field)"
                                            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                                            :required="field.required"
                                        >
                                            <option value="">{{ t('specialtyForms.selectOptionPlaceholder') }}</option>
                                            <option v-for="o in (lookups[field.key] ?? [])" :key="o.id" :value="o.id">{{ o.label }}</option>
                                        </select>

                                        <div v-else-if="field.type === 'file'" class="mt-1">
                                            <img
                                                v-if="record?.[`${field.key}_url`]"
                                                :src="record[`${field.key}_url`]"
                                                class="mb-2 h-32 rounded border object-contain"
                                            />
                                            <input
                                                v-if="!fieldDisabled(field)"
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
                                            :disabled="fieldDisabled(field)"
                                            class="mt-1"
                                        />

                                        <ToothOdontogram
                                            v-else-if="field.type === 'dental_chart'"
                                            v-model="form[formKey(field)]"
                                            :disabled="fieldDisabled(field)"
                                            class="mt-1"
                                        />

                                        <EndodonticsSection
                                            v-else-if="field.type === 'endodontics'"
                                            v-model="form[formKey(field)]"
                                            :disabled="fieldDisabled(field)"
                                            :root-filling="rootFilling"
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
                                            :disabled="fieldDisabled(field)"
                                            class="mt-1"
                                        />
                                        <QuadrantRepeater
                                            v-else-if="field.type === 'quadrant_repeater'"
                                            v-model="form[formKey(field)]"
                                            :disabled="fieldDisabled(field)"
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
                                            :disabled="fieldDisabled(field)"
                                            class="mt-1"
                                        />
                                        <ValueDetailsChecklist
                                            v-else-if="field.type === 'pmh_checklist'"
                                            v-model="form[formKey(field)]"
                                            :items="field.options"
                                            :disabled="fieldDisabled(field)"
                                            class="mt-1"
                                        />
                                        <SurgicalHistorySection
                                            v-else-if="field.type === 'surgical_history'"
                                            v-model="form[formKey(field)]"
                                            :disabled="fieldDisabled(field)"
                                            class="mt-1"
                                        />
                                        <FamilyHistorySection
                                            v-else-if="field.type === 'family_history'"
                                            v-model="form[formKey(field)]"
                                            :disabled="fieldDisabled(field)"
                                            class="mt-1"
                                        />
                                        <SocialHistorySection
                                            v-else-if="field.type === 'social_history'"
                                            v-model="form[formKey(field)]"
                                            :disabled="fieldDisabled(field)"
                                            class="mt-1"
                                        />
                                        <ExtraoralIntraoralExam
                                            v-else-if="field.type === 'extraoral_exam'"
                                            v-model="form[formKey(field)]"
                                            :disabled="fieldDisabled(field)"
                                            class="mt-1"
                                        />

                                        <!-- Auto-captured signature (2026-08-30,
                                             by request) — replaces a free-typed
                                             name: once signed, App\Support\
                                             CaseSheetSignatures immutably stamps
                                             the real signer + timestamp
                                             server-side, so this only ever shows
                                             a "توقيع" button (unsigned) or the
                                             stamped read-only text (signed). -->
                                        <div v-else-if="field.type === 'signature'" class="mt-1">
                                            <p v-if="form[formKey(field)] && form[formKey(field)] !== '__SIGN__'" class="rounded-md border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-800">
                                                <Icon name="verified" class="ml-1" />{{ form[formKey(field)] }}
                                            </p>
                                            <div v-else-if="form[formKey(field)] === '__SIGN__'" class="flex items-center justify-between gap-2 rounded-md border border-indigo-200 bg-indigo-50 px-3 py-2 text-sm text-indigo-800">
                                                {{ t('specialtyForms.willBeRecordedNote') }}
                                                <button type="button" @click="form[formKey(field)] = ''" class="text-xs text-indigo-600 underline">{{ t('specialtyForms.cancelAction') }}</button>
                                            </div>
                                            <button
                                                v-else
                                                type="button"
                                                :disabled="fieldDisabled(field)"
                                                @click="form[formKey(field)] = '__SIGN__'"
                                                class="inline-flex items-center rounded-md bg-indigo-600 px-3 py-1.5 text-sm text-white hover:bg-indigo-700 disabled:cursor-not-allowed disabled:opacity-50"
                                            >
                                                <Icon name="draw" class="ml-1" />{{ t('specialtyForms.signButton') }}
                                            </button>
                                        </div>

                                        <textarea
                                            v-else-if="field.type === 'textarea'"
                                            :id="formKey(field)"
                                            v-model="form[formKey(field)]"
                                            :disabled="fieldDisabled(field)"
                                            rows="3"
                                            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500"
                                        ></textarea>

                                        <TextInput
                                            v-else
                                            :id="formKey(field)"
                                            v-model="form[formKey(field)]"
                                            :type="['number', 'date', 'time'].includes(field.type) ? field.type : field.type === 'decimal' ? 'number' : 'text'"
                                            :step="field.type === 'decimal' ? '0.01' : undefined"
                                            :disabled="fieldDisabled(field)"
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

                    <!-- Live dental-arch preview — see ProsthodonticsDentalArch.vue's
                         own doc comment for why this only ever appeared in
                         the printed document until now. -->
                    <div v-if="resource === 'prosthodontics-records'" class="rounded-lg bg-white p-6 shadow-sm">
                        <h3 class="text-sm font-semibold uppercase tracking-wide text-gray-500">{{ t('specialtyForms.dentalArchHeading') }}</h3>
                        <ProsthodonticsDentalArch :missing-fdi="missingFdi" :carious-fdi="cariousFdi" />
                    </div>

                    <!-- Stages and evaluation -->
                    <div v-if="stages.length" class="overflow-hidden rounded-lg bg-white shadow-sm">
                        <h3 class="border-b border-gray-200 px-6 py-4 text-sm font-semibold uppercase tracking-wide text-gray-500">
                            {{ t('specialtyForms.stagesEvaluationHeading') }}
                        </h3>
                        <div class="overflow-x-auto">
                            <table class="min-w-full divide-y divide-gray-200">
                                <thead class="bg-gray-50">
                                    <tr>
                                        <th class="px-4 py-2 text-left text-xs font-medium uppercase text-gray-500">{{ t('specialtyForms.stageCol') }}</th>
                                        <th class="px-4 py-2 text-left text-xs font-medium uppercase text-gray-500">{{ t('specialtyForms.signatureOfInstructorCol') }}</th>
                                        <th class="px-4 py-2 text-left text-xs font-medium uppercase text-gray-500">{{ t('specialtyForms.dateCol') }}</th>
                                        <th class="px-4 py-2 text-left text-xs font-medium uppercase text-gray-500">{{ t('specialtyForms.gradeCol') }}</th>
                                    </tr>
                                </thead>
                                <tbody class="divide-y divide-gray-200 bg-white">
                                    <tr v-for="stage in stages" :key="stage.key">
                                        <td class="px-4 py-2 text-sm text-gray-900">
                                            {{ stage.label }}
                                            <div v-if="stage.note" class="text-xs text-gray-400">{{ stage.note }}</div>
                                        </td>
                                        <td class="px-4 py-2">
                                            <!-- Same auto-captured signature as the scalar
                                                 'signature' field type above, just keyed
                                                 by the stage table's own naming. -->
                                            <p v-if="form[`stage_${stage.key}_signature`] && form[`stage_${stage.key}_signature`] !== '__SIGN__'" class="rounded-md border border-emerald-200 bg-emerald-50 px-2 py-1 text-xs text-emerald-800">
                                                {{ form[`stage_${stage.key}_signature`] }}
                                            </p>
                                            <div v-else-if="form[`stage_${stage.key}_signature`] === '__SIGN__'" class="flex items-center justify-between gap-1 rounded-md border border-indigo-200 bg-indigo-50 px-2 py-1 text-xs text-indigo-800">
                                                {{ t('specialtyForms.stageSignPendingNote') }}
                                                <button type="button" @click="form[`stage_${stage.key}_signature`] = ''" class="text-indigo-600 underline">{{ t('specialtyForms.cancelAction') }}</button>
                                            </div>
                                            <button
                                                v-else
                                                type="button"
                                                :disabled="stageFieldDisabled(stage.key, 'signature') || !stageReadyToSign(stage.key)"
                                                :title="!stageReadyToSign(stage.key) ? t('specialtyForms.completeGradeDateFirst') : ''"
                                                @click="form[`stage_${stage.key}_signature`] = '__SIGN__'"
                                                class="w-full rounded-md bg-indigo-600 px-2 py-1 text-xs text-white hover:bg-indigo-700 disabled:cursor-not-allowed disabled:opacity-50"
                                            >
                                                {{ t('specialtyForms.signButton') }}
                                            </button>
                                            <p v-if="!stageFieldDisabled(stage.key, 'signature') && !stageReadyToSign(stage.key)" class="mt-1 text-xs text-gray-400">
                                                {{ t('specialtyForms.completeGradeDateFirst') }}
                                            </p>
                                        </td>
                                        <td class="px-4 py-2">
                                            <TextInput v-model="form[`stage_${stage.key}_date`]" type="date" :disabled="stageFieldDisabled(stage.key, 'date')" class="block w-full text-sm" />
                                        </td>
                                        <td class="px-4 py-2">
                                            <TextInput v-model="form[`stage_${stage.key}_grade`]" type="text" :disabled="stageFieldDisabled(stage.key, 'grade')" placeholder="e.g. 9/10" class="block w-full text-sm" />
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
                                :extracted-teeth="extractedTeeth"
                            />
                        </div>
                    </div>

                    <!-- "Plaque Index" per visit — separate feature from
                         the chartGroups tables above, see PlaqueChart.vue's
                         own doc comment. -->
                    <div v-if="plaqueVisits.length" class="rounded-lg bg-white p-6 shadow-sm">
                        <h3 class="mb-4 text-sm font-semibold uppercase tracking-wide text-gray-500">{{ t('specialtyForms.plaqueIndexHeading') }}</h3>
                        <PlaqueChart v-model="charts.dentalCharts" :visits="plaqueVisits" :disabled="readonly" />
                    </div>

                    <!-- "Advanced Periodontal Chart" — multiple sessions/visits, each its
                         own 32-tooth grid. See AdvancedPerioChartSessions.vue's own doc
                         comment; AdvancedPerioChart.vue itself (the grid) is untouched. -->
                    <div v-if="advancedPerioChart" class="rounded-lg bg-white p-6 shadow-sm">
                        <h3 class="mb-4 text-sm font-semibold uppercase tracking-wide text-gray-500">{{ t('specialtyForms.periodontalChartHeading') }}</h3>
                        <AdvancedPerioChartSessions v-model="charts.advancedChart" :disabled="readonly" />
                    </div>

                    <div v-if="canSubmit" class="flex justify-end">
                        <PrimaryButton :disabled="form.processing">{{ isEdit ? t('specialtyForms.updateButton') : t('specialtyForms.saveButton') }}</PrimaryButton>
                    </div>
                </form>
            </div>
        </div>

        <Modal :show="showQr" @close="showQr = false">
            <div class="p-6 text-center">
                <h3 class="text-lg font-medium text-gray-900"><Icon name="qr_code_2" class="ml-1" />{{ t('specialtyForms.caseCodeModalHeading') }}</h3>
                <div class="mt-4 flex items-center justify-center rounded-2xl bg-gray-50 p-6">
                    <img
                        v-if="showQr"
                        :src="route('case-sheets.instance-qr', taskInstanceId)"
                        alt="QR"
                        class="h-56 w-56"
                    />
                </div>
                <p class="mt-3 text-sm text-gray-500">{{ t('specialtyForms.scanToReopenNote') }}</p>
                <div class="mt-6 flex justify-center">
                    <SecondaryButton @click="showQr = false">{{ t('specialtyForms.closeAction') }}</SecondaryButton>
                </div>
            </div>
        </Modal>

        <Modal :show="showPatientScan" @close="showPatientScan = false">
            <div class="p-6">
                <h3 class="text-lg font-medium text-gray-900"><Icon name="qr_code_scanner" class="ml-1" />{{ t('specialtyForms.scanPatientAction') }}</h3>
                <p class="mt-1 text-sm text-gray-500">{{ t('specialtyForms.scanPatientModalDesc') }}</p>
                <div class="mt-4">
                    <QrScanner v-if="showPatientScan" ref="patientScannerRef" @decoded="onPatientDecoded" />
                </div>
                <div v-if="patientScanError" class="mt-3 rounded-md bg-red-50 p-2 text-sm text-red-700">{{ patientScanError }}</div>
                <div class="mt-6 flex justify-center">
                    <SecondaryButton @click="showPatientScan = false">{{ t('specialtyForms.closeAction') }}</SecondaryButton>
                </div>
            </div>
        </Modal>
    </component>
</template>
