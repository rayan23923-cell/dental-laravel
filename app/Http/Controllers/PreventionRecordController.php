<?php

namespace App\Http\Controllers;

use App\Models\Doctor;
use App\Models\PreventionRecord;
use App\Models\TaskInstance;
use App\Services\CaseSheetAccess;
use App\Support\CaseSheetPatientFieldMap;
use App\Support\CaseSheetSignatures;
use App\Support\CaseSheetSupervisorFields;
use App\Support\PreventionForm;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Prevention case sheet — faithful port of
 * dental_clinics2/doctor/prevention.php (layout in
 * App\Support\PreventionForm).
 *
 * `prevention_records` has no per-field columns: the original packs the
 * whole sheet into `patient_data` and `examination_data` JSON. The form
 * posts each group flat (patient_data, questions, dmfs_indices,
 * dietary_recall) and this controller re-nests the last three inside
 * `examination_data`, matching save_prevention.php's payload shape so the
 * record stays readable by the original app.
 */
class PreventionRecordController extends Controller
{
    public function index(): Response
    {
        return Inertia::render('Specialty/Index', [
            'resource' => 'prevention-records',
            'title' => 'Prevention Records',
            'titleField' => 'id',
            'records' => CaseSheetAccess::scope(PreventionRecord::with('doctor'))->latest('id')->paginate(15),
        ]);
    }

    public function create(Request $request): Response
    {
        // See README "task_instances_id wiring" — a blank sheet opened
        // from a task instance must stay linked to it.
        $taskInstanceId = $request->integer('task_instances_id') ?: null;

        return $this->form(
            null,
            taskInstanceId: $taskInstanceId,
            taskId: $request->integer('task_id') ?: null,
            prefill: CaseSheetPatientFieldMap::prefillFor('prevention-records', $taskInstanceId ? TaskInstance::find($taskInstanceId) : null),
        );
    }

    public function edit(PreventionRecord $record): Response
    {
        return $this->form($record);
    }

    public function show(PreventionRecord $record): Response
    {
        return $this->form($record, readonly: true);
    }

    public function store(Request $request): RedirectResponse
    {
        PreventionRecord::create($this->prepare($request, isCreate: true));

        return redirect()->route('prevention-records.index')->with('success', 'Prevention record created.');
    }

    public function update(Request $request, PreventionRecord $record): RedirectResponse
    {
        $record->update($this->prepare($request, existing: $record));

        return redirect()->route('prevention-records.index')->with('success', 'Prevention record updated.');
    }

    public function destroy(PreventionRecord $record): RedirectResponse
    {
        $record->delete();

        return redirect()->route('prevention-records.index')->with('success', 'Prevention record deleted.');
    }

    private function form(?PreventionRecord $record, bool $readonly = false, ?int $taskInstanceId = null, ?int $taskId = null, array $prefill = []): Response
    {
        // Flatten the stored examination_data back out so the form's
        // grouping can seed `questions` / `dmfs_indices` / `dietary_recall`
        // the same way it seeds a real column.
        $seed = $record?->toArray() ?? [];
        $examination = json_decode($record?->examination_data ?? '{}', true) ?: [];
        foreach (PreventionForm::examinationGroups() as $group) {
            $seed[$group] = json_encode($examination[$group] ?? new \stdClass());
        }

        return Inertia::render('Specialty/SectionedForm', [
            'resource' => 'prevention-records',
            'title' => 'Prevention Record',
            'sections' => PreventionForm::sections(),
            'doctors' => Doctor::orderBy('name')->get(['id', 'name']),
            'record' => $record ? $seed : null,
            // See ProsthodonticsRecordController's matching comment for
            // why this stays a separate prop rather than merged into
            // `record`/`$seed` — `isEdit` in SectionedForm.vue is
            // `props.record !== null`. `$prefill` here is already
            // `['patient_data' => [...]]` (grouped, per
            // CaseSheetPatientFieldMap), matching what `patient_data`
            // itself would look like on a real record.
            'patientPrefill' => $prefill,
            // Staff view but never save (App\Services\CaseSheetAccess);
            // the original disables every input for them.
            'readonly' => $readonly || CaseSheetAccess::isViewOnly(),
            'supervisorEditableFields' => CaseSheetAccess::isViewOnly() ? CaseSheetSupervisorFields::fieldsFor('prevention-records') : [],
            'supervisorFields' => CaseSheetSupervisorFields::fieldsFor('prevention-records'),
            'taskInstanceId' => $record?->task_instances_id ?? $taskInstanceId,
            'taskId' => $record?->task_id ?? $taskId,
        ]);
    }

    private function prepare(Request $request, bool $isCreate = false, ?PreventionRecord $existing = null): array
    {
        $validated = $request->validate([
            'doctor_id' => ['required', 'exists:doctors,id'],
            'task_instances_id' => ['nullable', 'integer'],
            'task_id' => ['nullable', 'integer'],
            'patient_data' => ['nullable', 'string'],
            'questions' => ['nullable', 'string'],
            'dmfs_indices' => ['nullable', 'string'],
            'dietary_recall' => ['nullable', 'string'],
            // See App\Support\CaseSheetSupervisorFields.
            'supervisor_notes' => ['nullable', 'string'],
            'supervisor_signature' => ['nullable', 'string'],
        ]);

        $examination = [];
        foreach (PreventionForm::examinationGroups() as $group) {
            $examination[$group] = json_decode($validated[$group] ?? '{}', true) ?: new \stdClass();
            unset($validated[$group]);
        }

        // The original also carries hygiene_table / dentition_table inside
        // examination_data (populated from its own grid widgets, which are
        // not ported yet) — preserved as empty rather than dropped, so the
        // JSON shape still matches what the original expects to read.
        $examination['hygiene_table'] = new \stdClass();
        $examination['dentition_table'] = new \stdClass();

        $validated['examination_data'] = json_encode($examination);

        // `patient_data.date` no longer has its own form field (removed
        // 2026-08-29, by request — see App\Support\PreventionForm's
        // matching comment); set automatically instead, once, at
        // creation only, same "sometimes"-style convention as
        // Orthodontics' referral_date.
        $patientData = json_decode($validated['patient_data'] ?? '{}', true) ?: [];
        if ($isCreate) {
            $patientData['date'] = now()->toDateString();
        }
        $validated['patient_data'] = json_encode($patientData);

        $validated = CaseSheetSignatures::applyPending('prevention-records', $validated, $existing, CaseSheetSignatures::signerName($request));

        return $validated;
    }
}
