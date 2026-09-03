<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

/**
 * A single stateless upload — accepts one X-ray image and returns where it
 * landed, nothing more. `App\Support\OperativeForm`'s endodontics
 * `first_visit_data.{canal}.wl_xray` cell (2026-09-03, by request — "صورة
 * الطول تكون عبر رفع صور للاشعة وليس حقل ادخال نصي") stores the returned
 * `path` as its value, exactly like it already stored a free-typed string
 * there before: no schema change, no new table, `endodontics_data` stays
 * the same JSON blob it always was.
 *
 * Unlike `SurgeryImageController` (a real satellite table keyed to an
 * existing `surgery_id`), there is deliberately no parent id here: a
 * doctor uploads a canal's X-ray while still composing a case sheet that
 * may not have an id yet (create flow), so nothing to scope the storage
 * path by. Files land under a flat `endodontics-xrays/` folder instead,
 * each with Laravel's own random filename — collisions aren't a concern
 * at this volume, and nothing ever lists this folder; every reference to
 * a file lives only inside the one case sheet's own JSON.
 */
class EndodonticsXrayController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $request->validate([
            'image' => ['required', 'image', 'max:5120'],
        ]);

        $path = $request->file('image')->store('endodontics-xrays', 'public');

        return response()->json([
            'path' => $path,
            'url' => Storage::disk('public')->url($path),
        ], 201);
    }
}
