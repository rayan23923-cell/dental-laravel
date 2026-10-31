<?php

namespace App\Http\Controllers;

use App\Models\ClinicSetting;
use App\Services\BulkCredentials;
use App\Support\ExcelTransfer;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Validation\ValidationException;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Bulk accounts and login emails, super admins only (2026-10-31, by
 * request). Done on the hosting, which emails everyone and hands back a
 * login file; the offline clinic server has no internet, so that file is
 * uploaded there to save the same accounts and passwords. See
 * BulkCredentials.
 */
class BulkCredentialsController extends Controller
{
    public const DEFAULT_LOGIN_URL = 'https://clinic.lan/login';

    public const DEFAULT_ALT_URL = 'https://192.168.68.52/login';

    public function index(): Response
    {
        return Inertia::render('Users/BulkCredentials', [
            'stages' => BulkCredentials::stageSummary(),
            'mailConfigured' => (bool) ClinicSetting::query()->find(1)?->mailConfigured(),
            'defaults' => ['login_url' => self::DEFAULT_LOGIN_URL, 'alt_url' => self::DEFAULT_ALT_URL],
        ]);
    }

    public function teachers(Request $request): JsonResponse
    {
        $data = $request->validate([
            'file' => ['required', 'file', 'max:5120'],
            'send_email' => ['required', 'boolean'],
            ...$this->linkRules(),
        ]);

        $rows = array_map(fn ($r) => self::nameAndEmail($r), $this->readRows($request->file('file')));
        $result = BulkCredentials::importTeachers($rows, $this->mail($data));

        return response()->json([
            'credentials' => $result['created'],
            'count' => count($result['created']),
            'skipped' => $result['skipped'],
        ]);
    }

    public function doctors(Request $request): JsonResponse
    {
        $data = $request->validate([
            'stage_ids' => ['required', 'array', 'min:1'],
            'stage_ids.*' => ['integer', 'exists:stages,id'],
            'send_email' => ['required', 'boolean'],
            ...$this->linkRules(),
        ]);

        $result = BulkCredentials::resetDoctors($data['stage_ids'], $this->mail($data));

        return response()->json([
            'credentials' => $result['reset'],
            'count' => count($result['reset']),
            'no_email' => $result['no_email'],
        ]);
    }

    /** The offline side: save the accounts and passwords of a login file made on the hosting. */
    public function apply(Request $request): JsonResponse
    {
        $request->validate(['file' => ['required', 'file', 'max:5120']]);

        $rows = $this->readRows($request->file('file'));
        if ($rows && ! isset($rows[0]['username'], $rows[0]['password'])) {
            throw ValidationException::withMessages(['file' => 'هذا ليس ملف بيانات الدخول (يجب أن يحوي الأعمدة username و password).']);
        }

        return response()->json(BulkCredentials::applyFile($rows));
    }

    private function linkRules(): array
    {
        return [
            'login_url' => ['nullable', 'url', 'max:255'],
            'alt_url' => ['nullable', 'url', 'max:255'],
        ];
    }

    private function mail(array $data): ?array
    {
        return $data['send_email'] ? BulkCredentials::links($data['login_url'] ?? null, [$data['alt_url'] ?? '']) : null;
    }

    /**
     * A CSV (as the page downloads it) or an Excel sheet, as rows keyed by
     * the lower-cased header.
     *
     * @return list<array<string, string>>
     */
    private function readRows(UploadedFile $file): array
    {
        if (! in_array(strtolower($file->getClientOriginalExtension()), ['csv', 'txt'], true)) {
            return array_values(ExcelTransfer::read($file));
        }

        $handle = fopen($file->getRealPath(), 'r');
        $headers = null;
        $rows = [];
        while (($row = fgetcsv($handle)) !== false) {
            if ($headers === null) {
                $row[0] = preg_replace('/^\x{FEFF}/u', '', (string) ($row[0] ?? ''));
                $headers = array_map(fn ($h) => ExcelTransfer::key($h), $row);

                continue;
            }
            $assoc = [];
            foreach ($headers as $i => $h) {
                $assoc[$h] = trim((string) ($row[$i] ?? ''));
            }
            if (implode('', $assoc) !== '') {
                $rows[] = $assoc;
            }
        }
        fclose($handle);

        return $rows;
    }

    /**
     * A teachers row whatever its headers: the email is the cell holding
     * one, the name the "name"/"الاسم…" column or else the first other cell.
     *
     * @return array{0: string, 1: string}
     */
    public static function nameAndEmail(array $row): array
    {
        $email = '';
        $name = '';
        foreach ($row as $key => $value) {
            if ($email === '' && filter_var($value, FILTER_VALIDATE_EMAIL)) {
                $email = $value;
            } elseif ($name === '' && (str_contains($key, 'name') || str_contains($key, 'اسم'))) {
                $name = $value;
            }
        }
        if ($name === '') {
            foreach ($row as $value) {
                if ($value !== '' && $value !== $email && ! is_numeric($value)) {
                    $name = $value;
                    break;
                }
            }
        }

        return [$name, $email];
    }
}
