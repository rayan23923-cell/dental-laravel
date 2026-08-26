<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\SurgeryImageResource;
use App\Models\SurgeryImage;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class SurgeryImageController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $records = SurgeryImage::query()
            ->when($request->integer('surgery_id'), fn ($q, $id) => $q->where('surgery_id', $id))
            ->latest('id')
            ->paginate(15);

        return SurgeryImageResource::collection($records)->response();
    }

    public function show(SurgeryImage $record): JsonResponse
    {
        return (new SurgeryImageResource($record))->response();
    }

    /**
     * Accepts an actual uploaded image file (`image`, multipart) rather
     * than a pre-existing path string — stores it on the public disk under
     * surgeries/{surgery_id}/ and saves the resulting path to image_path.
     */
    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'surgery_id' => ['required', 'integer', 'exists:surgeries,id'],
            'image' => ['required', 'image', 'max:5120'],
            'image_type' => ['nullable', 'string', 'max:255'],
            'description' => ['nullable', 'string'],
        ]);

        $path = $request->file('image')->store("surgeries/{$validated['surgery_id']}", 'public');

        $record = SurgeryImage::create([
            'surgery_id' => $validated['surgery_id'],
            'image_path' => $path,
            'image_type' => $validated['image_type'] ?? null,
            'description' => $validated['description'] ?? null,
            'uploaded_at' => now(),
        ]);

        return (new SurgeryImageResource($record))->response()->setStatusCode(201);
    }

    public function update(Request $request, SurgeryImage $record): JsonResponse
    {
        $validated = $request->validate([
            'image_type' => ['nullable', 'string', 'max:255'],
            'description' => ['nullable', 'string'],
        ]);

        $record->update($validated);

        return (new SurgeryImageResource($record))->response();
    }

    public function destroy(SurgeryImage $record): JsonResponse
    {
        Storage::disk('public')->delete($record->image_path);

        $record->delete();

        return response()->json(null, 204);
    }
}
