<?php

namespace App\Support;

/**
 * The short, typeable twin of a case's QR (2026-10-30, by request): a
 * supervisor whose camera can't read the code types these digits instead.
 *
 * Digits only, so a phone's number pad is enough:
 * - a started case (`task_instance` QR): `1` + instance id + check digit;
 * - a task not started yet (`pending_task` QR): `2` + how many digits the
 *   task id has + task id + doctor id + check digit.
 *
 * The last digit is a Luhn check digit, so a mistyped or swapped digit is
 * refused instead of opening someone else's case. Spaces and dashes are
 * ignored when typed. Mirrored in `resources/js/caseCode.js` and the app's
 * `core/utils/case_code.dart` (the doctor's QR dialogs show it under the
 * QR); `toPayload()` turns it back into the QR's own JSON so every
 * scanner endpoint accepts either.
 */
class CaseCode
{
    public static function forInstance(int $instanceId): string
    {
        return self::withCheck('1'.$instanceId);
    }

    public static function forPending(int $taskId, int $doctorId): string
    {
        $task = (string) $taskId;

        return self::withCheck('2'.strlen($task).$task.$doctorId);
    }

    /** Groups of three for display, e.g. `145 238`. */
    public static function format(string $code): string
    {
        return trim(chunk_split($code, 3, ' '));
    }

    /** Whether the input looks like a typed code rather than a QR payload. */
    public static function looksTyped(string $input): bool
    {
        return (bool) preg_match('/^[\d\s\-]+$/', trim($input));
    }

    /**
     * The QR payload this typed code stands for, or null when it isn't a
     * valid code (wrong check digit, unknown kind, malformed).
     */
    public static function toPayload(string $input): ?string
    {
        $digits = preg_replace('/\D/', '', $input);
        if (strlen($digits) < 3 || ! self::validCheck($digits)) {
            return null;
        }
        $body = substr($digits, 0, -1);

        if ($body[0] === '1') {
            $id = substr($body, 1);

            return $id !== '' && $id[0] !== '0'
                ? QrCodeFactory::payload('task_instance', (int) $id)
                : null;
        }

        if ($body[0] === '2') {
            $length = (int) $body[1];
            $task = substr($body, 2, $length);
            $doctor = substr($body, 2 + $length);
            if ($length < 1 || strlen($task) !== $length || $doctor === '' || $task[0] === '0' || $doctor[0] === '0') {
                return null;
            }

            return QrCodeFactory::rawPayload([
                'type' => 'pending_task',
                'task_id' => (int) $task,
                'doctor_id' => (int) $doctor,
            ]);
        }

        return null;
    }

    /**
     * A scanned QR payload as is, or a typed code turned into one. Null
     * for a typed code that isn't valid, so the caller can say so.
     */
    public static function normalize(string $input): ?string
    {
        return self::looksTyped($input) ? self::toPayload($input) : $input;
    }

    private static function withCheck(string $body): string
    {
        return $body.self::luhnDigit($body);
    }

    private static function validCheck(string $digits): bool
    {
        return self::luhnDigit(substr($digits, 0, -1)) === (int) substr($digits, -1);
    }

    private static function luhnDigit(string $body): int
    {
        $sum = 0;
        $double = true;
        for ($i = strlen($body) - 1; $i >= 0; $i--) {
            $d = (int) $body[$i];
            if ($double) {
                $d *= 2;
                if ($d > 9) {
                    $d -= 9;
                }
            }
            $sum += $d;
            $double = ! $double;
        }

        return (10 - $sum % 10) % 10;
    }
}
