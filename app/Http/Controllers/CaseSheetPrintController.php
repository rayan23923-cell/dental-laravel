<?php

namespace App\Http\Controllers;

use App\Models\ClinicSetting;
use App\Models\Doctor;
use App\Services\PermissionManager;
use App\Support\CaseSheetPrint;
use App\Support\CaseSheetPrintRenderer;
use Endroid\QrCode\ErrorCorrectionLevel;
use Endroid\QrCode\QrCode;
use Endroid\QrCode\Writer\PngWriter;
use Illuminate\Contracts\View\View;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Auth;

/**
 * Printable case sheets — port of the original's `doctor/*_print_html.php`
 * family (see App\Support\CaseSheetPrint for why the nine pages collapse
 * into one here).
 *
 * Blade rather than Inertia, exactly as the doctor roster/card printouts
 * are: these are standalone A4 documents opened in a new tab with their own
 * letterhead and `@page` rules, and wrapping them in the app shell would
 * print the navigation with them.
 */
class CaseSheetPrintController extends Controller
{
    public function show(string $resource, int $record): View
    {
        $config = CaseSheetPrint::config($resource);

        abort_unless($config, 404, 'Unknown case sheet type.');

        /** @var Model $model */
        $model = $config['model'];
        $sheet = $model::findOrFail($record);

        $this->authorizeSheet($sheet);

        $settings = ClinicSetting::current();
        $formClass = $config['form'];

        // Sheets that fold several inputs into one JSON column — derived
        // from the fields' own `group` keys (see
        // CaseSheetPrintRenderer::deriveGroupColumns() for why this isn't
        // a `method_exists($formClass, 'groupColumns')` call: most `*Form`
        // classes never implemented that static, which was silently
        // blanking every grouped field on their printouts).
        $groupColumns = CaseSheetPrintRenderer::deriveGroupColumns($formClass::sections());

        // Per-stage signature/date/grade tables (complete denture,
        // prosthodontics) print as their own bordered table.
        $stages = method_exists($formClass, 'stages') ? $formClass::stages() : [];

        // Per-tooth measurement grids (periodontal). The chart JSON lives in
        // its own column, named by the sheet's controller as `chartField`.
        $chartGroups = method_exists($formClass, 'chartGroups') ? $formClass::chartGroups() : [];
        $chartData = $chartGroups && $sheet->chart_data
            ? json_decode((string) $sheet->chart_data, true)
            : null;

        return view('print.case-sheet', [
            'settings' => $settings,
            'sheet' => $sheet,
            'sections' => CaseSheetPrintRenderer::sections($formClass::sections(), $sheet, $groupColumns),
            'stages' => CaseSheetPrintRenderer::stages($stages, $sheet),
            'charts' => CaseSheetPrintRenderer::charts($chartGroups, $chartData),
            'dentalChart' => CaseSheetPrintRenderer::dentalChart($formClass::sections(), $sheet),
            'title' => $config['title'],
            'department' => $config['department'] ?? null,
            'headerDepartment' => $config['headerDepartment'] ?? null,
            'doctorName' => $this->doctorName($sheet),
            'backUrl' => route("{$resource}.edit", $sheet->id),
            'qrDataUri' => $this->qrDataUri($resource, $sheet),
        ]);
    }

    /**
     * Same rule the original enforces at the top of every print page: a
     * doctor may only print their own sheet; a staff user needs the
     * `task_progress.open_case_sheet` permission — the very permission that
     * gates opening the sheet in the first place, so printing can't be a way
     * around it.
     */
    private function authorizeSheet(Model $sheet): void
    {
        $doctor = Auth::guard('doctor')->user();

        if ($doctor instanceof Doctor) {
            abort_unless((int) $sheet->doctor_id === $doctor->id, 403);

            return;
        }

        $user = Auth::user();
        abort_unless($user && (new PermissionManager($user))->can('task_progress', 'open_case_sheet'), 403);
    }

    private function doctorName(Model $sheet): ?string
    {
        if (! $sheet->doctor_id) {
            return null;
        }

        return Doctor::whereKey($sheet->doctor_id)->value('name');
    }

    /**
     * The original prints a QR that reopens the sheet itself — "Scan the QR
     * code to reopen this case sheet." Points at the task instance when the
     * sheet belongs to one, so scanning lands on the task as it does in the
     * original; otherwise at the record.
     */
    private function qrDataUri(string $resource, Model $sheet): string
    {
        $url = $sheet->task_instances_id
            ? route('case-sheet.open', $sheet->task_instances_id)
            : route("{$resource}.edit", $sheet->id);

        try {
            $result = (new PngWriter())->write(new QrCode(
                data: $url,
                errorCorrectionLevel: ErrorCorrectionLevel::Medium,
                size: 140,
                margin: 0,
            ));

            return $result->getDataUri();
        } catch (\Throwable) {
            // The original swallows QR failures and just omits the block
            // rather than failing the whole printout.
            return '';
        }
    }
}
