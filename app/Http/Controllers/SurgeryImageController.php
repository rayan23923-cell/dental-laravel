<?php

namespace App\Http\Controllers;

use App\Http\Controllers\Concerns\RendersSatelliteForm;
use App\Models\SurgeryImage;
use App\Support\SurgerySatelliteForms;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Surgery image — a satellite record of a surgery. Unlike the other
 * satellites this one takes a real file upload: `image_path` stores the
 * stored path, and the form is fed an `image_path_url` preview alongside it.
 */
class SurgeryImageController extends Controller
{
    use RendersSatelliteForm;

    private function sections(): array
    {
        return SurgerySatelliteForms::image();
    }

    public function index(): Response
    {
        return Inertia::render('Specialty/Index', [
            'resource' => 'surgery-images',
            'title' => 'Surgery Images',
            'titleField' => 'id',
            'records' => SurgeryImage::with('surgery')->latest('id')->paginate(15),
        ]);
    }

    public function create(): Response
    {
        return $this->renderSatelliteForm('surgery-images', 'Surgery Image', $this->sections(), null);
    }

    public function edit(SurgeryImage $record): Response
    {
        return $this->renderSatelliteForm('surgery-images', 'Surgery Image', $this->sections(), $this->withPreview($record));
    }

    public function show(SurgeryImage $record): Response
    {
        return $this->renderSatelliteForm('surgery-images', 'Surgery Image', $this->sections(), $this->withPreview($record), readonly: true);
    }

    public function store(Request $request): RedirectResponse
    {
        $data = $this->validateImage($request);
        $data['image_path'] = $request->file('image_path')->store('surgeries', 'public');

        SurgeryImage::create($data);

        return redirect()->route('surgery-images.index')->with('success', 'Surgery image uploaded.');
    }

    public function update(Request $request, SurgeryImage $record): RedirectResponse
    {
        $data = $this->validateImage($request, required: false);

        if ($request->hasFile('image_path')) {
            if ($record->image_path) {
                Storage::disk('public')->delete($record->image_path);
            }
            $data['image_path'] = $request->file('image_path')->store('surgeries', 'public');
        } else {
            // No new file picked — keep the stored path rather than nulling it.
            unset($data['image_path']);
        }

        $record->update($data);

        return redirect()->route('surgery-images.index')->with('success', 'Surgery image updated.');
    }

    public function destroy(SurgeryImage $record): RedirectResponse
    {
        if ($record->image_path) {
            Storage::disk('public')->delete($record->image_path);
        }

        $record->delete();

        return redirect()->route('surgery-images.index')->with('success', 'Surgery image deleted.');
    }

    private function withPreview(SurgeryImage $record): array
    {
        return [
            ...$record->toArray(),
            'image_path_url' => $record->image_path ? Storage::disk('public')->url($record->image_path) : null,
        ];
    }

    private function validateImage(Request $request, bool $required = true): array
    {
        return $this->satelliteValidate($request, $this->sections(), [
            'surgery_id' => ['required', 'exists:surgeries,id'],
            'image_type' => ['required', 'in:preop,intraop,postop'],
            'image_path' => [$required ? 'required' : 'nullable', 'image', 'max:5120'],
        ]);
    }
}
