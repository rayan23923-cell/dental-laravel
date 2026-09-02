<?php

namespace App\Http\Controllers;

use App\Models\Doctor;
use App\Models\OrthodonticsRecord;
use App\Models\TaskInstance;
use App\Services\CaseSheetAccess;
use App\Support\CaseSheetPatientFieldMap;
use App\Support\CaseSheetSignatures;
use App\Support\CaseSheetSupervisorFields;
use App\Support\OrthodonticsForm;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Orthodontics case sheet — faithful port of
 * dental_clinics2/doctor/orthodontics.php (layout in
 * App\Support\OrthodonticsForm). The patient/referral half maps to real
 * columns; the clinical half lives in the `examination_data` JSON blob,
 * keyed exactly as save_orthodontics.php writes it.
 */
class OrthodonticsRecordController extends Controller
{
    public function index(): Response
    {
        return Inertia::render('Specialty/Index', [
            'resource' => 'orthodontics-records',
            'title' => 'Orthodontics Records',
            'titleField' => 'patient_name',
            'records' => CaseSheetAccess::scope(OrthodonticsRecord::with('doctor'))->latest('id')->paginate(15),
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
            prefill: CaseSheetPatientFieldMap::prefillFor('orthodontics-records', $taskInstanceId ? TaskInstance::find($taskInstanceId) : null),
        );
    }

    public function edit(OrthodonticsRecord $record): Response
    {
        return $this->form($record);
    }

    public function show(OrthodonticsRecord $record): Response
    {
        return $this->form($record, readonly: true);
    }

    public function store(Request $request): RedirectResponse
    {
        OrthodonticsRecord::create($this->prepare($request, isCreate: true));

        return redirect()->route('orthodontics-records.index')->with('success', 'Orthodontics record created.');
    }

    public function update(Request $request, OrthodonticsRecord $record): RedirectResponse
    {
        $record->update($this->prepare($request, existing: $record));

        return redirect()->route('orthodontics-records.index')->with('success', 'Orthodontics record updated.');
    }

    public function destroy(OrthodonticsRecord $record): RedirectResponse
    {
        $record->delete();

        return redirect()->route('orthodontics-records.index')->with('success', 'Orthodontics record deleted.');
    }

    private function form(?OrthodonticsRecord $record, bool $readonly = false, ?int $taskInstanceId = null, ?int $taskId = null, array $prefill = []): Response
    {
        return Inertia::render('Specialty/SectionedForm', [
            'resource' => 'orthodontics-records',
            'title' => 'Orthodontics Record',
            'sections' => OrthodonticsForm::sections(),
            'doctors' => Doctor::orderBy('name')->get(['id', 'name']),
            'record' => $record,
            // See ProsthodonticsRecordController's matching comment for
            // why this stays a separate prop rather than merged into `record`.
            'patientPrefill' => $prefill,
            // Staff view but never save (App\Services\CaseSheetAccess);
            // the original disables every input for them.
            'readonly' => $readonly || CaseSheetAccess::isViewOnly(),
            'supervisorEditableFields' => CaseSheetAccess::isViewOnly() ? CaseSheetSupervisorFields::fieldsFor('orthodontics-records') : [],
            'supervisorFields' => CaseSheetSupervisorFields::fieldsFor('orthodontics-records'),
            'taskInstanceId' => $record?->task_instances_id ?? $taskInstanceId,
            'taskId' => $record?->task_id ?? $taskId,
        ]);
    }

    private function prepare(Request $request, bool $isCreate = false, ?OrthodonticsRecord $existing = null): array
    {
        $rules = [
            'doctor_id' => ['required', 'exists:doctors,id'],
            'task_instances_id' => ['nullable', 'integer'],
            'task_id' => ['nullable', 'integer'],
            'patient_name' => ['required', 'string', 'max:255'],
            'patient_age' => ['nullable', 'integer', 'min:0', 'max:150'],
            'patient_sex' => ['nullable', 'in:male,female'],
            'examination_data' => ['nullable', 'string'],
            // See App\Support\CaseSheetSupervisorFields — this table has
            // neither a `notes` field nor a senior-signature-equivalent
            // one of its own, so these two are new, dedicated to the
            // supervisor-preview feature.
            'supervisor_notes' => ['nullable', 'string'],
            'supervisor_signature' => ['nullable', 'string'],
        ];

        foreach (OrthodonticsForm::sections() as $section) {
            foreach ($section['fields'] as $field) {
                if (! empty($field['group']) || isset($rules[$field['key']])) {
                    continue;
                }
                $rules[$field['key']] = match ($field['type']) {
                    'boolean' => ['nullable', 'boolean'],
                    'number' => ['nullable', 'integer'],
                    'date' => ['nullable', 'date'],
                    default => ['nullable', 'string'],
                };
            }
        }

        $validated = $request->validate($rules);
        $validated = CaseSheetSignatures::applyPending('orthodontics-records', $validated, $existing, CaseSheetSignatures::signerName($request));

        // `student_name`/`referral_date` no longer have their own form
        // fields (removed 2026-08-29, by request — see
        // App\Support\OrthodonticsForm's matching comment) so they never
        // reach $rules/$validated above; set automatically instead, once,
        // at creation only (an update never overwrites them, same
        // "sometimes"-style convention as every other auto-defaulted
        // field this session).
        if ($isCreate) {
            $validated['student_name'] = Doctor::find($validated['doctor_id'])?->name;
            $validated['referral_date'] = now()->toDateString();
        }

        // The original always carries these three sub-structures inside
        // examination_data (teeth_squares, treatment_stages,
        // appliance_designs — all built as real widgets, see
        // App\Support\OrthodonticsForm). Default them defensively rather
        // than dropping the keys if a payload is ever missing one, so the
        // blob keeps the shape the original reads.
        $examination = json_decode($validated['examination_data'] ?? '{}', true) ?: [];
        $examination['treatment_stages'] ??= [];
        $examination['appliance_designs'] ??= [];
        $examination['teeth_squares'] ??= new \stdClass();
        $validated['examination_data'] = json_encode($examination);

        return $validated;
    }
}
