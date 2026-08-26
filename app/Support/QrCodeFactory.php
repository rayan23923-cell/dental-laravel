<?php

namespace App\Support;

use Endroid\QrCode\ErrorCorrectionLevel;
use Endroid\QrCode\QrCode;
use Endroid\QrCode\Writer\PngWriter;
use Illuminate\Http\Response;

/**
 * One place that turns a payload into a QR PNG response.
 *
 * The same five lines were copy-pasted in three controllers
 * (`Api\TaskInstanceQrController::show()`, `TaskInstanceController::qr()`,
 * `Doctor\PendingTasksQrController`); adding a fourth consumer
 * (`Api\PatientRegistrationQrController`) was the point to extract it
 * rather than make it four.
 *
 * Payload convention, unchanged from what those controllers already
 * emit: plain JSON `{"type": "<kind>", "id": <id>}` — see
 * `Api\TaskInstanceQrController`'s class docblock for why this codebase
 * standardized on one shape after the original app shipped three
 * incompatible ones.
 */
class QrCodeFactory
{
    /** Encode a `{type, id}` payload, the shape every scanner here expects. */
    public static function payload(string $type, int $id): string
    {
        return json_encode(['type' => $type, 'id' => $id]);
    }

    /** PNG response for an already-built payload string. */
    public static function pngResponse(string $payload, int $size = 300, string $cacheControl = 'public, max-age=3600'): Response
    {
        $result = (new PngWriter())->write(new QrCode(
            data: $payload,
            errorCorrectionLevel: ErrorCorrectionLevel::Medium,
            size: $size > 0 ? $size : 300,
            margin: 10,
        ));

        return response($result->getString(), 200, [
            'Content-Type' => $result->getMimeType(),
            'Cache-Control' => $cacheControl,
        ]);
    }

    /** Encode an arbitrary payload shape — for payloads that aren't the plain `{type, id}` pair. */
    public static function rawPayload(array $data): string
    {
        return json_encode($data);
    }
}
