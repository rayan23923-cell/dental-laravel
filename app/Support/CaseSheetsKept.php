<?php

namespace App\Support;

/**
 * The case sheets themselves are never deleted (2026-10-15, by request:
 * "ازل خاصية الحذف من النماذج السريرية لتجنب فقدانها"). Their delete routes
 * aren't registered and their lists show no delete button. Satellite
 * records (surgery images, medications, …) keep theirs.
 */
class CaseSheetsKept
{
    public const RESOURCES = [
        'advanced-periodontal-charts',
        'complete-denture-records',
        'oral-medicine-charts',
        'orthodontics-records',
        'periodontal-charts',
        'prevention-records',
        'prosthodontics-records',
        'surgeries',
    ];
}
