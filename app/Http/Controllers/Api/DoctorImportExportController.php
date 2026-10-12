<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Doctor;
use App\Services\CredentialMailer;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use PhpOffice\PhpSpreadsheet\IOFactory;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Same import/export logic as the web DoctorImportExportController, with a
 * JSON response for import instead of a redirect+flash. See that class's
 * docblock for the deliberate difference from the original app's importer
 * (reads all 5 template columns instead of silently only using 2).
 */
class DoctorImportExportController extends Controller
{
    public function template(): StreamedResponse
    {
        return app(\App\Http\Controllers\DoctorImportExportController::class)->template();
    }

    public function export(Request $request): StreamedResponse
    {
        return app(\App\Http\Controllers\DoctorImportExportController::class)->export($request);
    }

    public function import(Request $request): JsonResponse
    {
        $request->validate([
            'file' => ['required', 'file', 'mimes:xlsx,xls,csv'],
            'education_type_id' => ['required', 'exists:education_types,id'],
            'stage_id' => ['required', 'exists:stages,id'],
            // Blank: every imported doctor gets their own generated password.
            'default_password' => ['nullable', 'string', 'min:6'],
        ]);

        $spreadsheet = IOFactory::load($request->file('file')->getRealPath());
        $rows = $spreadsheet->getActiveSheet()->toArray();

        if (! $request->filled('default_password') && $missing = CredentialMailer::unreachableImportRows($rows)) {
            throw \Illuminate\Validation\ValidationException::withMessages([
                'default_password' => 'هؤلاء بلا إيميل صالح فلن تصلهم كلمة المرور المولدة. أدخل كلمة مرور افتراضية أو أضف إيميلاتهم: '
                    .implode('، ', array_slice($missing, 0, 20)).(count($missing) > 20 ? ' …' : ''),
            ]);
        }

        $imported = 0;
        $skipped = 0;
        $queued = 0;

        foreach ($rows as $index => $row) {
            if ($index === 0) {
                continue;
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

            $plainPassword = $request->filled('default_password')
                ? (string) $request->string('default_password')
                : CredentialMailer::generatePassword();

            $doctor = Doctor::create([
                'name' => $name !== '' ? $name : $username,
                'username' => $username,
                'email' => trim((string) $email) ?: "{$username}@placeholder.local",
                'phone' => trim((string) $phone) ?: null,
                'education_type_id' => $request->integer('education_type_id'),
                'stage_id' => $request->integer('stage_id'),
                'password' => Hash::make($plainPassword),
            ]);

            $imported++;
            if (CredentialMailer::queueWelcome('doctor', $doctor->email, $doctor->name, $doctor->username, $plainPassword)) {
                $queued++;
            }
        }

        return response()->json(['imported' => $imported, 'skipped' => $skipped, 'emails_queued' => $queued]);
    }
}
