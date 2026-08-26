<?php

namespace App\Http\Controllers;

use App\Models\ClinicSetting;
use App\Models\Doctor;
use App\Services\AcademicSessionHelper;
use App\Services\ScopeHelper;
use Illuminate\Contracts\View\View;
use Illuminate\Http\Request;

/**
 * Printable doctor views — port of admin/print_doctors.php (a roster
 * grouped by stage, with a summary box and the clinic logo as a watermark)
 * and admin/print_doctor_card.php (a single doctor's ID card).
 *
 * Rendered as Blade rather than Inertia pages on purpose: these are
 * standalone print documents opened in a new tab, with their own
 * university/college letterhead and `@media print` rules — wrapping them in
 * the app shell would print the navigation too.
 *
 * The roster honours the same filters as the doctors list (education type,
 * stage, search) plus an explicit id list, so "طباعة الفلتر" and
 * "طباعة المحدد" both work off one endpoint, as in the original.
 */
class DoctorPrintController extends Controller
{
    public function roster(Request $request): View
    {
        $query = Doctor::with(['educationType:id,name', 'stage:id,name', 'groups:id,name']);
        $query = ScopeHelper::scopeEducationTypes($query, $request->user(), 'education_type_id');
        $query = ScopeHelper::scopeStages($query, $request->user(), 'stage_id');
        $query = ScopeHelper::scopeAcademicSessions($query, $request->user());

        $ids = array_filter(explode(',', $request->string('ids')->toString()));

        // "طباعة الفلتر" must print what the screen shows, so the roster
        // repeats the list's academic-session filter. Skipped when explicit
        // ids are passed ("طباعة المحدد" prints exactly the ticked rows, which
        // the user may have selected while viewing all sessions).
        $sessionId = AcademicSessionHelper::resolveId();
        if ($sessionId && ! $ids && ! $request->boolean('all_sessions')) {
            $query->where(fn ($q) => $q
                ->where('academic_session_id', $sessionId)
                ->orWhereNull('academic_session_id'));
        }

        $doctors = $query
            ->when($ids, fn ($q) => $q->whereIn('id', $ids))
            ->when($request->integer('education_type_id'), fn ($q, $id) => $q->where('education_type_id', $id))
            ->when($request->integer('stage_id'), fn ($q, $id) => $q->where('stage_id', $id))
            ->when($request->string('search')->toString(), fn ($q, $s) => $q->where(function ($q2) use ($s) {
                $q2->where('name', 'like', "%{$s}%")
                    ->orWhere('email', 'like', "%{$s}%")
                    ->orWhere('username', 'like', "%{$s}%");
            }))
            ->orderBy('name')
            ->get();

        // The original groups the roster by stage and prints a per-stage
        // heading with its own count.
        $byStage = $doctors->groupBy(fn ($d) => $d->stage?->name ?? 'غير محدد');

        return view('print.doctors', [
            'settings' => ClinicSetting::current(),
            'byStage' => $byStage,
            'total' => $doctors->count(),
            // "مراحل متعددة" when the selection spans more than one stage,
            // matching the original's header logic.
            'stageLabel' => $byStage->count() === 1 ? $byStage->keys()->first() : 'مراحل متعددة',
        ]);
    }

    public function card(Doctor $doctor): View
    {
        $doctor->load(['educationType:id,name', 'stage:id,name', 'groups:id,name']);

        return view('print.doctor-card', [
            'settings' => ClinicSetting::current(),
            'doctor' => $doctor,
        ]);
    }
}
