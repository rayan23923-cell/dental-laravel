<?php

namespace App\Http\Controllers;

use App\Models\AcademicSession;
use App\Models\CaseSheetType;
use App\Models\Department;
use App\Models\EducationType;
use App\Models\RegisterDay;
use App\Models\Service;
use App\Models\Stage;
use App\Models\Task;
use App\Services\ScopeHelper;
use App\Support\ExcelTransfer;
use App\Support\TaskScoring;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Export services (with prices) and tasks to Excel and import them back,
 * so the hosted setup can be carried to the offline system (2026-10-18,
 * by request). An import adds what is missing and updates what matches
 * (a service by name; a task by title, stage, department and session),
 * creating any education type, stage, department or registration day it
 * names that does not exist yet.
 */
class ExcelTransferController extends Controller
{
    private const SERVICE_HEADERS = ['Name', 'Price', 'Student Discount %', 'Register Days'];

    private const TASK_HEADERS = [
        'Title', 'Education Type', 'Stage', 'Department', 'Department Pass %', 'Case Sheet Type',
        'Academic Session', 'Required Count', 'Grade', 'Is Required', 'Notes', 'Scoring', 'Register Days',
    ];

    public function exportServices(): StreamedResponse
    {
        $rows = Service::with('days')->orderBy('name')->get()->map(fn (Service $s) => [
            $s->name, $s->price, $s->student_discount_percent, $s->days->sortBy('sort_order')->pluck('name')->implode(', '),
        ]);

        return ExcelTransfer::download(self::SERVICE_HEADERS, $rows, 'services');
    }

    public function importServices(Request $request): RedirectResponse
    {
        $request->validate(['file' => ['required', 'file', 'mimes:xlsx,xls,csv']]);

        $added = $updated = 0;
        DB::transaction(function () use ($request, &$added, &$updated) {
            foreach (ExcelTransfer::read($request->file('file')) as $row) {
                $name = $row['name'] ?? '';
                if ($name === '') {
                    continue;
                }
                $price = $row['price'] ?? '';
                $service = Service::firstOrNew(['name' => $name]);
                $service->exists ? $updated++ : $added++;
                $service->price = is_numeric($price) ? $price : null;
                // Student discount (2026-10-25): an older sheet without the column keeps the current value.
                $discount = $row['student discount %'] ?? '';
                if (is_numeric($discount)) {
                    $service->student_discount_percent = max(0, min(100, (float) $discount));
                }
                $service->save();
                if (array_key_exists('register days', $row)) {
                    $service->days()->sync($this->dayIds($row['register days']));
                }
            }
        });

        return back()->with('success', "تم استيراد الخدمات: {$added} جديدة، {$updated} محدثة.");
    }

    public function exportTasks(Request $request): StreamedResponse
    {
        $query = Task::with(['stage.educationType', 'department', 'caseSheetType', 'academicSession', 'days'])->orderBy('id');
        ScopeHelper::scopeStages($query, $request->user(), 'stage_id');
        ScopeHelper::scopeDepartments($query, $request->user(), 'department_id');

        $rows = $query->get()->map(fn (Task $t) => [
            $t->title,
            $t->stage?->educationType?->name,
            $t->stage?->name,
            $t->department?->name,
            $t->department?->pass_percent,
            $t->caseSheetType?->type_code,
            $t->academicSession?->name,
            $t->required_count,
            $t->grade,
            $t->is_required ? 1 : 0,
            $t->notes,
            $t->scoring ? json_encode($t->scoring, JSON_UNESCAPED_UNICODE) : '',
            $t->days->sortBy('sort_order')->pluck('name')->implode(', '),
        ]);

        return ExcelTransfer::download(self::TASK_HEADERS, $rows, 'tasks');
    }

    public function importTasks(Request $request): RedirectResponse
    {
        $request->validate(['file' => ['required', 'file', 'mimes:xlsx,xls,csv']]);

        $added = $updated = 0;
        $problems = [];
        DB::transaction(function () use ($request, &$added, &$updated, &$problems) {
            foreach (ExcelTransfer::read($request->file('file')) as $i => $row) {
                $line = $i + 2;
                $title = $row['title'] ?? '';
                $sheetType = $row['case sheet type'] ?? '';
                $type = CaseSheetType::where('type_code', $sheetType)->orWhere('name_ar', $sheetType)->orWhere('name_en', $sheetType)->first();
                if ($title === '' || ($row['stage'] ?? '') === '' || ($row['department'] ?? '') === '' || ! $type) {
                    $problems[] = "سطر {$line}: ".($type || $title === '' ? 'العنوان والمرحلة والقسم مطلوبة' : "نوع الحالة «{$sheetType}» غير موجود");

                    continue;
                }

                $educationType = ($row['education type'] ?? '') !== '' ? EducationType::firstOrCreate(['name' => $row['education type']]) : null;
                $stage = Stage::firstOrCreate(['name' => $row['stage'], 'education_type_id' => $educationType?->id]);
                $department = Department::firstOrCreate(
                    ['name' => $row['department'], 'stage_id' => $stage->id],
                    ['education_type_id' => $stage->education_type_id],
                );
                if (is_numeric($row['department pass %'] ?? null)) {
                    $department->update(['pass_percent' => $row['department pass %']]);
                }
                $session = ($row['academic session'] ?? '') !== '' ? AcademicSession::where('name', $row['academic session'])->first() : null;
                $scoring = json_decode($row['scoring'] ?? '', true);

                $task = Task::firstOrNew([
                    'title' => $title, 'stage_id' => $stage->id, 'department_id' => $department->id,
                    'academic_session_id' => $session?->id,
                ]);
                $task->exists ? $updated++ : $added++;
                $task->fill([
                    'case_sheet_type_id' => $type->id,
                    'required_count' => max(1, (int) ($row['required count'] ?? 1)),
                    'grade' => is_numeric($row['grade'] ?? null) ? $row['grade'] : 0,
                    'is_required' => ! in_array(strtolower($row['is required'] ?? '1'), ['0', 'no', 'false', 'لا'], true),
                    'notes' => $row['notes'] ?? '',
                    'scoring' => is_array($scoring) ? TaskScoring::normalize($scoring) : null,
                ])->save();
                if (array_key_exists('register days', $row)) {
                    $task->days()->sync($this->dayIds($row['register days']));
                }
            }
        });

        $message = "تم استيراد المهام: {$added} جديدة، {$updated} محدثة.";
        if ($problems) {
            return back()->with('success', $message)->with('error', "لم تُستورد هذه الأسطر:\n".implode("\n", array_slice($problems, 0, 30)));
        }

        return back()->with('success', $message);
    }

    /** @return array<int, int> */
    private function dayIds(?string $names): array
    {
        return collect(ExcelTransfer::names($names))->map(fn ($n) => RegisterDay::firstOrCreate(['name' => $n])->id)->all();
    }
}
