<?php

namespace App\Http\Controllers;

use App\Models\Doctor;
use App\Models\Patient;
use App\Models\Surgery;
use App\Services\CaseSheetAccess;
use App\Support\CaseSheetSupervisorFields;
use App\Support\SurgeryForm;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Surgery case sheet — faithful port of
 * dental_clinics2/doctor/surgery.php (layout in App\Support\SurgeryForm).
 * This sheet has proper per-field columns, including the original's `mh_*`
 * yes/no medical-history checklist.
 */
class SurgeryController extends Controller
{
    public function index(): Response
    {
        return Inertia::render('Specialty/Index', [
            'resource' => 'surgeries',
            'title' => 'Surgeries',
            'titleField' => 'patient_name',
            'records' => CaseSheetAccess::scope(Surgery::with('doctor'))->latest('id')->paginate(15),
        ]);
    }

    public function create(Request $request): Response
    {
        // See README "task_instances_id wiring" — a blank sheet opened
        // from a task instance must stay linked to it.
        return $this->form(
            null,
            taskInstanceId: $request->integer('task_instances_id') ?: null,
            taskId: $request->integer('task_id') ?: null,
        );
    }

    public function edit(Surgery $record): Response
    {
        return $this->form($record);
    }

    public function show(Surgery $record): Response
    {
        return $this->form($record, readonly: true);
    }

    public function store(Request $request): RedirectResponse
    {
        $data = $this->validateRecord($request);
        $data['patient_id'] = $this->resolvePatientId($data);

        Surgery::create($data);

        return redirect()->route('surgeries.index')->with('success', 'Surgery record created.');
    }

    public function update(Request $request, Surgery $record): RedirectResponse
    {
        $data = $this->validateRecord($request);
        $data['patient_id'] = $this->resolvePatientId($data, $record->patient_id);

        $record->update($data);

        return redirect()->route('surgeries.index')->with('success', 'Surgery record updated.');
    }

    public function destroy(Surgery $record): RedirectResponse
    {
        $record->delete();

        return redirect()->route('surgeries.index')->with('success', 'Surgery record deleted.');
    }

    private function form(?Surgery $record, bool $readonly = false, ?int $taskInstanceId = null, ?int $taskId = null): Response
    {
        return Inertia::render('Specialty/SectionedForm', [
            'resource' => 'surgeries',
            'title' => 'Surgery',
            'sections' => SurgeryForm::sections(),
            'doctors' => Doctor::orderBy('name')->get(['id', 'name']),
            'record' => $record,
            // Staff view but never save (App\Services\CaseSheetAccess);
            // the original disables every input for them.
            'readonly' => $readonly || CaseSheetAccess::isViewOnly(),
            'supervisorEditableFields' => CaseSheetAccess::isViewOnly() ? CaseSheetSupervisorFields::fieldsFor('surgeries') : [],
            'taskInstanceId' => $record?->task_instances_id ?? $taskInstanceId,
            'taskId' => $record?->task_id ?? $taskId,
        ]);
    }

    /**
     * `surgeries.patient_id` is an int FK while the form only asks for a
     * name — same arrangement as the periodontal sheet, resolved the same
     * way (reuse a matching patient, else create one) so the record stays
     * joinable rather than carrying an orphan id.
     */
    private function resolvePatientId(array $data, ?int $currentId = null): ?int
    {
        $name = trim($data['patient_name'] ?? '');
        if ($name === '') {
            return $currentId;
        }

        $query = Patient::where('name', $name);
        if (! empty($data['patient_phone'])) {
            $query->where('phone', $data['patient_phone']);
        }

        return ($query->first() ?? Patient::create([
            'name' => $name,
            'phone' => $data['patient_phone'] ?? null,
        ]))->id;
    }

    private function validateRecord(Request $request): array
    {
        $rules = [
            'doctor_id' => ['required', 'exists:doctors,id'],
            'task_instances_id' => ['nullable', 'integer'],
            'task_id' => ['nullable', 'integer'],
            'patient_name' => ['required', 'string', 'max:255'],
            'patient_age' => ['nullable', 'integer', 'min:0', 'max:150'],
            'patient_gender' => ['nullable', 'in:male,female'],
            'status' => ['nullable', 'in:planned,in_progress,completed,cancelled'],
            'duration_minutes' => ['nullable', 'integer', 'min:0'],
            // MySQL returns TIME columns as HH:MM:SS, and <input type="time">
            // round-trips that form unchanged — so an edit that never touches
            // the field re-submits HH:MM:SS. Accepting only H:i would reject
            // it (a save that worked on create failing on edit).
            'start_time' => ['nullable', 'date_format:H:i,H:i:s'],
        ];

        foreach (SurgeryForm::sections() as $section) {
            foreach ($section['fields'] as $field) {
                if (isset($rules[$field['key']])) {
                    continue;
                }
                $rules[$field['key']] = match ($field['type']) {
                    'boolean' => ['nullable', 'boolean'],
                    'number' => ['nullable', 'integer'],
                    'date' => ['nullable', 'date'],
                    'select' => ['nullable', 'string', 'max:255'],
                    default => ['nullable', 'string'],
                };
            }
        }

        return $request->validate($rules);
    }
}
