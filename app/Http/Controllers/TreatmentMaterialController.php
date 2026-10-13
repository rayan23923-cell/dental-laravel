<?php

namespace App\Http\Controllers;

use App\Http\Controllers\Concerns\RendersSatelliteForm;
use App\Models\{TreatmentMaterial};
use App\Support\CaseSheetReturn;
use App\Support\SurgerySatelliteForms;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Treatment Material — one of the small satellite records attached to a parent case
 * sheet rather than a standalone sheet of its own. Layout in
 * App\Support\SurgerySatelliteForms.
 */
class TreatmentMaterialController extends Controller
{
    use RendersSatelliteForm;

    private function sections(): array
    {
        return SurgerySatelliteForms::treatmentMaterial();
    }

    public function index(): Response
    {
        return Inertia::render('Specialty/Index', [
            'resource' => 'treatment-materials',
            'title' => 'Treatment Materials',
            'titleField' => 'id',
            'records' => TreatmentMaterial::with('toothTreatment')->latest('id')->paginate(15),
        ]);
    }

    public function create(): Response
    {
        return $this->renderSatelliteForm('treatment-materials', 'Treatment Material', $this->sections(), null);
    }

    public function edit(TreatmentMaterial $record): Response
    {
        return $this->renderSatelliteForm('treatment-materials', 'Treatment Material', $this->sections(), $record);
    }

    public function show(TreatmentMaterial $record): Response
    {
        return $this->renderSatelliteForm('treatment-materials', 'Treatment Material', $this->sections(), $record, readonly: true);
    }

    public function store(Request $request): RedirectResponse
    {
        TreatmentMaterial::create($this->satelliteValidate($request, $this->sections(), ['tooth_treatment_id' => ['required', 'exists:tooth_treatments,id'], 'material_name' => ['required', 'string', 'max:255']]));

        return CaseSheetReturn::redirect()->with('success', 'Treatment material created.');
    }

    public function update(Request $request, TreatmentMaterial $record): RedirectResponse
    {
        $record->update($this->satelliteValidate($request, $this->sections(), ['tooth_treatment_id' => ['required', 'exists:tooth_treatments,id'], 'material_name' => ['required', 'string', 'max:255']]));

        return CaseSheetReturn::redirect()->with('success', 'Treatment material updated.');
    }

    public function destroy(TreatmentMaterial $record): RedirectResponse
    {
        $record->delete();

        return CaseSheetReturn::redirect()->with('success', 'Treatment material deleted.');
    }
}
