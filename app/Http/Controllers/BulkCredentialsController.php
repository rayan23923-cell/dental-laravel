<?php

namespace App\Http\Controllers;

use App\Models\ClinicSetting;
use App\Models\Doctor;
use App\Services\BulkCredentials;
use App\Support\ExcelTransfer;
use Illuminate\Contracts\View\View;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Validation\ValidationException;
use Inertia\Inertia;
use Inertia\Response;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

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
            'defaults' => ['login_url' => self::DEFAULT_LOGIN_URL, 'alt_url' => self::DEFAULT_ALT_URL, 'wifi_name' => BulkCredentials::wifiName()],
            'files' => BulkCredentials::loginFiles(),
        ]);
    }

    /** A login file kept on this server (made here, or by the GitHub workflow). */
    public function download(string $name): BinaryFileResponse
    {
        $path = BulkCredentials::loginFilePath($name) ?? abort(404);

        return response()->download($path, $name, ['Content-Type' => 'text/csv; charset=UTF-8']);
    }

    /**
     * A login file as cards to print on A4 (10 per page, cut along the
     * dashed lines) and hand out (2026-11-01, by request).
     */
    public function cards(Request $request, string $name): View
    {
        $path = BulkCredentials::loginFilePath($name) ?? abort(404);
        $rows = $this->csvRows($path);

        $stages = Doctor::query()
            ->whereIn('username', collect($rows)->where('account_type', 'doctor')->pluck('username'))
            ->with('stage:id,name')->get(['username', 'stage_id'])
            ->mapWithKeys(fn ($d) => [$d->username => $d->stage?->name]);
        $cards = collect($rows)->map(fn ($r) => $r + [
            'label' => ($r['account_type'] ?? '') === 'doctor' ? ($stages[$r['username'] ?? ''] ?? 'طالب') : 'تدريسي',
        ])->sortBy([['label', 'asc'], ['name', 'asc']])->values();

        $setting = ClinicSetting::query()->find(1);

        return view('bulk-credentials-cards', [
            'cards' => $cards,
            'title' => $setting?->clinic_name ?: config('app.name'),
            'loginUrl' => 'https://clinic.lan',
            'altUrl' => 'https://192.168.68.52',
            // The page's field as it is now (?wifi=), else the name saved here.
            'wifiName' => mb_substr(trim((string) $request->query('wifi', BulkCredentials::wifiName())), 0, 64),
        ]);
    }

    public function destroy(string $name): RedirectResponse
    {
        $path = BulkCredentials::loginFilePath($name) ?? abort(404);
        unlink($path);

        return back();
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
        if ($result['created']) {
            BulkCredentials::saveLoginFile($result['created'], 'teachers-logins');
        }

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
        if ($result['reset']) {
            BulkCredentials::saveLoginFile($result['reset'], 'doctors-logins');
        }

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
            'wifi_name' => ['nullable', 'string', 'max:64'],
        ];
    }

    private function mail(array $data): ?array
    {
        if (array_key_exists('wifi_name', $data)) {
            BulkCredentials::saveWifiName($data['wifi_name']);
        }

        return $data['send_email'] ? BulkCredentials::links($data['login_url'] ?? null, [$data['alt_url'] ?? ''], $data['wifi_name'] ?? null) : null;
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

        return $this->csvRows($file->getRealPath());
    }

    /** @return list<array<string, string>> */
    private function csvRows(string $path): array
    {
        $handle = fopen($path, 'r');
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
