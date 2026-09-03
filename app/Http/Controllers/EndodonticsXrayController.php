<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

/**
 * Web (session-auth) twin of `Api\EndodonticsXrayController` — same
 * stateless "store one image, hand back its path/url" shape, called via
 * axios from `Components/EndodonticsCanalTable.vue` rather than through
 * Inertia's page-visit router (a single JSON POST, not a page navigation).
 * See the API controller's own doc comment for why this has no parent id
 * and isn't behind the `case-sheet` middleware.
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
