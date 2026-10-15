<?php

namespace App\Http\Controllers;

use App\Models\CompleteDentureRecord;
use App\Models\Doctor;
use App\Models\TaskInstance;
use App\Services\CaseSheetAccess;
use App\Support\CaseSheetDoctor;
use App\Support\CaseSheetPatientFieldMap;
use App\Support\CaseSheetReturn;
use App\Support\CaseSheetSignatures;
use App\Support\CaseSheetSupervisorFields;
use App\Support\CompleteDentureForm;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Complete denture case sheet — faithful port of
 * dental_clinics2/doctor/complete_denture.php (layout in
 * App\Support\CompleteDentureForm), replacing the generic column-driven
 * form. Includes the original's quadrant tooth pickers (UR8/UL1-style
 * codes) and its "Stages and evaluation" signature/date/grade table.
 */
class CompleteDentureRecordController extends Controller
{
    public function index(): Response
    {
        return Inertia::render('Specialty/Index', [
            'resource' => 'complete-denture-records',
            'title' => 'Complete Denture Records',
            'titleField' => 'patient_name',
            'records' => CaseSheetAccess::scope(CompleteDentureRecord::with('doctor'))->latest('id')->paginate(15),
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
            prefill: CaseSheetPatientFieldMap::prefillFor('complete-denture-records', $taskInstanceId ? TaskInstance::find($taskInstanceId) : null),
        );
    }

    public function edit(CompleteDentureRecord $record): Response
    {
        return $this->form($record);
    }

    public function show(CompleteDentureRecord $record): Response
    {
        return $this->form($record, readonly: true);
    }

    public function store(Request $request): RedirectResponse
    {
        $data = CaseSheetSignatures::applyPending('complete-denture-records', $this->validateRecord($request), null, CaseSheetSignatures::signerName($request));
        CompleteDentureRecord::create($data);

        return CaseSheetReturn::redirect()->with('success', 'Complete denture record created.');
    }

    public function update(Request $request, CompleteDentureRecord $record): RedirectResponse
    {
        $data = CaseSheetSignatures::applyPending('complete-denture-records', $this->validateRecord($request), $record, CaseSheetSignatures::signerName($request));
        $record->update($data);

        return CaseSheetReturn::redirect()->with('success', 'Complete denture record updated.');
    }

    public function destroy(CompleteDentureRecord $record): RedirectResponse
    {
        $record->delete();

        return CaseSheetReturn::redirect()->with('success', 'Complete denture record deleted.');
    }

    private function form(?CompleteDentureRecord $record, bool $readonly = false, ?int $taskInstanceId = null, ?int $taskId = null, array $prefill = []): Response
    {
        return Inertia::render('Specialty/SectionedForm', [
            'resource' => 'complete-denture-records',
            'title' => 'Complete Denture Record',
            'sections' => CompleteDentureForm::sections(),
            'stages' => CompleteDentureForm::stages(),
            'doctors' => Doctor::orderBy('name')->get(['id', 'name']),
            'record' => $record,
            // See ProsthodonticsRecordController's matching comment for
            // why this stays a separate prop rather than merged into `record`.
            'patientPrefill' => $prefill,
            // Staff view but never save (App\Services\CaseSheetAccess);
            // the original disables every input for them.
            'readonly' => $readonly || CaseSheetAccess::isViewOnly(),
            'supervisorEditableFields' => CaseSheetAccess::isViewOnly() ? CaseSheetSupervisorFields::fieldsFor('complete-denture-records') : [],
            'supervisorFields' => CaseSheetSupervisorFields::fieldsFor('complete-denture-records'),
            'taskInstanceId' => $record?->task_instances_id ?? $taskInstanceId,
            'linkedDoctor' => CaseSheetDoctor::linked($record?->doctor_id, $record?->task_instances_id ?? $taskInstanceId),
            'taskId' => $record?->task_id ?? $taskId,
        ]);
    }

    private function validateRecord(Request $request): array
    {
        $rules = [
            'doctor_id' => ['required', 'exists:doctors,id'],
            'task_instances_id' => ['nullable', 'integer'],
            'task_id' => ['nullable', 'integer'],
            'patient_name' => ['required', 'string', 'max:255'],
            'age' => ['nullable', 'integer', 'min:0', 'max:150'],
            'sex' => ['nullable', 'in:male,female'],
            'first_time' => ['nullable', 'in:yes,no'],
        ];

        foreach (CompleteDentureForm::sections() as $section) {
            foreach ($section['fields'] as $field) {
                if (isset($rules[$field['key']])) {
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

        foreach (CompleteDentureForm::stages() as $stage) {
            $rules["stage_{$stage['key']}_signature"] = ['nullable', 'string'];
            $rules["stage_{$stage['key']}_date"] = ['nullable', 'date'];
            $rules["stage_{$stage['key']}_grade"] = ['nullable', 'string', 'max:50'];
        }

        return $request->validate($rules);
    }
}
