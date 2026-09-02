<?php

namespace App\Http\Controllers;

use App\Models\Doctor;
use App\Models\OralMedicineChart;
use App\Models\TaskInstance;
use App\Services\CaseSheetAccess;
use App\Support\CaseSheetPatientFieldMap;
use App\Support\CaseSheetSignatures;
use App\Support\CaseSheetSupervisorFields;
use App\Support\OralMedicineForm;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Oral medicine case sheet — faithful port of
 * dental_clinics2/doctor/oral_medicine.php (layout in
 * App\Support\OralMedicineForm). Several of this sheet's columns hold JSON
 * groups the original posts as `column[subkey]`; see that class.
 */
class OralMedicineChartController extends Controller
{
    public function index(): Response
    {
        return Inertia::render('Specialty/Index', [
            'resource' => 'oral-medicine-charts',
            'title' => 'Oral Medicine Charts',
            'titleField' => 'patient_id',
            'records' => CaseSheetAccess::scope(OralMedicineChart::with('doctor'))->latest('id')->paginate(15),
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
            prefill: CaseSheetPatientFieldMap::prefillFor('oral-medicine-charts', $taskInstanceId ? TaskInstance::find($taskInstanceId) : null),
        );
    }

    public function edit(OralMedicineChart $record): Response
    {
        return $this->form($record);
    }

    public function show(OralMedicineChart $record): Response
    {
        return $this->form($record, readonly: true);
    }

    public function store(Request $request): RedirectResponse
    {
        $data = CaseSheetSignatures::applyPending('oral-medicine-charts', $this->validateRecord($request), null, CaseSheetSignatures::signerName($request));
        OralMedicineChart::create($data);

        return redirect()->route('oral-medicine-charts.index')->with('success', 'Oral medicine chart created.');
    }

    public function update(Request $request, OralMedicineChart $record): RedirectResponse
    {
        $data = CaseSheetSignatures::applyPending('oral-medicine-charts', $this->validateRecord($request), $record, CaseSheetSignatures::signerName($request));
        $record->update($data);

        return redirect()->route('oral-medicine-charts.index')->with('success', 'Oral medicine chart updated.');
    }

    public function destroy(OralMedicineChart $record): RedirectResponse
    {
        $record->delete();

        return redirect()->route('oral-medicine-charts.index')->with('success', 'Oral medicine chart deleted.');
    }

    private function form(?OralMedicineChart $record, bool $readonly = false, ?int $taskInstanceId = null, ?int $taskId = null, array $prefill = []): Response
    {
        return Inertia::render('Specialty/SectionedForm', [
            'resource' => 'oral-medicine-charts',
            'title' => 'Oral Medicine Chart',
            'sections' => OralMedicineForm::sections(),
            'doctors' => Doctor::orderBy('name')->get(['id', 'name']),
            'record' => $record,
            // See ProsthodonticsRecordController's matching comment for
            // why this stays a separate prop rather than merged into `record`.
            'patientPrefill' => $prefill,
            // Staff view but never save (App\Services\CaseSheetAccess);
            // the original disables every input for them.
            'readonly' => $readonly || CaseSheetAccess::isViewOnly(),
            'supervisorEditableFields' => CaseSheetAccess::isViewOnly() ? CaseSheetSupervisorFields::fieldsFor('oral-medicine-charts') : [],
            'supervisorFields' => CaseSheetSupervisorFields::fieldsFor('oral-medicine-charts'),
            'taskInstanceId' => $record?->task_instances_id ?? $taskInstanceId,
            'taskId' => $record?->task_id ?? $taskId,
        ]);
    }

    private function validateRecord(Request $request): array
    {
        $rules = [
            'doctor_id' => ['required', 'exists:doctors,id'],
            'task_instances_id' => ['nullable', 'integer'],
            'task_id' => ['nullable', 'integer'],
            'patient_id' => ['required', 'string', 'max:255'],
            'visit_date' => ['required', 'date'],
            'patient_age' => ['nullable', 'integer', 'min:0', 'max:150'],
            'patient_sex' => ['nullable', 'in:male,female'],
            // See App\Support\CaseSheetSupervisorFields.
            'supervisor_notes' => ['nullable', 'string'],
            'supervisor_signature' => ['nullable', 'string'],
        ];

        foreach (OralMedicineForm::sections() as $section) {
            foreach ($section['fields'] as $field) {
                // Grouped subkeys arrive already collapsed into their JSON
                // column by the form, so only the column itself is validated.
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

        foreach (OralMedicineForm::groupColumns() as $column) {
            $rules[$column] = ['nullable', 'string'];
        }

        return $request->validate($rules);
    }
}
