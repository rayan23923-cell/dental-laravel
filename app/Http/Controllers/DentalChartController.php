<?php

namespace App\Http\Controllers;

use App\Models\DentalChart;
use App\Models\Doctor;
use App\Models\Task;
use App\Models\TaskInstance;
use App\Services\CaseSheetAccess;
use App\Support\CaseSheetPatientFieldMap;
use App\Support\CaseSheetReturn;
use App\Support\CaseSheetSignatures;
use App\Support\CaseSheetSupervisorFields;
use App\Support\OperativeForm;
use App\Support\TaskScoring;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Operative case sheet / المخطط السني — the `operative` case-sheet type,
 * stored in `dental_charts`. Port of dental_clinics2/doctor/operative.php;
 * layout in App\Support\OperativeForm.
 *
 * Like the original, a sheet belongs to a task instance: `task_instances_id`
 * is carried through from the case-sheet dispatcher
 * (App\Http\Controllers\CaseSheetController) so a filled sheet is tied to
 * the task it was filled for rather than floating free.
 */
class DentalChartController extends Controller
{
    public function index(Request $request): Response
    {
        return Inertia::render('Specialty/Index', [
            'resource' => 'dental-charts',
            'title' => 'Operative Case Sheets',
            'titleField' => 'patient_id',
            'records' => CaseSheetAccess::scope(DentalChart::with('doctor'))
                ->when($request->string('search')->toString(), fn ($q, $s) => $q->where('patient_id', 'like', "%{$s}%"))
                ->latest('id')->paginate(15)->withQueryString(),
        ]);
    }

    public function create(Request $request): Response
    {
        $taskInstanceId = $request->integer('task_instances_id') ?: null;

        return $this->form(
            null,
            taskInstanceId: $taskInstanceId,
            taskId: $request->integer('task_id') ?: null,
            prefill: CaseSheetPatientFieldMap::prefillFor('dental-charts', $taskInstanceId ? TaskInstance::find($taskInstanceId) : null),
        );
    }

    public function edit(DentalChart $dentalChart): Response
    {
        return $this->form($dentalChart);
    }

    public function show(DentalChart $dentalChart): Response
    {
        return $this->form($dentalChart, readonly: true);
    }

    public function store(Request $request): RedirectResponse
    {
        $data = CaseSheetSignatures::applyPending('dental-charts', $this->validateRecord($request), null, CaseSheetSignatures::signerName($request));
        DentalChart::create($data);

        return CaseSheetReturn::redirect()->with('success', 'Operative case sheet created.');
    }

    public function update(Request $request, DentalChart $dentalChart): RedirectResponse
    {
        $data = CaseSheetSignatures::applyPending('dental-charts', $this->validateRecord($request), $dentalChart, CaseSheetSignatures::signerName($request));
        $dentalChart->update($data);

        return CaseSheetReturn::redirect()->with('success', 'Operative case sheet updated.');
    }

    public function destroy(DentalChart $dentalChart): RedirectResponse
    {
        $dentalChart->delete();

        return CaseSheetReturn::redirect()->with('success', 'Operative case sheet deleted.');
    }

    private function form(?DentalChart $record, bool $readonly = false, ?int $taskInstanceId = null, ?int $taskId = null, array $prefill = []): Response
    {
        return Inertia::render('Specialty/SectionedForm', [
            'resource' => 'dental-charts',
            'title' => 'Operative Case Sheet',
            'sections' => OperativeForm::sections(),
            'doctors' => Doctor::orderBy('name')->get(['id', 'name']),
            'record' => $record,
            // See ProsthodonticsRecordController's matching comment for
            // why this stays a separate prop rather than merged into `record`.
            'patientPrefill' => $prefill,
            // Staff view but never save (App\Services\CaseSheetAccess);
            // the original disables every input for them.
            'readonly' => $readonly || CaseSheetAccess::isViewOnly(),
            'supervisorEditableFields' => CaseSheetAccess::isViewOnly() ? CaseSheetSupervisorFields::fieldsFor('dental-charts') : [],
            'supervisorFields' => CaseSheetSupervisorFields::fieldsFor('dental-charts'),
            'taskInstanceId' => $record?->task_instances_id ?? $taskInstanceId,
            'taskId' => $record?->task_id ?? $taskId,
            // A root-filling task opens with the Endodontics section on (2026-10-14).
            'rootFilling' => TaskScoring::isRootFilling(
                Task::find($record?->task_id ?? $taskId)
                    ?? TaskInstance::find($record?->task_instances_id ?? $taskInstanceId)?->task
            ),
        ]);
    }

    private function validateRecord(Request $request): array
    {
        $rules = [
            'doctor_id' => ['required', 'exists:doctors,id'],
            'task_instances_id' => ['nullable', 'integer'],
            'task_id' => ['nullable', 'integer'],
            'patient_id' => ['required', 'string', 'max:255'],
            'patient_age' => ['nullable', 'integer', 'min:0', 'max:150'],
            'patient_sex' => ['nullable', 'in:male,female'],
            // The original's operative sheet is per-dentition; `permanent`
            // is its default and the only one the ported layout exposes.
            'chart_type' => ['nullable', 'in:primary,permanent'],
        ];

        foreach (OperativeForm::sections() as $section) {
            foreach ($section['fields'] as $field) {
                if (isset($rules[$field['key']])) {
                    continue;
                }
                $rules[$field['key']] = match ($field['type']) {
                    'boolean' => ['nullable', 'boolean'],
                    'number' => ['nullable', 'integer'],
                    'date' => ['nullable', 'date'],
                    // tooth_data has a real 'array' cast on the model
                    // (unlike the periodontal sheet's chart_data, a plain
                    // text column) — posted and validated as an array, not
                    // a JSON string, or Eloquent double-encodes it on save.
                    'dental_chart' => ['nullable', 'array'],
                    // endodontics_data carries the same 'array' cast — see
                    // App\Models\DentalChart::casts().
                    'endodontics' => ['nullable', 'array'],
                    default => ['nullable', 'string'],
                };
            }
        }

        return $request->validate($rules);
    }
}
