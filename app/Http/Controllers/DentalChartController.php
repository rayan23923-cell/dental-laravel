<?php

namespace App\Http\Controllers;

use App\Models\DentalChart;
use App\Models\Doctor;
use App\Services\CaseSheetAccess;
use App\Support\CaseSheetSupervisorFields;
use App\Support\OperativeForm;
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
            'title' => 'المخططات السنية (Operative)',
            'titleField' => 'patient_id',
            'records' => CaseSheetAccess::scope(DentalChart::with('doctor'))
                ->when($request->string('search')->toString(), fn ($q, $s) => $q->where('patient_id', 'like', "%{$s}%"))
                ->latest('id')->paginate(15)->withQueryString(),
        ]);
    }

    public function create(Request $request): Response
    {
        return $this->form(
            null,
            taskInstanceId: $request->integer('task_instances_id') ?: null,
            taskId: $request->integer('task_id') ?: null,
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
        DentalChart::create($this->validateRecord($request));

        return redirect()->route('dental-charts.index')->with('success', 'تم حفظ المخطط السني.');
    }

    public function update(Request $request, DentalChart $dentalChart): RedirectResponse
    {
        $dentalChart->update($this->validateRecord($request));

        return redirect()->route('dental-charts.index')->with('success', 'تم تحديث المخطط السني.');
    }

    public function destroy(DentalChart $dentalChart): RedirectResponse
    {
        $dentalChart->delete();

        return redirect()->route('dental-charts.index')->with('success', 'تم حذف المخطط السني.');
    }

    private function form(?DentalChart $record, bool $readonly = false, ?int $taskInstanceId = null, ?int $taskId = null): Response
    {
        return Inertia::render('Specialty/SectionedForm', [
            'resource' => 'dental-charts',
            'title' => 'المخطط السني (Operative)',
            'sections' => OperativeForm::sections(),
            'doctors' => Doctor::orderBy('name')->get(['id', 'name']),
            'record' => $record,
            // Staff view but never save (App\Services\CaseSheetAccess);
            // the original disables every input for them.
            'readonly' => $readonly || CaseSheetAccess::isViewOnly(),
            'supervisorEditableFields' => CaseSheetAccess::isViewOnly() ? CaseSheetSupervisorFields::fieldsFor('dental-charts') : [],
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
