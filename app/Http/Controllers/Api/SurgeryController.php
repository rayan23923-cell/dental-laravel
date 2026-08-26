<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\SurgeryResource;
use App\Models\Patient;
use App\Models\Surgery;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SurgeryController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $doctor = $request->user();

        $query = Surgery::query();
        if ($doctor instanceof \App\Models\Doctor) {
            $query->where('doctor_id', $doctor->id);
        }

        $records = $query->latest('id')->paginate(15);

        return SurgeryResource::collection($records)->response();
    }

    public function show(Surgery $record): JsonResponse
    {
        return (new SurgeryResource($record))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->validateRecord($request);
        $data['patient_id'] = $this->resolvePatientId($data);

        $record = Surgery::create($data);

        return (new SurgeryResource($record))->response()->setStatusCode(201);
    }

    public function update(Request $request, Surgery $record): JsonResponse
    {
        $data = $this->validateRecord($request, true);
        $data['patient_id'] = $this->resolvePatientId($data, $record->patient_id);

        $record->update($data);

        return (new SurgeryResource($record))->response();
    }

    /**
     * `surgeries.patient_id` is an int FK while a case-sheet client (web or
     * this API) only ever collects a name — mirrors
     * `App\Http\Controllers\SurgeryController::resolvePatientId()` exactly,
     * so a record created through either path stays joinable to a real
     * `patients` row rather than carrying an orphan id. Previously this
     * API controller had no equivalent: `patient_id` was `required` with no
     * resolution, which meant no client could ever pass validation without
     * already possessing a valid `patients.id` — an id nothing in this API
     * exposes a way to obtain from a typed name. Found while scoping "create
     * new case sheet" for the Flutter client (see flutter_app/README.md).
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

    public function destroy(Surgery $record): JsonResponse
    {
        $record->delete();

        return response()->json(null, 204);
    }

    private function validateRecord(Request $request, bool $partial = false): array
    {
        $rules = [
            'task_instances_id' => ['nullable', 'integer'],
            // Not client-supplied — resolved server-side by
            // resolvePatientId() from patient_name (+ patient_phone), same
            // as the web controller. Accepting it as 'nullable' rather than
            // omitting it entirely keeps `$request->validate()` from
            // stripping a value out of $data before resolvePatientId() ever
            // sees it, in case a future caller does pass one directly.
            'patient_id' => ['nullable', 'integer'],
            'patient_name' => ['nullable', 'string', 'max:255'],
            'doctor_id' => ['required', 'integer'],
            'student_name' => ['nullable', 'string', 'max:255'],
            'grade_group' => ['nullable', 'string', 'max:255'],
            'surgery_date' => ['nullable', 'date'],
            'surgery_date_field' => ['nullable', 'date'],
            'start_time' => ['nullable', 'string', 'max:255'],
            'staff_signature' => ['nullable', 'string', 'max:255'],
            'surgery_type' => ['nullable', 'string', 'max:255'],
            'chief_complaint' => ['nullable', 'string'],
            'cc_pain' => ['nullable', 'boolean'],
            'cc_swelling' => ['nullable', 'boolean'],
            'cc_others' => ['nullable', 'string', 'max:255'],
            'medical_history' => ['nullable', 'string'],
            'hpi_duration' => ['nullable', 'string'],
            'hpi_onset' => ['nullable', 'string'],
            'hpi_factors' => ['nullable', 'string'],
            'hpi_characteristics' => ['nullable', 'string'],
            'past_dental_history' => ['nullable', 'string'],
            'mh_blood_pressure' => ['nullable', 'string', 'max:255'],
            'mh_diabetes' => ['nullable', 'string', 'max:255'],
            'mh_heart' => ['nullable', 'string', 'max:255'],
            'mh_thyroid' => ['nullable', 'string', 'max:255'],
            'mh_bleeding' => ['nullable', 'string', 'max:255'],
            'mh_epilepsy' => ['nullable', 'string', 'max:255'],
            'mh_respiratory' => ['nullable', 'string', 'max:255'],
            'mh_git' => ['nullable', 'string', 'max:255'],
            'mh_liver' => ['nullable', 'string', 'max:255'],
            'mh_kidney' => ['nullable', 'string', 'max:255'],
            'mh_hiv' => ['nullable', 'string', 'max:255'],
            'mh_implants' => ['nullable', 'string', 'max:255'],
            'mh_hospitalization' => ['nullable', 'string', 'max:255'],
            'mh_hospitalization_details' => ['nullable', 'string'],
            'mh_smoking' => ['nullable', 'string', 'max:255'],
            'mh_smoking_amount' => ['nullable', 'string', 'max:255'],
            'mh_allergies' => ['nullable', 'string', 'max:255'],
            'mh_allergies_details' => ['nullable', 'string'],
            'mh_drugs' => ['nullable', 'string', 'max:255'],
            'mh_drugs_details' => ['nullable', 'string'],
            'mh_pregnant' => ['nullable', 'string', 'max:255'],
            'exam_extraoral' => ['nullable', 'string'],
            'exam_intraoral' => ['nullable', 'string'],
            'investigation' => ['nullable', 'string'],
            'diagnosis' => ['nullable', 'string'],
            'treatment_tooth' => ['nullable', 'string', 'max:255'],
            'selected_teeth' => ['nullable', 'string'],
            'surgical_procedure' => ['nullable', 'string'],
            'anesthesia_type' => ['nullable', 'string', 'max:255'],
            'duration_minutes' => ['nullable', 'integer'],
            'complications' => ['nullable', 'string'],
            'postop_instructions' => ['nullable', 'string'],
            'follow_up_date' => ['nullable', 'date'],
            'status' => ['nullable', 'string', 'max:255'],
            'notes' => ['nullable', 'string'],
            'patient_phone' => ['nullable', 'string', 'max:255'],
            'patient_age' => ['nullable', 'integer'],
            'patient_gender' => ['nullable', 'string', 'max:255'],
            'patient_address' => ['nullable', 'string'],
            'patient_occupation' => ['nullable', 'string', 'max:255'],
            'senior_doctor_name' => ['nullable', 'string', 'max:255'],
            'approval_date' => ['nullable', 'date'],
            'senior_signature' => ['nullable', 'string'],
        ];

        if ($partial) {
            // Preserve `nullable` instead of overwriting it — see the full
            // explanation in CompleteDentureRecordController::validateRecord().
            // Blindly replacing index 0 turned `['nullable', 'string']` into
            // `['sometimes', 'string']`; combined with Laravel's global
            // `ConvertEmptyStringsToNull` middleware (an empty string in the
            // body becomes `null` before validation), a correctly-sent empty
            // optional field failed with "must be a string" — reproduced via
            // a real HTTP PUT, not just a rule-level check.
            foreach ($rules as $field => $fieldRules) {
                if (($fieldRules[0] ?? null) === 'nullable') {
                    array_unshift($rules[$field], 'sometimes');
                } else {
                    $rules[$field][0] = 'sometimes';
                }
            }
        }

        return $request->validate($rules);
    }
}
