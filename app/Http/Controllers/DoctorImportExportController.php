<?php

namespace App\Http\Controllers;

use App\Models\Doctor;
use App\Models\EducationType;
use App\Models\Stage;
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
            'default_password' => ['required', 'string', 'min:6'],
        ]);

        $spreadsheet = IOFactory::load($request->file('file')->getRealPath());
        $rows = $spreadsheet->getActiveSheet()->toArray();

        $imported = 0;
        $skipped = 0;

        foreach ($rows as $index => $row) {
            if ($index === 0) {
                continue; // header row
            }

            [$firstName, $lastName, $email, $phone, $username] = array_pad($row, 5, null);
            $username = trim((string) $username);

            if ($username === '') {
                continue;
            }

            if (Doctor::where('username', $username)->exists()) {
                $skipped++;

                continue;
            }

            $name = trim(($firstName ?? '').' '.($lastName ?? ''));

            Doctor::create([
                'name' => $name !== '' ? $name : $username,
                'username' => $username,
                'email' => trim((string) $email) ?: "{$username}@placeholder.local",
                'phone' => trim((string) $phone) ?: null,
                'education_type_id' => $request->integer('education_type_id'),
                'stage_id' => $request->integer('stage_id'),
                'password' => Hash::make($request->string('default_password')),
            ]);

            $imported++;
        }

        return redirect()->route('doctors.index')
            ->with('success', "Imported {$imported} doctors".($skipped ? ", skipped {$skipped} (username already exists)" : '').'.');
    }

    public function export(Request $request): StreamedResponse
    {
        $doctors = Doctor::with(['stage', 'educationType'])
            ->when($request->integer('stage_id'), fn ($q, $id) => $q->where('stage_id', $id))
            ->when($request->integer('education_type_id'), fn ($q, $id) => $q->where('education_type_id', $id))
            ->orderBy('id')
            ->get();

        $spreadsheet = new Spreadsheet();
        $sheet = $spreadsheet->getActiveSheet();

        $headers = ['Name', 'Stage', 'Education Type', 'Username', 'Email', 'Phone', 'Created At'];
        foreach ($headers as $i => $header) {
            $sheet->setCellValue(Coordinate::stringFromColumnIndex($i + 1).'1', $header);
        }
        $sheet->getStyle('A1:G1')->getFont()->setBold(true);

        foreach ($doctors as $i => $doctor) {
            $row = $i + 2;
            $sheet->setCellValue("A{$row}", $doctor->name);
            $sheet->setCellValue("B{$row}", $doctor->stage?->name);
            $sheet->setCellValue("C{$row}", $doctor->educationType?->name);
            $sheet->setCellValue("D{$row}", $doctor->username);
            $sheet->setCellValue("E{$row}", $doctor->email);
            $sheet->setCellValue("F{$row}", $doctor->phone);
            $sheet->setCellValue("G{$row}", $doctor->created_at?->format('Y-m-d'));
        }

        foreach (range('A', 'G') as $col) {
            $sheet->getColumnDimension($col)->setAutoSize(true);
        }

        return $this->streamSpreadsheet($spreadsheet, 'doctors_export_'.now()->format('Ymd_His').'.xlsx');
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
