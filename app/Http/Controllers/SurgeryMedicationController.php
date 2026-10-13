<?php

namespace App\Http\Controllers;

use App\Http\Controllers\Concerns\RendersSatelliteForm;
use App\Models\{SurgeryMedication};
use App\Support\CaseSheetReturn;
use App\Support\SurgerySatelliteForms;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Surgery Medication — one of the small satellite records attached to a parent case
 * sheet rather than a standalone sheet of its own. Layout in
 * App\Support\SurgerySatelliteForms.
 */
class SurgeryMedicationController extends Controller
{
    use RendersSatelliteForm;

    private function sections(): array
    {
        return SurgerySatelliteForms::medication();
    }

    public function index(): Response
    {
        return Inertia::render('Specialty/Index', [
            'resource' => 'surgery-medications',
            'title' => 'Surgery Medications',
            'titleField' => 'id',
            'records' => SurgeryMedication::with('surgery')->latest('id')->paginate(15),
        ]);
    }

    public function create(): Response
    {
        return $this->renderSatelliteForm('surgery-medications', 'Surgery Medication', $this->sections(), null);
    }

    public function edit(SurgeryMedication $record): Response
    {
        return $this->renderSatelliteForm('surgery-medications', 'Surgery Medication', $this->sections(), $record);
    }

    public function show(SurgeryMedication $record): Response
    {
        return $this->renderSatelliteForm('surgery-medications', 'Surgery Medication', $this->sections(), $record, readonly: true);
    }

    public function store(Request $request): RedirectResponse
    {
        SurgeryMedication::create($this->satelliteValidate($request, $this->sections(), ['surgery_id' => ['required', 'exists:surgeries,id'], 'medication_name' => ['required', 'string', 'max:255']]));

        return CaseSheetReturn::redirect()->with('success', 'Surgery medication created.');
    }

    public function update(Request $request, SurgeryMedication $record): RedirectResponse
    {
        $record->update($this->satelliteValidate($request, $this->sections(), ['surgery_id' => ['required', 'exists:surgeries,id'], 'medication_name' => ['required', 'string', 'max:255']]));

        return CaseSheetReturn::redirect()->with('success', 'Surgery medication updated.');
    }

    public function destroy(SurgeryMedication $record): RedirectResponse
    {
        $record->delete();

        return CaseSheetReturn::redirect()->with('success', 'Surgery medication deleted.');
    }
}
