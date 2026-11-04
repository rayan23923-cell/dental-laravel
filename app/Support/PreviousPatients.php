<?php

namespace App\Support;

use App\Models\PatientRegistration;

/**
 * "مسجّل سابقاً" while registering a new patient (2026-11-04, by
 * request): as the desk types the name or the phone, earlier
 * registrations that match are suggested (a faint completion on the web
 * field and a tap-to-fill line in the apps), so a returning patient is
 * entered quickly and the same person isn't typed differently. It never
 * blocks typing: the clients ask in the background and ignore late
 * answers.
 */
class PreviousPatients
{
    public const LIMIT = 5;

    /**
     * Distinct earlier patients (same name + phone counted once, newest
     * visit first), exact name first, then names that start with what was
     * typed, then the rest.
     *
     * @return array<int, array{name: string, phone: string|null, visits: int, last_visit: string|null, exact_name: bool, exact_phone: bool}>
     */
    public static function suggest(?string $name, ?string $phone): array
    {
        $name = trim(preg_replace('/\s+/u', ' ', (string) $name));
        $digits = preg_replace('/\D/', '', strtr((string) $phone, [
            '٠' => '0', '١' => '1', '٢' => '2', '٣' => '3', '٤' => '4', '٥' => '5', '٦' => '6', '٧' => '7', '٨' => '8', '٩' => '9',
        ]));
        $useName = mb_strlen($name) >= 2;
        $usePhone = strlen($digits) >= 4;
        if (! $useName && ! $usePhone) {
            return [];
        }

        $rows = PatientRegistration::withTrashed()
            ->where(function ($q) use ($useName, $usePhone, $name, $digits) {
                if ($useName) {
                    $like = addcslashes($name, '%_\\');
                    $q->orWhere('name', 'like', $like.'%')->orWhere('name', 'like', '% '.$like.'%');
                }
                if ($usePhone) {
                    $q->orWhere('phone', 'like', '%'.$digits.'%');
                }
            })
            ->orderByDesc('created_at')
            ->limit(200)
            ->get(['id', 'name', 'phone', 'created_at']);

        $out = [];
        foreach ($rows as $row) {
            $key = mb_strtolower(trim((string) $row->name)).'|'.preg_replace('/\D/', '', (string) $row->phone);
            if (isset($out[$key])) {
                $out[$key]['visits']++;

                continue;
            }
            $rowName = trim(preg_replace('/\s+/u', ' ', (string) $row->name));
            $rowDigits = preg_replace('/\D/', '', (string) $row->phone);
            $out[$key] = [
                'name' => $rowName,
                'phone' => $row->phone,
                'visits' => 1,
                'last_visit' => $row->created_at?->toIso8601String(),
                'exact_name' => $useName && mb_strtolower($rowName) === mb_strtolower($name),
                'exact_phone' => $usePhone && $rowDigits === $digits,
                'name_prefix' => $useName && str_starts_with(mb_strtolower($rowName), mb_strtolower($name)),
            ];
        }

        $rank = fn (array $r) => match (true) {
            $r['exact_phone'] => 0,
            $r['exact_name'] => 1,
            $r['name_prefix'] => 2,
            default => 3,
        };
        $list = array_values($out);
        // Stable: within a rank, the newest visit stays first.
        $indexed = array_map(null, $list, array_keys($list));
        usort($indexed, fn ($a, $b) => [$rank($a[0]), $a[1]] <=> [$rank($b[0]), $b[1]]);

        return array_map(fn ($pair) => $pair[0], array_slice($indexed, 0, self::LIMIT));
    }
}
