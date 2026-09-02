<?php

namespace App\Http\Controllers;

use App\Models\Doctor;
use App\Models\ProsthodonticsRecord;
use App\Models\TaskInstance;
use App\Services\CaseSheetAccess;
use App\Support\CaseSheetPatientFieldMap;
use App\Support\CaseSheetSignatures;
use App\Support\CaseSheetSupervisorFields;
use App\Support\ProsthodonticsForm;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Removable partial denture case sheet — faithful port of
 * dental_clinics2/doctor/prosthodontics.php (layout in
 * App\Support\ProsthodonticsForm).
 */
class ProsthodonticsRecordController extends Controller
{
    public function index(): Response
    {
        return Inertia::render('Specialty/Index', [
            'resource' => 'prosthodontics-records',
            'title' => 'Prosthodontics Records',
            'titleField' => 'patient_name',
            'records' => CaseSheetAccess::scope(ProsthodonticsRecord::with('doctor'))->latest('id')->paginate(15),
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
            // Auto-fills the patient fields from whichever patient
            // TaskStarter::start() already tied this task instance to —
            // see CaseSheetPatientFieldMap's own doc comment.
            prefill: CaseSheetPatientFieldMap::prefillFor('prosthodontics-records', $taskInstanceId ? TaskInstance::find($taskInstanceId) : null),
        );
    }

    public function edit(ProsthodonticsRecord $record): Response
    {
        return $this->form($record);
    }

    public function show(ProsthodonticsRecord $record): Response
    {
        return $this->form($record, readonly: true);
    }

    public function store(Request $request): RedirectResponse
    {
        ProsthodonticsRecord::create($this->prepare($request));

        return redirect()->route('prosthodontics-records.index')->with('success', 'Prosthodontics record created.');
    }

    public function update(Request $request, ProsthodonticsRecord $record): RedirectResponse
    {
        $record->update($this->prepare($request, $record));

        return redirect()->route('prosthodontics-records.index')->with('success', 'Prosthodontics record updated.');
    }

    public function destroy(ProsthodonticsRecord $record): RedirectResponse
    {
        $record->delete();

        return redirect()->route('prosthodontics-records.index')->with('success', 'Prosthodontics record deleted.');
    }

    private function form(?ProsthodonticsRecord $record, bool $readonly = false, ?int $taskInstanceId = null, ?int $taskId = null, array $prefill = []): Response
    {
        return Inertia::render('Specialty/SectionedForm', [
            'resource' => 'prosthodontics-records',
            'title' => 'Prosthodontics Record',
            'sections' => ProsthodonticsForm::sections(),
            'stages' => ProsthodonticsForm::stages(),
            'doctors' => Doctor::orderBy('name')->get(['id', 'name']),
            'record' => $record,
            // Kept separate from `record` deliberately — `SectionedForm.vue`'s
            // `isEdit` is `props.record !== null`, so merging this into
            // `record` on a create would make the page think it's editing
            // (wrong title/button text, and `props.record.id` being
            // undefined would build a broken PUT to `/undefined`).
            'patientPrefill' => $prefill,
            // Staff view but never save (App\Services\CaseSheetAccess);
            // the original disables every input for them.
            'readonly' => $readonly || CaseSheetAccess::isViewOnly(),
            'supervisorEditableFields' => CaseSheetAccess::isViewOnly() ? CaseSheetSupervisorFields::fieldsFor('prosthodontics-records') : [],
            'supervisorFields' => CaseSheetSupervisorFields::fieldsFor('prosthodontics-records'),
            'taskInstanceId' => $record?->task_instances_id ?? $taskInstanceId,
            'taskId' => $record?->task_id ?? $taskId,
        ]);
    }

    /**
     * The original writes the selected missing/caries teeth to their own
     * columns *and* mirrors them inside the `tooth_chart_data` JSON blob
     * (its save payload is `{ selectedTeeth, dmftData, missingTeeth,
     * cariesTeeth }`), and its loader falls back to that blob when the
     * direct column is empty. Kept in sync here so a record written by this
     * app still loads correctly in the original.
     */
    private function prepare(Request $request, ?ProsthodonticsRecord $existing = null): array
    {
        $data = $this->validateRecord($request);
        $data = CaseSheetSignatures::applyPending('prosthodontics-records', $data, $existing, CaseSheetSignatures::signerName($request));

        $data['tooth_chart_data'] = json_encode([
            'selectedTeeth' => [],
            'dmftData' => new \stdClass(),
            'missingTeeth' => $data['missing_teeth'] ?? '',
            'cariesTeeth' => $data['caries_teeth'] ?? '',
        ]);

        return $data;
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
            'tmj_disorder' => ['nullable', 'in:Yes,No'],
        ];

        foreach (ProsthodonticsForm::sections() as $section) {
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

        foreach (ProsthodonticsForm::stages() as $stage) {
            $rules["stage_{$stage['key']}_signature"] = ['nullable', 'string'];
            $rules["stage_{$stage['key']}_date"] = ['nullable', 'date'];
            $rules["stage_{$stage['key']}_grade"] = ['nullable', 'string', 'max:50'];
        }

        return $request->validate($rules);
    }
}
