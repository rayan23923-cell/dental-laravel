<?php

namespace App\Http\Controllers;

use App\Models\AcademicSession;
use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\Stage;
use App\Services\AcademicSessionHelper;
use App\Services\CredentialMailer;
use App\Services\ScopeHelper;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use Inertia\Inertia;
use Inertia\Response;

class DoctorController extends Controller
{
    public function index(Request $request): Response
    {
        // Matches admin/ajax/doctors_crud.php: education-type and stage
        // scope both apply (AND) for any non-super_admin user with rows in
        // user_allowed_education_types / user_allowed_stages.
        $query = Doctor::with(['educationType', 'stage', 'academicSession:id,name']);
        $query = ScopeHelper::scopeEducationTypes($query, $request->user(), 'education_type_id');
        $query = ScopeHelper::scopeStages($query, $request->user(), 'stage_id');
        // Which years this user's account is permitted to see at all — a
        // permission, independent of the "which session is currently being
        // viewed" filter just below. Both apply together.
        $query = ScopeHelper::scopeAcademicSessions($query, $request->user());

        // Doctors belong to an academic session (see the 2026_08_19_120000
        // migration). Session-less doctors stay visible under every session,
        // matching how session-less groups and tasks behave elsewhere.
        $session = AcademicSessionHelper::resolve();
        $sessionId = $session?->id;
        if ($sessionId && ! $request->boolean('all_sessions')) {
            $query->where(fn ($q) => $q
                ->where('academic_session_id', $sessionId)
                ->orWhereNull('academic_session_id'));
        }

        // The original's page has an education-type filter and a stage
        // filter that cascades off it, alongside the search box.
        $doctors = $query
            ->when($request->integer('education_type_id'), fn ($q, $id) => $q->where('education_type_id', $id))
            ->when($request->integer('stage_id'), fn ($q, $id) => $q->where('stage_id', $id))
            ->when($request->string('search')->toString(), function ($query, $search) {
                $query->where(function ($q) use ($search) {
                    $q->where('name', 'like', "%{$search}%")
                        ->orWhere('email', 'like', "%{$search}%")
                        ->orWhere('username', 'like', "%{$search}%");
                });
            })
            ->orderBy('name')
            ->paginate(15)
            ->withQueryString();

        return Inertia::render('Doctors/Index', [
            'doctors' => $doctors,
            'educationTypes' => ScopeHelper::scopeEducationTypes(EducationType::query(), $request->user())->orderBy('name')->get(['id', 'name']),
            'stages' => ScopeHelper::scopeStages(Stage::query(), $request->user())->orderBy('name')->get(['id', 'name', 'education_type_id']),
            'filters' => $request->only('search', 'education_type_id', 'stage_id'),
            'currentSession' => $session?->only('id', 'name'),
            'allSessions' => $request->boolean('all_sessions'),
        ]);
    }

    /**
     * Ports the original's "حذف المحدد" bulk action on the doctors table
     * (its `deleteSelectedBtn`), which the previous port had no equivalent
     * of — deleting many doctors meant one confirm per row.
     */
    public function destroyMany(Request $request): RedirectResponse
    {
        $validated = $request->validate([
            'ids' => ['required', 'array'],
            'ids.*' => ['integer', 'exists:doctors,id'],
        ]);

        $doctors = Doctor::whereIn('id', $validated['ids'])->get();

        foreach ($doctors as $doctor) {
            if ($doctor->profile_image) {
                Storage::disk('public')->delete($doctor->profile_image);
            }
            $doctor->delete();
        }

        return back()->with('success', $doctors->count().' doctor(s) deleted.');
    }

    public function create(): Response
    {
        return Inertia::render('Doctors/Create', [
            'educationTypes' => EducationType::orderBy('name')->get(),
            'stages' => Stage::orderBy('name')->get(),
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        $validated = $this->validateDoctor($request);
        // Left blank: generate one. Either way it goes to the new doctor by email.
        $plainPassword = $validated['password'] ?? null ?: CredentialMailer::generatePassword();
        $validated['password'] = Hash::make($plainPassword);

        // A new doctor belongs to the session currently being worked in —
        // the same rule GroupController uses when creating a group, so a new
        // intake lands in the right academic year without extra input.
        $validated['academic_session_id'] ??= AcademicSessionHelper::resolveId();

        if ($request->hasFile('profile_image')) {
            $validated['profile_image'] = $request->file('profile_image')->store('doctors', 'public');
        }

        $doctor = Doctor::create($validated);
        CredentialMailer::queueWelcome('doctor', $doctor->email, $doctor->name, $doctor->username, $plainPassword);

        return redirect()->route('doctors.index')->with('success', 'Doctor added successfully.');
    }

    public function edit(Request $request, Doctor $doctor): Response
    {
        return Inertia::render('Doctors/Edit', [
            'doctor' => $doctor,
            'educationTypes' => EducationType::orderBy('name')->get(),
            'stages' => Stage::orderBy('name')->get(),
            // Editable so a doctor can be moved between academic years, and
            // so pre-existing session-less doctors can be assigned one.
            // Scoped the same as the other three dimensions elsewhere in
            // this controller — a restricted user shouldn't be offered a
            // year outside their own allowed scope to assign a doctor into.
            'academicSessions' => ScopeHelper::scopeAcademicSessions(AcademicSession::query(), $request->user(), 'id')
                ->orderByDesc('start_date')->get(['id', 'name']),
        ]);
    }

    public function update(Request $request, Doctor $doctor): RedirectResponse
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

        return redirect()->route('doctors.index')->with('success', 'Doctor updated successfully.');
    }

    public function destroy(Doctor $doctor): RedirectResponse
    {
        if ($doctor->profile_image) {
            Storage::disk('public')->delete($doctor->profile_image);
        }

        $doctor->delete();

        return redirect()->route('doctors.index')->with('success', 'Doctor deleted successfully.');
    }

    private function validateDoctor(Request $request, ?int $doctorId = null): array
    {
        // Normalized before validation so manual web entry and a
        // Flutter-scanned tag UID collide predictably against the unique
        // constraint regardless of entry path — see the migration's
        // docblock for why the stored form is uppercase hex, no separators.
        // An empty string must become null, not stay '' — a nullable+unique
        // column treats '' as a real, colliding value (unlike NULL, which
        // MySQL allows any number of), so a second doctor saved with a
        // blank field would otherwise fail with a confusing uniqueness error.
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
            // Only the edit form posts this; on create it's filled from the
            // session being worked in (see store()).
            'academic_session_id' => ['nullable', 'exists:academic_sessions,id'],
            'nfc_tag_id' => ['nullable', 'string', 'max:64', Rule::unique('doctors', 'nfc_tag_id')->ignore($doctorId)],
        ]);
    }
}
