<?php

namespace App\Support;

use Illuminate\Http\UploadedFile;
use PhpOffice\PhpSpreadsheet\Cell\Coordinate;
use PhpOffice\PhpSpreadsheet\Cell\DataType;
use PhpOffice\PhpSpreadsheet\IOFactory;
use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Style\Fill;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Excel files for moving doctors, services and tasks between the hosted
 * and the offline system (2026-10-18, by request). The first row holds
 * the column names, and reading matches columns by those names, so a
 * column moved or added in Excel still imports.
 */
class ExcelTransfer
{
    /** @param  array<int, array<int, mixed>>  $rows */
    public static function download(array $headers, iterable $rows, string $name): StreamedResponse
    {
        $spreadsheet = new Spreadsheet();
        $sheet = $spreadsheet->getActiveSheet();
        $sheet->setRightToLeft(true);

        foreach ($headers as $i => $header) {
            $sheet->setCellValue(Coordinate::stringFromColumnIndex($i + 1).'1', $header);
        }
        $last = Coordinate::stringFromColumnIndex(count($headers));
        $sheet->getStyle("A1:{$last}1")->applyFromArray([
            'font' => ['bold' => true, 'color' => ['rgb' => 'FFFFFF']],
            'fill' => ['fillType' => Fill::FILL_SOLID, 'startColor' => ['rgb' => '4472C4']],
        ]);

        $r = 2;
        foreach ($rows as $row) {
            foreach (array_values($row) as $i => $value) {
                // As text, so usernames and phones keep their leading zeros.
                $sheet->setCellValueExplicit(Coordinate::stringFromColumnIndex($i + 1).$r, $value === null ? '' : (string) $value, DataType::TYPE_STRING);
            }
            $r++;
        }
        for ($i = 1; $i <= count($headers); $i++) {
            $sheet->getColumnDimension(Coordinate::stringFromColumnIndex($i))->setAutoSize(true);
        }

        $writer = IOFactory::createWriter($spreadsheet, 'Xlsx');

        return response()->streamDownload(fn () => $writer->save('php://output'), $name.'_'.now()->format('Ymd_His').'.xlsx', [
            'Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ]);
    }

    /**
     * The sheet's rows as [column name => trimmed text], skipping empty rows.
     *
     * @return array<int, array<string, string>>
     */
    public static function read(UploadedFile $file): array
    {
        $rows = IOFactory::load($file->getRealPath())->getActiveSheet()->toArray(null, true, false);
        $headers = array_map(fn ($h) => self::key($h), array_shift($rows) ?? []);

        return collect($rows)
            ->map(fn ($row) => collect($headers)->mapWithKeys(fn ($h, $i) => [$h => trim((string) ($row[$i] ?? ''))])->all())
            ->filter(fn ($row) => implode('', $row) !== '')
            ->values()->all();
    }

    public static function key(mixed $header): string
    {
        return strtolower(trim((string) $header));
    }

    /** Comma-separated names (Arabic or Latin comma) as a list. */
    public static function names(?string $value): array
    {
        return collect(preg_split('/\s*[,،]\s*/u', (string) $value))->map(fn ($n) => trim($n))->filter()->unique()->values()->all();
    }
}
