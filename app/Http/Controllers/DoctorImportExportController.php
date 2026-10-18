<?php

namespace App\Http\Controllers;

use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\Stage;
use App\Services\CredentialMailer;
use App\Support\ExcelTransfer;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;
use Inertia\Inertia;
use Inertia\Response;
use PhpOffice\PhpSpreadsheet\Cell\Coordinate;
use PhpOffice\PhpSpreadsheet\IOFactory;
use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Style\Alignment;
use PhpOffice\PhpSpreadsheet\Style\Fill;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Doctor bulk import/export via Excel (PhpSpreadsheet), matching the
 * original app's feature (admin/import_doctors.php, export_doctors_excel.php,
 * generate_doctor_template.php).
 *
 * One deliberate improvement over the original: its template promised 5
 * columns (first name, last name, email, phone, username — see
 * generate_doctor_template.php) but the actual importer
 * (admin/import_doctors.php) only ever read columns 0–1 (username, phone)
 * and fabricated every doctor's name as "طبيب {username}", silently
 * discarding the email/name columns the template told users to fill in.
 * That's an incomplete implementation in the original, not a competing
 * source of truth (unlike the appointments.doctor_id case) — this rebuild
 * reads all 5 columns as the template actually promises.
 */
class DoctorImportExportController extends Controller
{
    private const EXPORT_HEADERS = ['Name', 'Username', 'Email', 'Phone', 'Stage', 'Education Type', 'Created At'];

    public function showImport(): Response
    {
        return Inertia::render('Doctors/Import', [
            'educationTypes' => EducationType::orderBy('name')->get(),
            'stages' => Stage::orderBy('name')->get(),
        ]);
    }

    public function template(): StreamedResponse
    {
        $spreadsheet = new Spreadsheet();
        $sheet = $spreadsheet->getActiveSheet();

        $headers = ['First Name', 'Last Name', 'Email', 'Phone', 'Username'];
        foreach ($headers as $i => $header) {
            $sheet->setCellValue(Coordinate::stringFromColumnIndex($i + 1).'1', $header);
        }
        $sheet->getStyle('A1:E1')->applyFromArray([
            'font' => ['bold' => true, 'color' => ['rgb' => 'FFFFFF']],
            'fill' => ['fillType' => Fill::FILL_SOLID, 'startColor' => ['rgb' => '4472C4']],
            'alignment' => ['horizontal' => Alignment::HORIZONTAL_CENTER],
        ]);

        $sample = [
            ['Ahmed', 'Mohamed', 'ahmed.mohamed@example.com', '0501234567', 'ahmed_mohamed'],
            ['Fatima', 'Ali', 'fatima.ali@example.com', '0509876543', 'fatima_ali'],
        ];
        foreach ($sample as $rowIndex => $row) {
            foreach ($row as $colIndex => $value) {
                $sheet->setCellValue(Coordinate::stringFromColumnIndex($colIndex + 1).($rowIndex + 2), $value);
            }
        }

        foreach (range('A', 'E') as $col) {
            $sheet->getColumnDimension($col)->setAutoSize(true);
        }

        return $this->streamSpreadsheet($spreadsheet, 'doctors_import_template.xlsx');
    }

