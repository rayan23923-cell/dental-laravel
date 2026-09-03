<?php

namespace App\Http\Controllers;

use App\Models\AdvancedPeriodontalChart;
use App\Models\Doctor;
use App\Models\Patient;
use App\Models\TaskInstance;
use App\Services\CaseSheetAccess;
use App\Support\AdvancedPeriodontalChartForm;
use App\Support\CaseSheetPatientFieldMap;
use App\Support\CaseSheetSignatures;
use App\Support\CaseSheetSupervisorFields;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * "Advanced Periodontal Chart" — see App\Support\AdvancedPeriodontalChartForm's
 * own doc comment. Structurally a copy of PeriodontalChartController (same
 * task-linkage, signature, and supervisor-field plumbing every case sheet
 * shares) minus the medical-history sections this resource doesn't have.
 */
class AdvancedPeriodontalChartController extends Controller
{
    public function index(): Response
    {
        return Inertia::render('Specialty/Index', [
            'resource' => 'advanced-periodontal-charts',
            'title' => 'Advanced Periodontal Charts',
            'titleField' => 'patient_last_name',
            'records' => CaseSheetAccess::scope(AdvancedPeriodontalChart::with('doctor'))->latest('id')->paginate(15),
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
            // "اضف كيو ار لمسح معلومات المريض مثل كيسشيتات البقية"
            // (2026-09-04) — same auto-fill every other case sheet already
            // has; see CaseSheetPatientFieldMap's own doc comment for why
            // this resource needed a dedicated (name-splitting) code path
            // there rather than a plain MAP entry.
            prefill: CaseSheetPatientFieldMap::prefillFor('advanced-periodontal-charts', $taskInstanceId ? TaskInstance::find($taskInstanceId) : null),
        );
    }

    public function edit(AdvancedPeriodontalChart $record): Response
    {
        return $this->form($record);
    }

    public function show(AdvancedPeriodontalChart $record): Response
    {
        return $this->form($record, readonly: true);
    }

    public function store(Request $request): RedirectResponse
    {
        $data = $this->validateRecord($request);
        $data = CaseSheetSignatures::applyPending('advanced-periodontal-charts', $data, null, CaseSheetSignatures::signerName($request));
        $data['patient_id'] = $this->resolvePatientId($data);

        AdvancedPeriodontalChart::create($data);

        return redirect()->route('advanced-periodontal-charts.index')->with('success', 'Advanced periodontal chart created.');
    }

    public function update(Request $request, AdvancedPeriodontalChart $record): RedirectResponse
    {
        $data = $this->validateRecord($request);
        $data = CaseSheetSignatures::applyPending('advanced-periodontal-charts', $data, $record, CaseSheetSignatures::signerName($request));
        $data['patient_id'] = $this->resolvePatientId($data, $record->patient_id);

        $record->update($data);

        return redirect()->route('advanced-periodontal-charts.index')->with('success', 'Advanced periodontal chart updated.');
    }

    public function destroy(AdvancedPeriodontalChart $record): RedirectResponse
    {
        $record->delete();

        return redirect()->route('advanced-periodontal-charts.index')->with('success', 'Advanced periodontal chart deleted.');
    }

    private function form(?AdvancedPeriodontalChart $record, bool $readonly = false, ?int $taskInstanceId = null, ?int $taskId = null, array $prefill = []): Response
    {
        return Inertia::render('Specialty/SectionedForm', [
            'resource' => 'advanced-periodontal-charts',
            'title' => 'Advanced Periodontal Chart',
            'sections' => AdvancedPeriodontalChartForm::sections(),
            'chartField' => 'chart_data',
            // The 32-tooth grid — a completely separate mechanism from
            // `chartGroups`/`plaqueVisits` (this resource has neither),
            // see AdvancedPerioChartSessions.vue's own doc comment.
            'advancedPerioChart' => true,
            'doctors' => Doctor::orderBy('name')->get(['id', 'name']),
            'record' => $record,
            // See ProsthodonticsRecordController's matching comment for
            // why this stays a separate prop rather than merged into `record`.
            'patientPrefill' => $prefill,
            'chartData' => $record?->chart_data ? json_decode($record->chart_data, true) : null,
            'readonly' => $readonly || CaseSheetAccess::isViewOnly(),
            'supervisorEditableFields' => CaseSheetAccess::isViewOnly() ? CaseSheetSupervisorFields::fieldsFor('advanced-periodontal-charts') : [],
            'supervisorFields' => CaseSheetSupervisorFields::fieldsFor('advanced-periodontal-charts'),
            'taskInstanceId' => $record?->task_instances_id ?? $taskInstanceId,
            'taskId' => $record?->task_id ?? $taskId,
        ]);
    }

    /** Same resolvePatientId pattern every case-sheet controller uses — see PeriodontalChartController's own copy. */
    private function resolvePatientId(array $data, ?int $currentId = null): ?int
    {
        $name = trim(($data['patient_first_name'] ?? '').' '.($data['patient_last_name'] ?? ''));
        if ($name === '') {
            return $currentId;
        }

        $patient = Patient::where('name', $name)->first();

        if (! $patient) {
            $patient = Patient::create(['name' => $name]);
        }

        return $patient->id;
    }

    private function validateRecord(Request $request): array
    {
        $rules = [
            'doctor_id' => ['required', 'exists:doctors,id'],
            'task_instances_id' => ['nullable', 'integer'],
            'task_id' => ['nullable', 'integer'],
            'patient_last_name' => ['required', 'string', 'max:255'],
            'patient_first_name' => ['required', 'string', 'max:255'],
            'patient_dob' => ['nullable', 'date'],
            'patient_gender' => ['nullable', 'in:male,female'],
            'chart_date' => ['required', 'date'],
            'exam_type' => ['nullable', 'in:initial,re_evaluation'],
            'chart_data' => ['nullable', 'string'],
            // Radio fields use PeriodontalChartForm::YND's own value set,
            // not the generic 'boolean'/'string' the loop below would infer
            // from `type: 'radio'` — same override
            // PeriodontalChartController::validateRecord() makes for its
            // own copy of these three fields.
            'women_pregnancy' => ['nullable', 'in:yes,no,dk'],
            'women_birth_control' => ['nullable', 'in:yes,no,dk'],
            'women_nursing' => ['nullable', 'in:yes,no,dk'],
        ];

        // Everything else the merged-in sections bind to, typed from its
        // field spec — same pattern PeriodontalChartController's own
        // validateRecord() uses, so a field added to either form's
        // sections() is validated without a rule being hand-written here.
        foreach (AdvancedPeriodontalChartForm::sections() as $section) {
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
