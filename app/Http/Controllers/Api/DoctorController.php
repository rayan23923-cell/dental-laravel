<?php

namespace App\Http\Controllers\Api;

use App\Support\LinkedRecords;
use App\Http\Controllers\Controller;
use App\Http\Resources\DoctorResource;
use App\Models\Doctor;
use App\Services\AcademicSessionHelper;
use App\Services\CredentialMailer;
use App\Services\ScopeHelper;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;

class DoctorController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        // Same education-type/stage scoping as the web admin's doctor list
        // (see App\Http\Controllers\DoctorController) — kept in sync so the
        // Flutter client can't see doctors outside the caller's scope just
        // by hitting the API instead of the web UI.
        // groups:id,name — same eager-load DoctorPrintController.php (the
        // web roster print) already uses, needed here so the Flutter
        // roster PDF can show each doctor's group without an N+1.
        $query = Doctor::with(['educationType', 'stage', 'academicSession:id,name', 'groups:id,name']);
        $query = ScopeHelper::scopeEducationTypes($query, $request->user(), 'education_type_id');
        $query = ScopeHelper::scopeStages($query, $request->user(), 'stage_id');
        $query = ScopeHelper::scopeAcademicSessions($query, $request->user());

        // Doctors are enrolled per academic session; a client can pass an
        // explicit academic_session_id or all_sessions=1 (matches the web
        // list's "عرض جميع الفصول الدراسية" toggle).
        $sessionId = $request->integer('academic_session_id') ?: AcademicSessionHelper::resolveId();
        if ($sessionId && ! $request->boolean('all_sessions')) {
            $query->where(fn ($q) => $q
                ->where('academic_session_id', $sessionId)
                ->orWhereNull('academic_session_id'));
        }

        $doctors = $query
            // Cascading education-type/stage filters, matching the web
            // admin's own DoctorController::index() (its Doctors/Index.vue
            // narrows the stage dropdown to the chosen education type
            // client-side — these two clauses are what actually apply the
            // filter server-side, and the Flutter app was previously
            // missing both, only ever sending `search`).
            ->when($request->integer('education_type_id'), fn ($q, $id) => $q->where('education_type_id', $id))
            ->when($request->integer('stage_id'), fn ($q, $id) => $q->where('stage_id', $id))
            // The orWhere must be nested — unnested it escapes the scope and
            // session filters above, leaking doctors the caller may not see
            // (the same bug fixed earlier in the web controller).
            ->when($request->string('search')->toString(), function ($query, $search) {
                $query->where(function ($q) use ($search) {
                    $q->where('name', 'like', "%{$search}%")
                        ->orWhere('email', 'like', "%{$search}%")
                        // The web controller already searches username too;
                        // this one was missing it — small found parity gap,
                        // fixed alongside since it's the same clause.
                        ->orWhere('username', 'like', "%{$search}%");
                });
            })
            ->orderBy('name');

        // Rows per page, as on the web list (2026-10-18, by request): 15,
        // 25, 50, 75, 100 or all; anything else falls back to 15.
        $perPage = $request->string('per_page')->toString();
        $perPage = $perPage === 'all'
            ? max(1, (clone $doctors)->count())
            : (in_array((int) $perPage, [15, 25, 50, 75, 100], true) ? (int) $perPage : 15);

        return DoctorResource::collection($doctors->paginate($perPage))->response();
    }

    /**
     * Resolves a scanned NFC tag's hardware UID to a doctor — same
     * normalization as `validateDoctor()` below. A lighter, reusable twin
     * of `Api\TaskProgressController::nfcScan()`: that one also runs
     * `PendingTaskFinder` to offer a direct task-start shortcut, which is
     * irrelevant here (the doctors/groups admin lists just need "which
     * doctor is this card?", not their pending tasks) — added here rather
     * than making `doctors_admin`/`groups_admin` depend on the
     * `task_progress_admin` feature for an unrelated lookup.
     */
    public function nfcLookup(Request $request): JsonResponse
    {
        $validated = $request->validate(['tag_id' => ['required', 'string']]);
        $tagId = strtoupper(trim($validated['tag_id']));

        $doctor = Doctor::where('nfc_tag_id', $tagId)->with(['educationType', 'stage'])->first();

        if (! $doctor) {
            return response()->json(['message' => 'لا يوجد طبيب مرتبط بهذه البطاقة.'], 404);
        }

        return (new DoctorResource($doctor))->response();
    }

    public function show(Doctor $doctor): JsonResponse
    {
        $doctor->load(['educationType', 'stage', 'groups']);

        return (new DoctorResource($doctor))->response();
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $this->validateDoctor($request);
        // Left blank: generate one. Either way it goes to the new doctor by email.
        $plainPassword = $validated['password'] ?? null ?: CredentialMailer::generatePassword();
        $validated['password'] = Hash::make($plainPassword);

        // Defaults to the active session, as in the web controller.
        $validated['academic_session_id'] ??= AcademicSessionHelper::resolveId();

        if ($request->hasFile('profile_image')) {
            $validated['profile_image'] = $request->file('profile_image')->store('doctors', 'public');
        }

        $doctor = Doctor::create($validated);
        CredentialMailer::queueWelcome('doctor', $doctor->email, $doctor->name, $doctor->username, $plainPassword);

        return (new DoctorResource($doctor))->response()->setStatusCode(201);
    }

    public function update(Request $request, Doctor $doctor): JsonResponse
    {
        $validated = $this->validateDoctor($request, $doctor->id);

        if (! empty($validated['password'])) {
            $validated['password'] = Hash::make($validated['password']);
        } else {
            unset($validated['password']);
        }

        if ($request->hasFile('profile_image')) {
            if ($doctor->profile_image) {
                Storage::disk('public')->delete($doctor->profile_image);
            }
            $validated['profile_image'] = $request->file('profile_image')->store('doctors', 'public');
        }

        $doctor->update($validated);

        return (new DoctorResource($doctor))->response();
    }

    public function destroy(Doctor $doctor): JsonResponse
    {
        if ($linked = LinkedRecords::message($doctor)) {
            return response()->json(['message' => $linked, 'linked' => LinkedRecords::for($doctor)], 422);
        }

        // Archived, so the photo stays with the record.
        $doctor->delete();

        return response()->json(null, 204);
    }

    /**
     * Archive several doctors at once — the app's twin of the web's
     * doctors.destroy-many (2026-10-17): linked doctors are skipped and
     * named, the rest archived.
     */
    public function destroyMany(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'ids' => ['required', 'array'],
            'ids.*' => ['integer', 'exists:doctors,id'],
        ]);

        $blocked = [];
        $archived = 0;
        foreach (Doctor::whereIn('id', $validated['ids'])->get() as $doctor) {
            if ($linked = LinkedRecords::message($doctor)) {
                $blocked[] = "{$doctor->name}: {$linked}";

                continue;
            }
            $doctor->delete();
            $archived++;
        }

        return response()->json([
            'archived' => $archived,
            'blocked' => $blocked,
            'message' => "تمت أرشفة {$archived} طبيب.",
        ]);
    }

    private function validateDoctor(Request $request, ?int $doctorId = null): array
    {
        // Same normalization as the web twin (`DoctorController::validateDoctor()`)
        // so a tag scanned in Flutter and one typed on the web collide
        // predictably against the unique constraint. Empty string must
        // become null — see that method's comment for why.
        if ($request->filled('nfc_tag_id')) {
            $request->merge(['nfc_tag_id' => strtoupper(trim($request->string('nfc_tag_id')))]);
        } elseif ($request->has('nfc_tag_id')) {
            $request->merge(['nfc_tag_id' => null]);
        }

        return $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'username' => ['required', 'string', 'max:100', Rule::unique('doctors', 'username')->ignore($doctorId)],
            'email' => ['required', 'email', 'max:250', Rule::unique('doctors', 'email')->ignore($doctorId)],
            'phone' => ['nullable', 'string', 'max:50'],
            'education_type_id' => ['required', 'exists:education_types,id'],
            'stage_id' => ['required', 'exists:stages,id'],
            // Optional on create too: blank means "generate one" (see store()).
            'password' => ['nullable', 'string', 'min:6'],
            'profile_image' => ['nullable', 'image', 'max:2048'],
            'academic_session_id' => ['nullable', 'exists:academic_sessions,id'],
            'nfc_tag_id' => ['nullable', 'string', 'max:64', Rule::unique('doctors', 'nfc_tag_id')->ignore($doctorId)],
        ]);
    }
}