    public function import(Request $request): RedirectResponse
    {
        $request->validate([
            'file' => ['required', 'file', 'mimes:xlsx,xls,csv'],
            'education_type_id' => ['required', 'exists:education_types,id'],
            'stage_id' => ['required', 'exists:stages,id'],
            // Blank: every imported doctor gets their own generated password.
            'default_password' => ['nullable', 'string', 'min:6'],
        ]);

        $spreadsheet = IOFactory::load($request->file('file')->getRealPath());
        $rows = self::fromExportLayout($spreadsheet->getActiveSheet()->toArray());

        if (! $request->filled('default_password') && $missing = CredentialMailer::unreachableImportRows($rows)) {
            throw ValidationException::withMessages([
                'default_password' => 'هؤلاء بلا إيميل صالح فلن تصلهم كلمة المرور المولدة. أدخل كلمة مرور افتراضية أو أضف إيميلاتهم: '
                    .implode('، ', array_slice($missing, 0, 20)).(count($missing) > 20 ? ' …' : ''),
            ]);
        }

        $imported = 0;
        $skipped = 0;
        $queued = 0;

        foreach ($rows as $index => $row) {
            if ($index === 0) {
                continue; // header row
            }

            [$firstName, $lastName, $email, $phone, $username, $stageName, $typeName] = array_pad($row, 7, null);
            $username = trim((string) $username);

            if ($username === '') {
                continue;
            }

            if (Doctor::where('username', $username)->exists()) {
                $skipped++;

                continue;
            }

            $name = trim(($firstName ?? '').' '.($lastName ?? ''));

            $plainPassword = $request->filled('default_password')
                ? (string) $request->string('default_password')
                : CredentialMailer::generatePassword();

            // An exported file names each doctor's own stage; one this
            // system doesn't have falls back to the stage chosen on the form.
            $stage = self::stageNamed($stageName, $typeName);

            $doctor = Doctor::create([
                'name' => $name !== '' ? $name : $username,
                'username' => $username,
                'email' => trim((string) $email) ?: "{$username}@placeholder.local",
                'phone' => trim((string) $phone) ?: null,
                'education_type_id' => $stage?->education_type_id ?? $request->integer('education_type_id'),
                'stage_id' => $stage?->id ?? $request->integer('stage_id'),
                'password' => Hash::make($plainPassword),
            ]);

            $imported++;
            if (CredentialMailer::queueWelcome('doctor', $doctor->email, $doctor->name, $doctor->username, $plainPassword)) {
                $queued++;
            }
        }

        return redirect()->route('doctors.index')
            ->with('success', "Imported {$imported} doctors".($skipped ? ", skipped {$skipped} (username already exists)" : '')
                .". {$queued} login emails queued (sent gradually within the daily limit).");
    }

    /**
     * Without passwords (2026-10-18, by request); the columns are the
     * ones import() reads back, so the file moves doctors to the offline
     * system (see fromExportLayout()).
     */
    public function export(Request $request): StreamedResponse
    {
        $doctors = Doctor::with(['stage', 'educationType'])
            ->when($request->integer('stage_id'), fn ($q, $id) => $q->where('stage_id', $id))
            ->when($request->integer('education_type_id'), fn ($q, $id) => $q->where('education_type_id', $id))
            ->orderBy('id')
            ->get()
            ->map(fn (Doctor $d) => [
                $d->name, $d->username, $d->email, $d->phone, $d->stage?->name,
                $d->educationType?->name ?? $d->stage?->educationType?->name, $d->created_at?->format('Y-m-d'),
            ]);

        return ExcelTransfer::download(self::EXPORT_HEADERS, $doctors, 'doctors_export');
    }

    /**
     * Rows of an exported file in the template's layout (first name, last
     * name, email, phone, username) plus stage and education type names.
     * Any other file is returned as it is.
     */
    private static function fromExportLayout(array $rows): array
    {
        $headers = array_map(fn ($h) => ExcelTransfer::key($h), $rows[0] ?? []);
        if (! in_array('name', $headers, true) || ! in_array('username', $headers, true)) {
            return $rows;
        }
        $col = array_flip($headers);
        $get = fn ($row, $key) => isset($col[$key]) ? ($row[$col[$key]] ?? null) : null;

        return array_map(fn ($row) => [
            $get($row, 'name'), '', $get($row, 'email'), $get($row, 'phone'),
            $get($row, 'username'), $get($row, 'stage'), $get($row, 'education type'),
        ], $rows);
    }

    private static function stageNamed(?string $stage, ?string $type): ?Stage
    {
        $stage = trim((string) $stage);
        if ($stage === '') {
            return null;
        }

        return Stage::where('name', $stage)
            ->when(trim((string) $type) !== '', fn ($q) => $q->whereHas('educationType', fn ($t) => $t->where('name', trim((string) $type))))
            ->first();
    }

    private function streamSpreadsheet(Spreadsheet $spreadsheet, string $filename): StreamedResponse
    {
        $writer = IOFactory::createWriter($spreadsheet, 'Xlsx');

        return response()->streamDownload(function () use ($writer) {
            $writer->save('php://output');
        }, $filename, [
            'Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ]);
    }
}
