<?php

namespace App\Http\Controllers;

use App\Models\Doctor;
use App\Models\Patient;
use App\Models\PeriodontalChart;
use App\Services\CaseSheetAccess;
use App\Support\PeriodontalChartForm;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Periodontal chart — a faithful port of
 * dental_clinics2/doctor/periodontal_chart.php rather than the generic
 * column-driven form the other specialty tables still use. The real
 * section layout lives in App\Support\PeriodontalChartForm; the per-tooth
 * charts are rendered by resources/js/Components/PerioChart.vue and stored
 * in the `chart_data` JSON column in the original's exact shape.
 */
class PeriodontalChartController extends Controller
{
    public function index(): Response
    {
        return Inertia::render('Specialty/Index', [
            'resource' => 'periodontal-charts',
            'title' => 'Periodontal Charts',
            'titleField' => 'patient_name',
            'records' => CaseSheetAccess::scope(PeriodontalChart::with('doctor'))->latest('id')->paginate(15),
        ]);
    }

    public function create(Request $request): Response
    {
        // See README "task_instances_id wiring" — a blank sheet opened
        // from a task instance must stay linked to it.
        return $this->form(null, taskInstanceId: $request->integer('task_instances_id') ?: null);
    }

    public function edit(PeriodontalChart $record): Response
    {
        return $this->form($record);
    }

    public function show(PeriodontalChart $record): Response
    {
        return $this->form($record, readonly: true);
    }

    public function store(Request $request): RedirectResponse
    {
        $data = $this->validateRecord($request);
        $data['patient_id'] = $this->resolvePatientId($data);

        PeriodontalChart::create($data);

        return redirect()->route('periodontal-charts.index')->with('success', 'Periodontal chart created.');
    }

    public function update(Request $request, PeriodontalChart $record): RedirectResponse
    {
        $data = $this->validateRecord($request);
        $data['patient_id'] = $this->resolvePatientId($data, $record->patient_id);

        $record->update($data);

        return redirect()->route('periodontal-charts.index')->with('success', 'Periodontal chart updated.');
    }

    public function destroy(PeriodontalChart $record): RedirectResponse
    {
        $record->delete();

        return redirect()->route('periodontal-charts.index')->with('success', 'Periodontal chart deleted.');
    }

    private function form(?PeriodontalChart $record, bool $readonly = false, ?int $taskInstanceId = null): Response
    {
        return Inertia::render('Specialty/SectionedForm', [
            'resource' => 'periodontal-charts',
            'title' => 'Periodontal Chart',
            'sections' => PeriodontalChartForm::sections(),
            'chartGroups' => PeriodontalChartForm::chartGroups(),
            'chartField' => 'chart_data',
            'doctors' => Doctor::orderBy('name')->get(['id', 'name']),
            'record' => $record,
            // chart_data is a longtext column holding JSON; decoded here so
            // the page gets a real object rather than a string to re-parse.
            'chartData' => $record?->chart_data ? json_decode($record->chart_data, true) : null,
            // Staff view but never save (App\Services\CaseSheetAccess);
            // the original disables every input for them.
            'readonly' => $readonly || CaseSheetAccess::isViewOnly(),
            'taskInstanceId' => $record?->task_instances_id ?? $taskInstanceId,
        ]);
    }

    /**
     * The original (save_periodontal_chart.php) resolves the typed patient
     * name to a real `patients` row — reusing an existing patient matched on
     * name (+ phone when given) or creating one — and stores that FK in
     * `periodontal_charts.patient_id`, which is an int column even though the
     * form only ever asks for a name. Ported so charts stay joinable to the
     * patient record rather than holding an orphan id.
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

        $patient = $query->first();

        if (! $patient) {
            $patient = Patient::create([
                'name' => $name,
                'phone' => $data['patient_phone'] ?? null,
            ]);
        }

        return $patient->id;
    }

    private function validateRecord(Request $request): array
    {
        $rules = [
            'doctor_id' => ['required', 'exists:doctors,id'],
            'task_instances_id' => ['nullable', 'integer'],
            'patient_name' => ['required', 'string', 'max:255'],
            'patient_phone' => ['nullable', 'string', 'max:50'],
            'chart_date' => ['required', 'date'],
            'patient_age' => ['nullable', 'integer', 'min:0', 'max:150'],
            'patient_gender' => ['nullable', 'in:male,female'],
            'patient_address' => ['nullable', 'string'],
            'patient_occupation' => ['nullable', 'string', 'max:255'],
            'patient_marital_status' => ['nullable', 'in:single,married'],
            'student_name' => ['nullable', 'string', 'max:255'],
            'student_group' => ['nullable', 'string', 'max:100'],
            'case_start_date' => ['nullable', 'date'],
            'mentor_name' => ['nullable', 'string', 'max:255'],
            'women_pregnancy' => ['nullable', 'in:yes,no,dk'],
            'pregnancy_weeks' => ['nullable', 'string', 'max:50'],
            'women_birth_control' => ['nullable', 'in:yes,no,dk'],
            'women_nursing' => ['nullable', 'in:yes,no,dk'],
            'exam_bpe_ur' => ['nullable', 'string', 'max:10'],
            'exam_bpe_ua' => ['nullable', 'string', 'max:10'],
            'exam_bpe_ul' => ['nullable', 'string', 'max:10'],
            'exam_bpe_lr' => ['nullable', 'string', 'max:10'],
            'exam_bpe_la' => ['nullable', 'string', 'max:10'],
            'exam_bpe_ll' => ['nullable', 'string', 'max:10'],
            'diagnosis_pattern' => ['nullable', 'string', 'max:255'],
            'diagnosis_stage' => ['nullable', 'string', 'max:50'],
            'diagnosis_grade' => ['nullable', 'string', 'max:50'],
            'diagnosis_status' => ['nullable', 'string', 'max:50'],
            'treatment_plan_date' => ['nullable', 'date'],
            'approval_date' => ['nullable', 'date'],
            'senior_doctor_name' => ['nullable', 'string', 'max:255'],
            'chart_data' => ['nullable', 'string'],
        ];

        // Everything else the layout binds to, typed from its field spec.
        foreach (PeriodontalChartForm::sections() as $section) {
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

        return $request->validate($rules);
    }
}
